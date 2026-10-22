/-
  LSys/Provenance.lean

  T4b (`spec/semantics.md` T4 table, `spec/ub.md` §2) for **UB-8 / UB-9 / UB-10**:
  the RTT v1 (Region-Tag Tree) runtime model — tag trees, the A1–A6 access
  checks, and the provenance/alignment events.

  Design notes (and the deliberate boundary):

  * RTT tags are **erased for the safe subset** (`spec/ub.md` §2.1: safe code has
    no `rawptr`, RTT costs nothing at run time), so the tag tree lives in its own
    layer instead of a new field on the core `Cell`/`RVal`.  Pulling a `tag` into
    `Cell` would force the same edit through `Unified`/`StepBridge`/`EffHCK`/
    `WTKH` for a fragment (`unsafe`/`rawptr`) that F0 does not contain, so this
    module keeps the tree separate and proves a **bridge** to the core heap
    instead (`ProvWF`, `check_ok_live`): a checked access touches a live core
    cell.
  * `Ptr = (a, off, tag)` of `spec/ub.md` §2 is `Access` here (`alloc`/`off`/
    `tag`), with the pointee `align`, the access size and the `Witness` flag.
  * `check` is a total decision function returning a `Verdict`; `Verdict.ub`
    maps the failing verdict to the UB code: `rawUnsafe` (UB-8: null/wild),
    `unaligned` (UB-9), `provenance` (UB-10).  `check_ok_or_ub` is the oracle,
    `verdict_ub_outside` shows the codes are outside F0.

  Axioms: no `Classical`; all splits are constructor/`Bool` cases.
-/

import LSys.Runtime
import LSys.UBCode

namespace LSys

set_option linter.unusedVariables false

/-! ## 1. RTT v1: allocations and tag trees (`spec/ub.md` §2.1–2.3) -/

abbrev AllocId := Nat
abbrev TagId := Nat

inductive TagKind where
  | uniq
  | mut
  | frozen
  | raw
  deriving DecidableEq, Repr

inductive TagState where
  | act
  | res
  | froz
  | dis
  deriving DecidableEq, Repr

structure Tag where
  id : TagId
  parent : Option TagId
  kind : TagKind
  state : TagState
  deriving DecidableEq, Repr

structure Alloc where
  size : Nat
  /-- alignment of the allocation (bytes) -/
  align : Nat
  tags : List Tag
  deriving DecidableEq, Repr

/-- The provenance store: `AllocId ⇀ Alloc` as a list (so everything stays
    computable and concrete instances can be checked with `decide`). -/
structure Prov where
  allocs : List (AllocId × Alloc)

def lookupAlloc (p : Prov) (a : AllocId) : Option Alloc :=
  (p.allocs.find? (fun e => e.1 == a)).map Prod.snd

def findTag (al : Alloc) (t : TagId) : Option Tag :=
  al.tags.find? (fun x => x.id == t)

def parentOf (al : Alloc) (t : TagId) : Option TagId :=
  match findTag al t with
  | none => none
  | some tag => tag.parent

/-- `s` is an ancestor-or-self of `t`, with `fuel` bounding the parent walk
    (the tags list is finite, so `al.tags.length + 1` always suffices). -/
def reaches (al : Alloc) : Nat → TagId → TagId → Bool
  | 0, _, _ => false
  | fuel + 1, s, t =>
      if s == t then true
      else match parentOf al t with
        | none => false
        | some q => reaches al fuel s q

def anc (al : Alloc) (s t : TagId) : Bool := reaches al (al.tags.length + 1) s t

/-! ## 2. Accesses, verdicts and the A1–A6 checks -/

inductive RW where
  | read
  | write
  deriving DecidableEq, Repr

/-- `Access(t, off, sz, rw)` of `spec/ub.md` §2.4 plus the pointee alignment and
    the `Witness` flag (per-access contract). -/
structure Access where
  alloc : AllocId
  tag : TagId
  off : Nat
  sz : Nat
  align : Nat
  rw : RW
  witness : Bool
  deriving DecidableEq, Repr

inductive Verdict where
  | ok
  | nullDeref
  | wildDeref
  | noTag
  | disabled
  | outOfBounds
  | misaligned
  | writeNotActive
  | rawConflict
  deriving DecidableEq, Repr

/-- The UB code of a failing verdict (`none` for `ok`). -/
def Verdict.ub : Verdict → Option UBCode
  | .ok => none
  | .nullDeref => some UBCode.rawUnsafe
  | .wildDeref => some UBCode.rawUnsafe
  | .noTag => some UBCode.provenance
  | .disabled => some UBCode.provenance
  | .outOfBounds => some UBCode.provenance
  | .misaligned => some UBCode.unaligned
  | .writeNotActive => some UBCode.provenance
  | .rawConflict => some UBCode.provenance

/-- A3: the access must be aligned (`align > 0` and `off % align = 0`). -/
def alignOk (ac : Access) : Bool := ac.align != 0 && ac.off % ac.align == 0

/-- A2, as a `Bool` so the checks stay computable: `off + sz > size(a)`. -/
def overSize (al : Alloc) (ac : Access) : Bool := decide (al.size < ac.off + ac.sz)

theorem overSize_false {al : Alloc} {ac : Access} (h : overSize al ac = false) :
    ac.off + ac.sz ≤ al.size := by
  unfold overSize at h
  exact Nat.ge_of_not_lt (of_decide_eq_false h)

/-- A5/A6: does a *non-raw* live tag outside the raw tag's subtree conflict?

    * read  (A5): a live `act` `uniq`/`mut` tag outside `t`'s subtree;
    * write (A6): a live non-`raw` tag outside `t`'s subtree and not on `t`'s
      ancestor chain (ancestors are disabled by the write and are allowed). -/
def outsideConflict (al : Alloc) (ac : Access) : Bool :=
  match ac.rw with
  | RW.read =>
      al.tags.any (fun s =>
        s.state == TagState.act && (s.kind == TagKind.uniq || s.kind == TagKind.mut)
          && !(anc al ac.tag s.id))
  | RW.write =>
      al.tags.any (fun s =>
        s.state != TagState.dis && s.kind != TagKind.raw
          && !(anc al ac.tag s.id) && !(anc al s.id ac.tag))

/-- A1–A6 for a resolved tag.  The order of the checks fixes which code is
    reported first; every failing branch is a UB-8/9/10 verdict. -/
def checkTag' (al : Alloc) (ac : Access) (t : Tag) : Verdict :=
  if t.state == TagState.dis then .disabled
  else if overSize al ac then .outOfBounds
  else if !alignOk ac then .misaligned
  else if ac.rw == RW.write && t.state != TagState.act then .writeNotActive
  else if t.kind == TagKind.raw && !ac.witness && outsideConflict al ac then .rawConflict
  else .ok

/-- A1 (tag in the tree) then A2–A6. -/
def checkTagged (al : Alloc) (ac : Access) : Verdict :=
  match findTag al ac.tag with
  | none => .noTag
  | some t => checkTag' al ac t

/-- The whole check: null (UB-8) → unknown allocation (UB-8, wild pointer) →
    the tag tree checks. -/
def check (p : Prov) (ac : Access) : Verdict :=
  if ac.alloc == 0 then .nullDeref
  else match lookupAlloc p ac.alloc with
    | none => .wildDeref
    | some al => checkTagged al ac

/-! ### `Bool` equality helpers -/

theorem eq_of_beq_true' {α : Type} [DecidableEq α] {a b : α} (h : (a == b) = true) :
    a = b :=
  of_decide_eq_true (show decide (a = b) = true from h)

theorem beq_self' {α : Type} [DecidableEq α] (a : α) : (a == a) = true :=
  decide_eq_true rfl

theorem beq_self (a : Nat) : (a == a) = true := Nat.beq_refl a

theorem beq_true_of_bne_false {α : Type} [DecidableEq α] {a b : α}
    (h : (a != b) = false) : (a == b) = true := by
  have h2 : (!(a == b)) = false := h
  cases hb : (a == b) with
  | true => rfl
  | false =>
      exact absurd h2 (by rw [hb]; intro hc; cases hc)

/-! ## 3. Classification: `ok`, or a UB-8/9/10 code -/

/-- A successful `checkTag'` satisfies A2–A6 for that tag. -/
theorem checkTag'_ok {al : Alloc} {ac : Access} {t : Tag}
    (h : checkTag' al ac t = Verdict.ok) :
    t.state ≠ TagState.dis ∧ ac.off + ac.sz ≤ al.size ∧ alignOk ac = true ∧
      (ac.rw = RW.write → (t.state == TagState.act) = true) ∧
      (t.kind = TagKind.raw → ac.witness = true ∨ outsideConflict al ac = false) := by
  unfold checkTag' at h
  cases hdis : (t.state == TagState.dis) with
  | true => rw [hdis] at h; simp at h
  | false =>
      rw [hdis] at h
      cases hb : overSize al ac with
      | true => rw [hb] at h; simp at h
      | false =>
          rw [hb] at h
          cases hal : alignOk ac with
          | false => rw [hal] at h; simp at h
          | true =>
              rw [hal] at h
              cases hwa : (ac.rw == RW.write && t.state != TagState.act) with
              | true => rw [hwa] at h; simp at h
              | false =>
                  rw [hwa] at h
                  cases hraw : (t.kind == TagKind.raw && !ac.witness && outsideConflict al ac) with
                  | true => rw [hraw] at h; simp at h
                  | false =>
                      refine ⟨?_, overSize_false hb, rfl, ?_, ?_⟩
                      · intro hd
                        rw [hd] at hdis
                        cases hdis
                      · intro hrw
                        rw [hrw] at hwa
                        rw [beq_self' RW.write, Bool.true_and] at hwa
                        exact beq_true_of_bne_false hwa
                      · intro hkind
                        rw [hkind] at hraw
                        cases hw : ac.witness with
                        | true => exact Or.inl rfl
                        | false =>
                            exact Or.inr (by
                              simp only [hw, Bool.not_false, Bool.and_true,
                                Bool.true_and] at hraw
                              exact hraw)

/-- A successful `checkTagged` resolves a tag that itself passes A2–A6. -/
theorem checkTagged_ok {al : Alloc} {ac : Access}
    (h : checkTagged al ac = Verdict.ok) :
    ∃ t, findTag al ac.tag = some t ∧ checkTag' al ac t = Verdict.ok := by
  unfold checkTagged at h
  cases hf : findTag al ac.tag with
  | none => rw [hf] at h; simp at h
  | some t =>
      simp only [hf] at h
      refine ⟨t, ?_, h⟩
      first
        | exact hf
        | rfl

/-- A successful `check` finds the allocation (the tag checks are discharged by
    `checkTagged_ok`). -/
theorem check_ok_lookup {p : Prov} {ac : Access} (h : check p ac = Verdict.ok) :
    ∃ al, lookupAlloc p ac.alloc = some al := by
  unfold check at h
  cases hn : (ac.alloc == 0) with
  | true => rw [hn] at h; simp at h
  | false =>
      rw [hn] at h
      cases hl : lookupAlloc p ac.alloc with
      | none => rw [hl] at h; simp at h
      | some al =>
          refine ⟨al, ?_⟩
          first
            | exact hl
            | rfl

/-- **The oracle**: every access either passes the checks, or `check` yields a
    UB-8/9/10 code. -/
theorem check_ok_or_ub (p : Prov) (ac : Access) :
    check p ac = Verdict.ok ∨ ∃ k, Verdict.ub (check p ac) = some k := by
  cases h : check p ac with
  | ok => exact Or.inl rfl
  | nullDeref => exact Or.inr ⟨UBCode.rawUnsafe, rfl⟩
  | wildDeref => exact Or.inr ⟨UBCode.rawUnsafe, rfl⟩
  | noTag => exact Or.inr ⟨UBCode.provenance, rfl⟩
  | disabled => exact Or.inr ⟨UBCode.provenance, rfl⟩
  | outOfBounds => exact Or.inr ⟨UBCode.provenance, rfl⟩
  | misaligned => exact Or.inr ⟨UBCode.unaligned, rfl⟩
  | writeNotActive => exact Or.inr ⟨UBCode.provenance, rfl⟩
  | rawConflict => exact Or.inr ⟨UBCode.provenance, rfl⟩

/-- Every UB code the model can report is outside F0. -/
theorem verdict_ub_outside {v : Verdict} {k : UBCode} (h : Verdict.ub v = some k) :
    OutsideF0 k := by
  cases v with
  | ok => simp [Verdict.ub] at h
  | nullDeref => cases h; simp [OutsideF0]
  | wildDeref => cases h; simp [OutsideF0]
  | noTag => cases h; simp [OutsideF0]
  | disabled => cases h; simp [OutsideF0]
  | outOfBounds => cases h; simp [OutsideF0]
  | misaligned => cases h; simp [OutsideF0]
  | writeNotActive => cases h; simp [OutsideF0]
  | rawConflict => cases h; simp [OutsideF0]

/-- `rawConflict` on a resolved tag implies a `raw` tag without a `Witness`:
    this is what keeps A5/A6 out of the safe subset (no `rawptr`). -/
theorem checkTag'_rawConflict {al : Alloc} {ac : Access} {t : Tag}
    (h : checkTag' al ac t = Verdict.rawConflict) :
    t.kind = TagKind.raw ∧ ac.witness = false ∧ outsideConflict al ac = true := by
  unfold checkTag' at h
  cases hdis : (t.state == TagState.dis) with
  | true => rw [hdis] at h; simp at h
  | false =>
      rw [hdis] at h
      cases hb : overSize al ac with
      | true => rw [hb] at h; simp at h
      | false =>
          rw [hb] at h
          cases hal : alignOk ac with
          | false => rw [hal] at h; simp at h
          | true =>
              rw [hal] at h
              cases hwa : (ac.rw == RW.write && t.state != TagState.act) with
              | true => rw [hwa] at h; simp at h
              | false =>
                  rw [hwa] at h
                  cases hraw : (t.kind == TagKind.raw && !ac.witness && outsideConflict al ac) with
                  | false => rw [hraw] at h; simp at h
                  | true =>
                      simp only [Bool.and_eq_true] at hraw
                      refine ⟨eq_of_beq_true' hraw.1.1, ?_, hraw.2⟩
                      cases hw : ac.witness with
                      | false => rfl
                      | true =>
                          have hnot : (!ac.witness) = true := hraw.1.2
                          rw [hw] at hnot
                          cases hnot

/-- `rawConflict` on a whole allocation implies the resolved tag is `raw`. -/
theorem rawConflict_implies_raw {al : Alloc} {ac : Access}
    (h : checkTagged al ac = Verdict.rawConflict) :
    ∃ t, findTag al ac.tag = some t ∧ t.kind = TagKind.raw ∧
      ac.witness = false ∧ outsideConflict al ac = true := by
  unfold checkTagged at h
  cases hf : findTag al ac.tag with
  | none => rw [hf] at h; simp at h
  | some t =>
      simp only [hf] at h
      cases checkTag'_rawConflict h with
      | intro hkind rest =>
          refine ⟨t, ?_, hkind, rest⟩
          first
            | exact hf
            | rfl

/-! ## 4. Pointer operations from `spec/ub.md` §2.4 -/

/-- `p + k`: forming a pointer outside `[0, size]` disables the tag (UB-10 once
    it is dereferenced). -/
def ptrAdd (al : Alloc) (off k : Nat) : Option UBCode :=
  if off + k > al.size then some UBCode.provenance else none

/-- `p - q`: both pointers must belong to the same allocation. -/
def ptrSub (a b : AllocId) : Option UBCode :=
  if a == b then none else some UBCode.provenance

/-- `int → raw` without a `Witness` is UB-10: RTT v1 does not launder
    provenance (`spec/ub.md` §2.4 / RTT-4). -/
def intToRaw (witness : Bool) : Verdict :=
  if witness then .ok else .noTag

/-- `recover` requires that no live `frozen` (`val`) copy remains. -/
def recoverVerdict (al : Alloc) : Verdict :=
  if al.tags.any (fun t => t.state == TagState.froz) then .rawConflict else .ok

theorem ptr_add_out_of_bounds {al : Alloc} {off k : Nat} (h : al.size < off + k) :
    ptrAdd al off k = some UBCode.provenance := by
  unfold ptrAdd
  rw [if_pos h]

theorem ptr_add_in_bounds {al : Alloc} {off k : Nat} (h : ¬ al.size < off + k) :
    ptrAdd al off k = none := by
  unfold ptrAdd
  rw [if_neg h]

theorem ptr_sub_same (a : AllocId) : ptrSub a a = none := by
  unfold ptrSub
  rw [if_pos (beq_self a)]

theorem ptr_sub_other {a b : AllocId} (h : a ≠ b) :
    ptrSub a b = some UBCode.provenance := by
  unfold ptrSub
  rw [if_neg (by intro hb; exact h (eq_of_beq_true hb))]

theorem int_to_raw_needs_witness : intToRaw false = Verdict.noTag := rfl

theorem int_to_raw_with_witness : intToRaw true = Verdict.ok := rfl

/-! ## 5. The core bridge: a checked access touches a live core cell -/

/-- Well-formedness linking the RTT store to the core heap: every allocation id
    in the store is a live cell of `LSys.Conf`. -/
def ProvWF (p : Prov) (c : Conf) : Prop :=
  ∀ (a : AllocId) (al : Alloc), lookupAlloc p a = some al → liveB c a = true

/-- A checked access touches a live cell of the core heap. -/
theorem check_ok_live {p : Prov} {c : Conf} {ac : Access} (hwf : ProvWF p c)
    (h : check p ac = Verdict.ok) : liveB c ac.alloc = true := by
  cases check_ok_lookup h with
  | intro al hl => exact hwf _ _ hl

/-! ## 6. Concrete RTT v1 oracles (`spec/ub.md` §2.6) -/

def tag (id : TagId) (parent : Option TagId) (kind : TagKind) (state : TagState) : Tag :=
  { id := id, parent := parent, kind := kind, state := state }

def alloc (size align : Nat) (tags : List Tag) : Alloc :=
  { size := size, align := align, tags := tags }

def prov (as : List (AllocId × Alloc)) : Prov := { allocs := as }

def acc (alloc : AllocId) (tag : TagId) (off sz align : Nat) (rw : RW)
    (witness : Bool) : Access :=
  { alloc := alloc, tag := tag, off := off, sz := sz, align := align, rw := rw,
    witness := witness }

/-- One allocation `1` of 16 bytes: root `uniq/act`, a raw child `raw/act` whose
    parent was demoted to `res` (the `raw(p)` rule of `spec/ub.md` §2.3). -/
def pRaw : Prov :=
  prov [(1, alloc 16 8 [tag 0 none TagKind.uniq TagState.res,
                        tag 1 (some 0) TagKind.raw TagState.act])]

/-- Plain allocation: root `uniq/act`. -/
def pBase : Prov := prov [(1, alloc 16 8 [tag 0 none TagKind.uniq TagState.act])]

/-- RTT-1: `base + len` then deref ⇒ out-of-bounds derivation (UB-10). -/
theorem rtt1_out_of_bounds :
    check pBase (acc 1 0 16 1 1 RW.read false) = Verdict.outOfBounds := by
  decide

/-- RTT-2a: the raw write itself is fine (only the demoted ancestor is outside
    the subtree and ancestors are exempt by A6). -/
theorem rtt2_raw_write_ok :
    check pRaw (acc 1 1 0 8 8 RW.write false) = Verdict.ok := by
  decide

/-- RTT-2b: `*r` after the raw write — the parent tag is `dis` ⇒ UB-10. -/
theorem rtt2_after_write_disabled :
    check (prov [(1, alloc 16 8 [tag 0 none TagKind.uniq TagState.dis,
                                 tag 1 (some 0) TagKind.raw TagState.act])])
      (acc 1 0 0 8 8 RW.read false) = Verdict.disabled := by
  decide

/-- RTT-3: writing a `frozen` tag ⇒ UB-10 (A4). -/
theorem rtt3_frozen_write :
    check (prov [(1, alloc 16 8 [tag 0 none TagKind.frozen TagState.froz])])
      (acc 1 0 0 8 8 RW.write false) = Verdict.writeNotActive := by
  decide

/-- RTT-4: `int → raw` without a `Witness` is UB-10 (no provenance laundering). -/
theorem rtt4_int_to_raw : intToRaw false = Verdict.noTag := rfl

theorem rtt4_int_to_raw_is_ub10 :
    Verdict.ub (intToRaw false) = some UBCode.provenance := rfl

/-- RTT-4 (wild pointer): an address that is not an allocation ⇒ UB-8. -/
theorem rtt4_wild_pointer :
    check pBase (acc 4096 0 0 1 1 RW.read false) = Verdict.wildDeref := by
  decide

/-- RTT-5: a child tag after its borrow ended (`dis`) ⇒ UB-10. -/
theorem rtt5_child_disabled :
    check (prov [(1, alloc 16 8 [tag 0 none TagKind.uniq TagState.act,
                                 tag 2 (some 0) TagKind.mut TagState.dis])])
      (acc 1 2 0 8 8 RW.read false) = Verdict.disabled := by
  decide

/-- RTT-6: `recover` with a live `val` copy ⇒ alias not consumed (UB-10). -/
theorem rtt6_recover_with_live_val :
    recoverVerdict (alloc 16 8 [tag 0 none TagKind.uniq TagState.act,
                                tag 1 (some 0) TagKind.frozen TagState.froz])
      = Verdict.rawConflict := by
  decide

/-- RTT-7: a raw read with no live `act uniq/mut` outside the raw subtree is
    allowed (the parent was demoted to `res`). -/
theorem rtt7_raw_read_ok :
    check pRaw (acc 1 1 0 8 8 RW.read false) = Verdict.ok := by
  decide

/-- RTT-8: after the child borrow ends, the parent is `act` again ⇒ allowed. -/
theorem rtt8_parent_after_child_ok :
    check (prov [(1, alloc 16 8 [tag 0 none TagKind.uniq TagState.act,
                                 tag 2 (some 0) TagKind.mut TagState.dis])])
      (acc 1 0 0 8 8 RW.read false) = Verdict.ok := by
  decide

/-- RTT-9: `p - q` across allocations ⇒ UB-10. -/
theorem rtt9_ptr_sub_other : ptrSub 1 2 = some UBCode.provenance := by
  decide

theorem rtt9_ptr_sub_same : ptrSub 1 1 = none := by
  decide

/-- RTT-10: writing a `res` tag ⇒ UB-10 (A4). -/
theorem rtt10_res_write :
    check (prov [(1, alloc 16 8 [tag 0 none TagKind.uniq TagState.res])])
      (acc 1 0 0 8 8 RW.write false) = Verdict.writeNotActive := by
  decide

/-- A `Witness` exempts the raw A5/A6 checks (raw read with a conflicting live
    `uniq/act` inside the same allocation). -/
def pRawConflict : Prov :=
  prov [(1, alloc 16 8 [tag 0 none TagKind.uniq TagState.act,
                        tag 1 none TagKind.raw TagState.act])]

theorem witness_exempts_raw_conflict :
    check pRawConflict (acc 1 1 0 8 8 RW.read false) = Verdict.rawConflict := by
  decide

theorem witness_allows_raw_read :
    check pRawConflict (acc 1 1 0 8 8 RW.read true) = Verdict.ok := by
  decide

/-- UB-9: an unaligned raw read ⇒ `unaligned`. -/
theorem ub9_misaligned :
    check pRaw (acc 1 1 4 8 8 RW.read false) = Verdict.misaligned := by
  decide

/-- UB-8: the null allocation id is a null dereference. -/
theorem ub8_null :
    check pBase (acc 0 0 0 1 1 RW.read false) = Verdict.nullDeref := by
  decide

/-- UB-10 needs a `raw` tag: a `rawConflict` verdict always carries one. -/
theorem rawConflict_is_raw {al : Alloc} {ac : Access}
    (h : checkTagged al ac = Verdict.rawConflict) :
    ∃ t, findTag al ac.tag = some t ∧ t.kind = TagKind.raw := by
  cases rawConflict_implies_raw h with
  | intro t rest =>
      exact ⟨t, rest.1, rest.2.1⟩

end LSys
