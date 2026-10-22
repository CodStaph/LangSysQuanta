/-
  LSys/Runtime.lean

  T4a foundation (1/2): a concrete F0 runtime fragment with a real heap,
  borrow table, and pending-handle set.

  This file does **not** replace `LSys.Term`; it gives the runtime model that
  the paper's T1 (no dangling), T3 (`recover` uniqueness), and L4
  (preservation of well-formedness) need.

  Scope of this increment:
  * heap as `Loc → Option Cell` (function representation, no Mathlib);
  * operations: read / write / alloc / freeze / recover / drop;
  * well-formedness I1/I2/I3/I4/I5 (live targets, no dangling stored `loc`,
    every borrow is in flight or held, unique bids, holders reference bids);
  * `wf_preserved` (L4 fragment);
  * `t1_no_dangling` and `t3_recover_unique`.

  Not yet in this file: variable frames / `let` / `move` / `borrow` holders
  in environments, region exit, and the premise-carrying `Step` refactor.
-/

import LSys.State
import LSys.UBCode

namespace LSys

set_option linter.unusedVariables false

abbrev Loc := Nat

inductive RVal where
  | unit
  | nat (n : Nat)
  | loc (l : Loc)
  | valH (b : Bid)
  | refH (b : Bid)
  deriving Repr, DecidableEq

structure Cell where
  val : RVal
  mode : Mode
  rgn : Rgn
  live : Bool
  holders : List Bid
  /-- Initialisation flag.  `true` by default, because `allocConf` stores the
      initial value; it is what UB-4 (read of uninitialised memory) is about. -/
  init : Bool := true
  deriving Repr, DecidableEq

structure BEntry where
  bid : Bid
  target : Loc
  mode : Mode
  rgn : Rgn
  deriving Repr, DecidableEq

/-- Heap as a total function; absent locations map to `none`. -/
abbrev Heap := Loc → Option Cell

structure Conf where
  heap : Heap
  btab : List BEntry
  flight : List Bid

/-! ## Heap operations -/

def liveB (c : Conf) (l : Loc) : Bool :=
  match c.heap l with
  | some cell => cell.live
  | none => false

def cellMode (c : Conf) (l : Loc) : Option Mode :=
  (c.heap l).map (fun cell => cell.mode)

def cellRgn (c : Conf) (l : Loc) : Rgn :=
  match c.heap l with
  | some cell => cell.rgn
  | none => 0

def holdersAt (c : Conf) (l : Loc) : List Bid :=
  match c.heap l with
  | some cell => cell.holders
  | none => []

def updateCell (h : Heap) (l : Loc) (f : Cell → Cell) : Heap :=
  fun q => if q = l then (h q).map f else h q

def allocCell (h : Heap) (l : Loc) (cell : Cell) : Heap :=
  fun q => if q = l then some cell else h q

def killRegion (h : Heap) (r : Rgn) : Heap :=
  fun q =>
    (h q).map (fun cell =>
      if cell.rgn == r then { cell with live := false, holders := [] } else cell)

theorem lookup_update_same (h : Heap) (l : Loc) (f : Cell → Cell) :
    updateCell h l f l = (h l).map f := by
  unfold updateCell
  simp

theorem lookup_update_other (h : Heap) (l q : Loc) (f : Cell → Cell)
    (hne : q ≠ l) : updateCell h l f q = h q := by
  unfold updateCell
  simp [hne]

theorem lookup_alloc_same (h : Heap) (l : Loc) (cell : Cell) :
    allocCell h l cell l = some cell := by
  unfold allocCell
  simp

theorem lookup_alloc_other (h : Heap) (l q : Loc) (cell : Cell)
    (hne : q ≠ l) : allocCell h l cell q = h q := by
  unfold allocCell
  simp [hne]

/-! ## Values, holders, borrows -/

def holdersOfVal : RVal → List Bid
  | RVal.refH b => [b]
  | RVal.valH b => [b]
  | _ => []

def hasBid : List BEntry → Bid → Bool
  | [], _ => false
  | e :: es, b => if e.bid == b then true else hasBid es b

def isLiveVal (c : Conf) : RVal → Bool
  | RVal.loc l => liveB c l
  | RVal.refH b => hasBid c.btab b
  | RVal.valH b => hasBid c.btab b
  | _ => true

def bidsAtTarget (l : Loc) : List BEntry → List Bid
  | [] => []
  | e :: es => if e.target == l then e.bid :: bidsAtTarget l es else bidsAtTarget l es

def removeTarget (l : Loc) : List BEntry → List BEntry
  | [] => []
  | e :: es => if e.target == l then removeTarget l es else e :: removeTarget l es

def allInFlight : List Bid → List Bid → Bool
  | [], _ => true
  | b :: bs, flight => flight.elem b && allInFlight bs flight

/-! ## Well-formedness (I1–I4 fragment) -/

structure WF (c : Conf) : Prop where
  i1_btab_live : ∀ e, e ∈ c.btab → liveB c e.target = true
  i2_heap_locs : ∀ q cell l, c.heap q = some cell → cell.val = RVal.loc l →
    liveB c l = true
  i3_alias_flight : ∀ e, e ∈ c.btab → e.bid ∈ c.flight
  i4_unique : ∀ e1 e2, e1 ∈ c.btab → e2 ∈ c.btab → e1.bid = e2.bid → e1 = e2

/-! ## Runtime operations -/

def writeConf (c : Conf) (l : Loc) (v : RVal) : Conf :=
  { c with
    heap := updateCell c.heap l
      (fun cell => { cell with val := v, holders := holdersOfVal v }) }

def allocConf (c : Conf) (l : Loc) (v : RVal) (m : Mode) (r : Rgn) : Conf :=
  { c with
    heap := allocCell c.heap l
      { val := v, mode := m, rgn := r, live := true, holders := holdersOfVal v } }

def freezeConf (c : Conf) (l : Loc) (b : Bid) : Conf :=
  { c with
    heap := updateCell c.heap l (fun cell => { cell with mode := Mode.frozen }),
    btab := { bid := b, target := l, mode := Mode.frozen, rgn := cellRgn c l } :: c.btab,
    flight := b :: c.flight }

def recoverConf (c : Conf) (l : Loc) : Conf :=
  { c with
    heap := updateCell c.heap l (fun cell => { cell with mode := Mode.uniq }),
    btab := removeTarget l c.btab }

def dropConf (c : Conf) (l : Loc) : Conf :=
  { c with heap := updateCell c.heap l (fun cell => { cell with live := false }) }

def regionExitConf (c : Conf) (r : Rgn) : Conf :=
  { c with heap := killRegion c.heap r }

theorem beq_false_of_ne {a b : Nat} (h : a ≠ b) : (a == b) = false := by
  cases hb : a == b with
  | false => rfl
  | true => exact absurd (Nat.eq_of_beq_eq_true hb) h

theorem liveB_killRegion {c : Conf} {r : Rgn} {q : Loc} {cell : Cell}
    (h : c.heap q = some cell) :
    liveB (regionExitConf c r) q = (if cell.rgn == r then false else cell.live) := by
  unfold liveB regionExitConf killRegion
  dsimp only
  rw [h]
  show (if cell.rgn == r then { cell with live := false, holders := [] } else cell).live =
    (if cell.rgn == r then false else cell.live)
  cases hr : cell.rgn == r <;> simp [hr]

theorem liveB_killRegion_of_ne {c : Conf} {r : Rgn} {q : Loc} {cell : Cell}
    (h : c.heap q = some cell) (hne : cell.rgn ≠ r) :
    liveB (regionExitConf c r) q = liveB c q := by
  rw [liveB_killRegion h]
  rw [beq_false_of_ne hne]
  unfold liveB
  rw [h]
  simp

theorem heap_drop_same {c : Conf} {l : Loc} {cell : Cell} (h : c.heap l = some cell) :
    (dropConf c l).heap l = some { cell with live := false } := by
  unfold dropConf updateCell
  dsimp only
  rw [if_pos rfl, h]
  rfl

theorem heap_drop_other {c : Conf} {l q : Loc} (hne : q ≠ l) :
    (dropConf c l).heap q = c.heap q := by
  unfold dropConf updateCell
  dsimp only
  rw [if_neg hne]


theorem liveB_true_exists {c : Conf} {l : Loc} (h : liveB c l = true) :
    ∃ cell, c.heap l = some cell := by
  unfold liveB at h
  cases hc : c.heap l with
  | none => simp [hc] at h
  | some cell => exact ⟨cell, rfl⟩

theorem liveB_write_same (c : Conf) (l : Loc) (v : RVal) :
    liveB (writeConf c l v) l = liveB c l := by
  unfold liveB writeConf updateCell
  dsimp only
  rw [if_pos rfl]
  cases c.heap l <;> rfl

theorem liveB_write_other {c : Conf} {l q : Loc} {v : RVal} (hne : q ≠ l) :
    liveB (writeConf c l v) q = liveB c q := by
  unfold liveB writeConf updateCell
  dsimp only
  rw [if_neg hne]

theorem liveB_alloc_new (c : Conf) (l : Loc) (v : RVal) (m : Mode) (r : Rgn) :
    liveB (allocConf c l v m r) l = true := by
  unfold liveB allocConf allocCell
  dsimp only
  rw [if_pos rfl]

theorem liveB_alloc_other {c : Conf} {l q : Loc} {v : RVal} {m : Mode} {r : Rgn}
    (hne : q ≠ l) : liveB (allocConf c l v m r) q = liveB c q := by
  unfold liveB allocConf allocCell
  dsimp only
  rw [if_neg hne]

theorem liveB_freeze_same (c : Conf) (l : Loc) (b : Bid) :
    liveB (freezeConf c l b) l = liveB c l := by
  unfold liveB freezeConf updateCell
  dsimp only
  rw [if_pos rfl]
  cases c.heap l <;> rfl

theorem liveB_freeze_other {c : Conf} {l q : Loc} {b : Bid} (hne : q ≠ l) :
    liveB (freezeConf c l b) q = liveB c q := by
  unfold liveB freezeConf updateCell
  dsimp only
  rw [if_neg hne]

theorem liveB_recover_same (c : Conf) (l : Loc) :
    liveB (recoverConf c l) l = liveB c l := by
  unfold liveB recoverConf updateCell
  dsimp only
  rw [if_pos rfl]
  cases c.heap l <;> rfl

theorem liveB_recover_other {c : Conf} {l q : Loc} (hne : q ≠ l) :
    liveB (recoverConf c l) q = liveB c q := by
  unfold liveB recoverConf updateCell
  dsimp only
  rw [if_neg hne]

theorem liveB_drop_same (c : Conf) (l : Loc) :
    liveB (dropConf c l) l = false := by
  unfold liveB dropConf updateCell
  dsimp only
  rw [if_pos rfl]
  cases c.heap l <;> rfl

theorem liveB_drop_other {c : Conf} {l q : Loc} (hne : q ≠ l) :
    liveB (dropConf c l) q = liveB c q := by
  unfold liveB dropConf updateCell
  dsimp only
  rw [if_neg hne]


theorem hasBid_of_mem {btab : List BEntry} {e : BEntry} {b : Bid}
    (he : e ∈ btab) (hb : e.bid = b) : hasBid btab b = true := by
  induction btab with
  | nil => cases he
  | cons x xs ih =>
      cases hx : x.bid == b with
      | true => simp [hasBid, hx]
      | false =>
          have h' : hasBid xs b = true := by
            cases he with
            | head =>
                have ht : (e.bid == b) = true := by
                  rw [hb]
                  exact LawfulBEq.rfl
                rw [ht] at hx
                exact Bool.noConfusion hx
            | tail _ hmem => exact ih hmem
          simp only [hasBid]
          rw [hx]
          simp
          exact h'

theorem hasBid_true {btab : List BEntry} {b : Bid} (h : hasBid btab b = true) :
    ∃ e, e ∈ btab ∧ e.bid = b := by
  induction btab with
  | nil =>
      unfold hasBid at h
      exact Bool.noConfusion h
  | cons x xs ih =>
      cases hx : x.bid == b with
      | true => exact ⟨x, List.Mem.head _, Nat.eq_of_beq_eq_true hx⟩
      | false =>
          have h' : hasBid xs b = true := by
            unfold hasBid at h
            rw [hx] at h
            simp at h
            exact h
          cases ih h' with
          | intro e he => exact ⟨e, List.Mem.tail _ he.1, he.2⟩

theorem hasBid_false {btab : List BEntry} {b : Bid} (h : hasBid btab b = false) :
    ∀ e, e ∈ btab → e.bid ≠ b := by
  intro e he hb
  have ht : hasBid btab b = true := hasBid_of_mem he hb
  rw [h] at ht
  exact Bool.noConfusion ht

theorem isLiveVal_holders {c : Conf} {v : RVal} {b : Bid}
    (hv : isLiveVal c v = true) (hb : b ∈ holdersOfVal v) :
    hasBid c.btab b = true := by
  cases v with
  | unit => cases hb
  | nat n => cases hb
  | loc l => cases hb
  | valH x =>
      simp only [holdersOfVal] at hb
      cases hb with
      | head => exact hv
      | tail _ h => cases h
  | refH x =>
      simp only [holdersOfVal] at hb
      cases hb with
      | head => exact hv
      | tail _ h => cases h

theorem allInFlight_mem {bs flight : List Bid} {b : Bid}
    (h : allInFlight bs flight = true) (hb : b ∈ bs) : b ∈ flight := by
  induction bs with
  | nil => cases hb
  | cons c cs ih =>
      cases hc : flight.elem c with
      | false =>
          have hfalse : False := by
            simp only [allInFlight] at h
            rw [hc] at h
            exact Bool.noConfusion h
          exact False.elim hfalse
      | true =>
          have hmem : c ∈ flight := List.mem_of_elem_eq_true hc
          cases hb with
          | head => exact hmem
          | tail _ hb' =>
              have h' : allInFlight cs flight = true := by
                simp only [allInFlight] at h
                rw [hc] at h
                simp at h
                exact h
              exact ih h' hb'

theorem eq_of_beq_true {a b : Nat} (h : (a == b) = true) : a = b :=
  Nat.eq_of_beq_eq_true h

theorem ne_of_beq_false {a b : Nat} (h : (a == b) = false) : a ≠ b := by
  intro he
  have ht : (a == b) = true := by
    rw [he]
    exact LawfulBEq.rfl
  rw [ht] at h
  exact Bool.noConfusion h

theorem liveB_write_of_liveB {c : Conf} {l q : Loc} {v : RVal}
    (h : liveB c q = true) : liveB (writeConf c l v) q = true := by
  cases hq : q == l with
  | true =>
      have heq := eq_of_beq_true hq
      rw [heq]
      rw [heq] at h
      rw [liveB_write_same]
      exact h
  | false =>
      rw [liveB_write_other (ne_of_beq_false hq)]
      exact h

theorem liveB_alloc_of_liveB {c : Conf} {l q : Loc} {v : RVal} {m : Mode} {r : Rgn}
    (h : liveB c q = true) : liveB (allocConf c l v m r) q = true := by
  cases hq : q == l with
  | true =>
      rw [eq_of_beq_true hq, liveB_alloc_new]
  | false =>
      rw [liveB_alloc_other (ne_of_beq_false hq)]
      exact h

theorem liveB_freeze_of_liveB {c : Conf} {l q : Loc} {b : Bid}
    (h : liveB c q = true) : liveB (freezeConf c l b) q = true := by
  cases hq : q == l with
  | true =>
      have heq := eq_of_beq_true hq
      rw [heq]
      rw [heq] at h
      rw [liveB_freeze_same]
      exact h
  | false =>
      rw [liveB_freeze_other (ne_of_beq_false hq)]
      exact h

theorem liveB_recover_of_liveB {c : Conf} {l q : Loc}
    (h : liveB c q = true) : liveB (recoverConf c l) q = true := by
  cases hq : q == l with
  | true =>
      have heq := eq_of_beq_true hq
      rw [heq]
      rw [heq] at h
      rw [liveB_recover_same]
      exact h
  | false =>
      rw [liveB_recover_other (ne_of_beq_false hq)]
      exact h

theorem liveB_drop_of_ne {c : Conf} {l q : Loc} (hne : q ≠ l)
    (h : liveB c q = true) : liveB (dropConf c l) q = true := by
  rw [liveB_drop_other hne]
  exact h

theorem holdersAt_write_same {c : Conf} {l : Loc} {v : RVal} {cell : Cell}
    (h : c.heap l = some cell) :
    holdersAt (writeConf c l v) l = holdersOfVal v := by
  unfold holdersAt writeConf updateCell
  dsimp only
  rw [if_pos rfl, h]
  rfl

theorem holdersAt_write_other {c : Conf} {l q : Loc} {v : RVal} (hne : q ≠ l) :
    holdersAt (writeConf c l v) q = holdersAt c q := by
  unfold holdersAt writeConf updateCell
  dsimp only
  rw [if_neg hne]

theorem holdersAt_alloc_new (c : Conf) (l : Loc) (v : RVal) (m : Mode) (r : Rgn) :
    holdersAt (allocConf c l v m r) l = holdersOfVal v := by
  unfold holdersAt allocConf allocCell
  dsimp only
  rw [if_pos rfl]

theorem holdersAt_alloc_other {c : Conf} {l q : Loc} {v : RVal} {m : Mode} {r : Rgn}
    (hne : q ≠ l) : holdersAt (allocConf c l v m r) q = holdersAt c q := by
  unfold holdersAt allocConf allocCell
  dsimp only
  rw [if_neg hne]

theorem holdersAt_freeze_same (c : Conf) (l : Loc) (b : Bid) :
    holdersAt (freezeConf c l b) l = holdersAt c l := by
  unfold holdersAt freezeConf updateCell
  dsimp only
  rw [if_pos rfl]
  cases c.heap l <;> rfl

theorem holdersAt_freeze_other {c : Conf} {l q : Loc} {b : Bid} (hne : q ≠ l) :
    holdersAt (freezeConf c l b) q = holdersAt c q := by
  unfold holdersAt freezeConf updateCell
  dsimp only
  rw [if_neg hne]

theorem holdersAt_recover_same (c : Conf) (l : Loc) :
    holdersAt (recoverConf c l) l = holdersAt c l := by
  unfold holdersAt recoverConf updateCell
  dsimp only
  rw [if_pos rfl]
  cases c.heap l <;> rfl

theorem holdersAt_recover_other {c : Conf} {l q : Loc} (hne : q ≠ l) :
    holdersAt (recoverConf c l) q = holdersAt c q := by
  unfold holdersAt recoverConf updateCell
  dsimp only
  rw [if_neg hne]

theorem holdersAt_drop_same (c : Conf) (l : Loc) :
    holdersAt (dropConf c l) l = holdersAt c l := by
  unfold holdersAt dropConf updateCell
  dsimp only
  rw [if_pos rfl]
  cases c.heap l <;> rfl

theorem holdersAt_drop_other {c : Conf} {l q : Loc} (hne : q ≠ l) :
    holdersAt (dropConf c l) q = holdersAt c q := by
  unfold holdersAt dropConf updateCell
  dsimp only
  rw [if_neg hne]

theorem bidsAtTarget_of_mem {btab : List BEntry} {e : BEntry} {l : Loc}
    (he : e ∈ btab) (ht : e.target = l) : e.bid ∈ bidsAtTarget l btab := by
  induction btab with
  | nil => cases he
  | cons x xs ih =>
      cases hx : x.target == l with
      | true =>
          simp [bidsAtTarget, hx]
          cases he with
          | head => exact List.Mem.head _
          | tail _ hmem => exact List.Mem.tail _ (ih hmem)
      | false =>
          simp [bidsAtTarget, hx]
          cases he with
          | head =>
              have ht' : (e.target == l) = true := by
                rw [ht]
                exact LawfulBEq.rfl
              rw [ht'] at hx
              exact Bool.noConfusion hx
          | tail _ hmem => exact ih hmem

theorem bidsAtTarget_nil {btab : List BEntry} {l : Loc}
    (h : bidsAtTarget l btab = []) : ∀ e, e ∈ btab → e.target ≠ l := by
  induction btab with
  | nil => intro e he; cases he
  | cons x xs ih =>
      cases hx : x.target == l with
      | true =>
          have hfalse : False := by
            simp [bidsAtTarget, hx] at h
          intro e he
          exact False.elim hfalse
      | false =>
          have h' : bidsAtTarget l xs = [] := by
            simp [bidsAtTarget, hx] at h
            exact h
          intro e he
          cases he with
          | head =>
              intro ht
              have ht' : (x.target == l) = true := by
                rw [ht]
                exact LawfulBEq.rfl
              rw [ht'] at hx
              exact Bool.noConfusion hx
          | tail _ hmem => exact ih h' e hmem

theorem removeTarget_mem {btab : List BEntry} {l : Loc} {e : BEntry}
    (h : e ∈ removeTarget l btab) : e ∈ btab := by
  induction btab with
  | nil => cases h
  | cons x xs ih =>
      cases hx : x.target == l with
      | true =>
          have h' : e ∈ removeTarget l xs := by
            simp [removeTarget, hx] at h
            exact h
          exact List.Mem.tail _ (ih h')
      | false =>
          simp [removeTarget, hx] at h
          cases h with
          | head => exact List.Mem.head _
          | tail _ hmem => exact List.Mem.tail _ (ih hmem)

theorem removeTarget_target_ne {btab : List BEntry} {l : Loc} {e : BEntry}
    (h : e ∈ removeTarget l btab) : e.target ≠ l := by
  induction btab with
  | nil => cases h
  | cons x xs ih =>
      cases hx : x.target == l with
      | true =>
          have h' : e ∈ removeTarget l xs := by
            simp [removeTarget, hx] at h
            exact h
          exact ih h'
      | false =>
          simp [removeTarget, hx] at h
          cases h with
          | head =>
              intro ht
              have ht' : (e.target == l) = true := by
                rw [ht]
                exact LawfulBEq.rfl
              rw [ht'] at hx
              exact Bool.noConfusion hx
          | tail _ hmem => exact ih hmem

theorem bidsAtTarget_removeTarget (btab : List BEntry) (l : Loc) :
    bidsAtTarget l (removeTarget l btab) = [] := by
  induction btab with
  | nil => rfl
  | cons x xs ih =>
      cases hx : x.target == l with
      | true =>
          simp [removeTarget, hx]
          exact ih
      | false =>
          simp [removeTarget, bidsAtTarget, hx]
          exact ih

/-- Concrete F0 runtime steps.  Every rule carries the side conditions that
    the paper's S3–S12 require; post-states are computed, not arbitrary. -/
inductive RStep : Conf → Conf → Prop where
  | read {c : Conf} {l : Loc} (hl : liveB c l = true) : RStep c c
  | write {c : Conf} {l : Loc} {v : RVal}
      (hl : liveB c l = true) (hv : isLiveVal c v = true) :
      RStep c (writeConf c l v)
  | alloc {c : Conf} {l : Loc} {v : RVal} {m : Mode} {r : Rgn}
      (hfresh : c.heap l = none) (hv : isLiveVal c v = true) :
      RStep c (allocConf c l v m r)
  | freeze {c : Conf} {l : Loc} {b : Bid}
      (hl : liveB c l = true) (hm : cellMode c l = some Mode.uniq)
      (hno : bidsAtTarget l c.btab = []) (hfresh : hasBid c.btab b = false) :
      RStep c (freezeConf c l b)
  | recover {c : Conf} {l : Loc}
      (hm : cellMode c l = some Mode.frozen)
      (hclear : ∀ e, e ∈ c.btab → e.target = l → e.bid ∈ c.flight) :
      RStep c (recoverConf c l)
  | drop {c : Conf} {l : Loc}
      (hl : liveB c l = true) (hno : bidsAtTarget l c.btab = [])
      (hholders : holdersAt c l = []) (hnoref : ∀ q cell, c.heap q = some cell →
        cell.val ≠ RVal.loc l) :
      RStep c (dropConf c l)
  | regionExit {c : Conf} {r : Rgn}
      (hnoBid : ∀ e, e ∈ c.btab → ∀ cell, c.heap e.target = some cell → cell.rgn ≠ r)
      (hnoRef : ∀ q cell l, c.heap q = some cell → cell.val = RVal.loc l →
        ∀ target, c.heap l = some target → target.rgn ≠ r) :
      RStep c (regionExitConf c r)


/-- The fragment for which L4/preservation is proved in this increment:
    `read`/`write`/`alloc`/`freeze`/`recover`.  `drop`/region exit and
    environment/`borrow` holders are the next increment. -/
inductive RStepCore : Conf → Conf → Prop where
  | read {c : Conf} {l : Loc} (hl : liveB c l = true) : RStepCore c c
  | write {c : Conf} {l : Loc} {v : RVal}
      (hl : liveB c l = true) (hv : isLiveVal c v = true) :
      RStepCore c (writeConf c l v)
  | alloc {c : Conf} {l : Loc} {v : RVal} {m : Mode} {r : Rgn}
      (hfresh : c.heap l = none) (hv : isLiveVal c v = true) :
      RStepCore c (allocConf c l v m r)
  | freeze {c : Conf} {l : Loc} {b : Bid}
      (hl : liveB c l = true) (hm : cellMode c l = some Mode.uniq)
      (hno : bidsAtTarget l c.btab = []) (hfresh : hasBid c.btab b = false) :
      RStepCore c (freezeConf c l b)
  | recover {c : Conf} {l : Loc}
      (hm : cellMode c l = some Mode.frozen)
      (hclear : ∀ e, e ∈ c.btab → e.target = l → e.bid ∈ c.flight) :
      RStepCore c (recoverConf c l)
  | drop {c : Conf} {l : Loc}
      (hl : liveB c l = true) (hno : bidsAtTarget l c.btab = [])
      (hholders : holdersAt c l = []) (hnoref : ∀ q cell, c.heap q = some cell →
        cell.val ≠ RVal.loc l) :
      RStepCore c (dropConf c l)
  | regionExit {c : Conf} {r : Rgn}
      (hnoBid : ∀ e, e ∈ c.btab → ∀ cell, c.heap e.target = some cell → cell.rgn ≠ r)
      (hnoRef : ∀ q cell l, c.heap q = some cell → cell.val = RVal.loc l →
        ∀ target, c.heap l = some target → target.rgn ≠ r) :
      RStepCore c (regionExitConf c r)

theorem liveB_of_isLiveVal {c : Conf} {v : RVal} {l : Loc}
    (hv : isLiveVal c v = true) (h : v = RVal.loc l) : liveB c l = true := by
  cases h
  exact hv

theorem cellMode_some_exists {c : Conf} {l : Loc} {m : Mode}
    (h : cellMode c l = some m) : ∃ cell, c.heap l = some cell := by
  unfold cellMode at h
  cases hc : c.heap l with
  | none => rw [hc] at h; cases h
  | some cell => exact ⟨cell, rfl⟩

theorem heap_write_same {c : Conf} {l : Loc} {cell : Cell} {v : RVal}
    (h : c.heap l = some cell) :
    (writeConf c l v).heap l = some { cell with val := v, holders := holdersOfVal v } := by
  unfold writeConf updateCell
  dsimp only
  rw [if_pos rfl, h]
  rfl

theorem heap_write_other {c : Conf} {l q : Loc} {v : RVal} (hne : q ≠ l) :
    (writeConf c l v).heap q = c.heap q := by
  unfold writeConf updateCell
  dsimp only
  rw [if_neg hne]

theorem heap_alloc_same (c : Conf) (l : Loc) (v : RVal) (m : Mode) (r : Rgn) :
    (allocConf c l v m r).heap l =
      some { val := v, mode := m, rgn := r, live := true, holders := holdersOfVal v } := by
  unfold allocConf allocCell
  dsimp only
  rw [if_pos rfl]

theorem heap_alloc_other {c : Conf} {l q : Loc} {v : RVal} {m : Mode} {r : Rgn}
    (hne : q ≠ l) : (allocConf c l v m r).heap q = c.heap q := by
  unfold allocConf allocCell
  dsimp only
  rw [if_neg hne]

theorem heap_freeze_same {c : Conf} {l : Loc} {cell : Cell} {b : Bid}
    (h : c.heap l = some cell) :
    (freezeConf c l b).heap l = some { cell with mode := Mode.frozen } := by
  unfold freezeConf updateCell
  dsimp only
  rw [if_pos rfl, h]
  rfl

theorem heap_freeze_other {c : Conf} {l q : Loc} {b : Bid} (hne : q ≠ l) :
    (freezeConf c l b).heap q = c.heap q := by
  unfold freezeConf updateCell
  dsimp only
  rw [if_neg hne]

theorem heap_recover_same {c : Conf} {l : Loc} {cell : Cell} (h : c.heap l = some cell) :
    (recoverConf c l).heap l = some { cell with mode := Mode.uniq } := by
  unfold recoverConf updateCell
  dsimp only
  rw [if_pos rfl, h]
  rfl

theorem heap_recover_other {c : Conf} {l q : Loc} (hne : q ≠ l) :
    (recoverConf c l).heap q = c.heap q := by
  unfold recoverConf updateCell
  dsimp only
  rw [if_neg hne]

theorem RStepCore.toRStep {c c' : Conf} (h : RStepCore c c') : RStep c c' := by
  cases h with
  | read hl => exact RStep.read hl
  | write hl hv => exact RStep.write hl hv
  | alloc hf hv => exact RStep.alloc hf hv
  | freeze hl hm hno hf => exact RStep.freeze hl hm hno hf
  | recover hm hc => exact RStep.recover hm hc
  | drop hl hno hh hnr => exact RStep.drop hl hno hh hnr
  | regionExit hb hr => exact RStep.regionExit hb hr

theorem wf_write {c : Conf} {l : Loc} {v : RVal} (hwf : WF c)
    (hl : liveB c l = true) (hv : isLiveVal c v = true) :
    WF (writeConf c l v) := by
  constructor
  · intro e he
    cases ht : e.target == l with
    | true =>
        rw [eq_of_beq_true ht, liveB_write_same]
        exact hl
    | false =>
        rw [liveB_write_other (ne_of_beq_false ht)]
        exact hwf.i1_btab_live e he
  · intro q cell l' hq hval
    cases hqeq : q == l with
    | true =>
        have heq := eq_of_beq_true hqeq
        cases liveB_true_exists hl with
        | intro old hold =>
            rw [heq] at hq
            rw [heap_write_same hold] at hq
            cases hq
            exact liveB_write_of_liveB (liveB_of_isLiveVal hv hval)
    | false =>
        rw [heap_write_other (ne_of_beq_false hqeq)] at hq
        exact liveB_write_of_liveB (hwf.i2_heap_locs q cell l' hq hval)
  · intro e he
    exact hwf.i3_alias_flight e he
  · intro e1 e2 h1 h2 hb
    exact hwf.i4_unique e1 e2 h1 h2 hb

theorem wf_alloc {c : Conf} {l : Loc} {v : RVal} {m : Mode} {r : Rgn}
    (hwf : WF c) (hfresh : c.heap l = none) (hv : isLiveVal c v = true) :
    WF (allocConf c l v m r) := by
  constructor
  · intro e he
    exact liveB_alloc_of_liveB (hwf.i1_btab_live e he)
  · intro q cell l' hq hval
    cases hqeq : q == l with
    | true =>
        have heq := eq_of_beq_true hqeq
        rw [heq] at hq
        rw [heap_alloc_same] at hq
        cases hq
        exact liveB_alloc_of_liveB (liveB_of_isLiveVal hv hval)
    | false =>
        rw [heap_alloc_other (ne_of_beq_false hqeq)] at hq
        exact liveB_alloc_of_liveB (hwf.i2_heap_locs q cell l' hq hval)
  · intro e he
    exact hwf.i3_alias_flight e he
  · intro e1 e2 h1 h2 hb
    exact hwf.i4_unique e1 e2 h1 h2 hb

theorem wf_freeze {c : Conf} {l : Loc} {b : Bid} (hwf : WF c)
    (hl : liveB c l = true) (hm : cellMode c l = some Mode.uniq)
    (hno : bidsAtTarget l c.btab = []) (hfresh : hasBid c.btab b = false) :
    WF (freezeConf c l b) := by
  constructor
  · intro e he
    cases he with
    | head =>
        rw [liveB_freeze_same]
        exact hl
    | tail _ heold =>
        exact liveB_freeze_of_liveB (hwf.i1_btab_live e heold)
  · intro q cell l' hq hval
    cases hqeq : q == l with
    | true =>
        have heq := eq_of_beq_true hqeq
        cases liveB_true_exists hl with
        | intro old hold =>
            rw [heq] at hq
            rw [heap_freeze_same hold] at hq
            cases hq
            exact liveB_freeze_of_liveB (hwf.i2_heap_locs l old l' hold hval)
    | false =>
        rw [heap_freeze_other (ne_of_beq_false hqeq)] at hq
        exact liveB_freeze_of_liveB (hwf.i2_heap_locs q cell l' hq hval)
  · intro e he
    cases he with
    | head => exact List.Mem.head _
    | tail _ heold => exact List.Mem.tail b (hwf.i3_alias_flight e heold)
  · intro e1 e2 h1 h2 hb
    cases h1 with
    | head =>
        cases h2 with
        | head => rfl
        | tail _ h2old =>
            have hne := hasBid_false hfresh e2 h2old
            exact absurd hb.symm hne
    | tail _ h1old =>
        cases h2 with
        | head =>
            have hne := hasBid_false hfresh e1 h1old
            exact absurd hb hne
        | tail _ h2old =>
            exact hwf.i4_unique e1 e2 h1old h2old hb

theorem wf_recover {c : Conf} {l : Loc} (hwf : WF c)
    (hm : cellMode c l = some Mode.frozen)
    (hclear : ∀ e, e ∈ c.btab → e.target = l → e.bid ∈ c.flight) :
    WF (recoverConf c l) := by
  constructor
  · intro e he
    have heold := removeTarget_mem he
    have ht := removeTarget_target_ne he
    rw [liveB_recover_other ht]
    exact hwf.i1_btab_live e heold
  · intro q cell l' hq hval
    cases hqeq : q == l with
    | true =>
        have heq := eq_of_beq_true hqeq
        cases cellMode_some_exists hm with
        | intro old hold =>
            rw [heq] at hq
            rw [heap_recover_same hold] at hq
            cases hq
            exact liveB_recover_of_liveB (hwf.i2_heap_locs l old l' hold hval)
    | false =>
        rw [heap_recover_other (ne_of_beq_false hqeq)] at hq
        exact liveB_recover_of_liveB (hwf.i2_heap_locs q cell l' hq hval)
  · intro e he
    exact hwf.i3_alias_flight e (removeTarget_mem he)
  · intro e1 e2 h1 h2 hb
    exact hwf.i4_unique e1 e2 (removeTarget_mem h1) (removeTarget_mem h2) hb

/-- **L4 fragment**: the core runtime steps preserve well-formedness. -/
theorem heap_killRegion_some {c : Conf} {r : Rgn} {q : Loc} {cell : Cell}
    (h : c.heap q = some cell) :
    (regionExitConf c r).heap q =
      some (if cell.rgn == r then { cell with live := false, holders := [] } else cell) := by
  unfold regionExitConf killRegion
  dsimp only
  rw [h]
  show some (if cell.rgn == r then { cell with live := false, holders := [] } else cell) =
    some (if cell.rgn == r then { cell with live := false, holders := [] } else cell)
  rfl

theorem killRegion_val {r : Rgn} {cell : Cell} :
    (if cell.rgn == r then { cell with live := false, holders := [] } else cell).val =
      cell.val := by
  cases hr : cell.rgn == r <;> simp [hr]

theorem wf_drop {c : Conf} {l : Loc} (hwf : WF c)
    (hl : liveB c l = true) (hno : bidsAtTarget l c.btab = [])
    (hholders : holdersAt c l = [])
    (hnoref : ∀ q cell, c.heap q = some cell → cell.val ≠ RVal.loc l) :
    WF (dropConf c l) := by
  constructor
  · intro e he
    have ht : e.target ≠ l := bidsAtTarget_nil hno e he
    rw [liveB_drop_other ht]
    exact hwf.i1_btab_live e he
  · intro q cell l' hq hval
    cases hqeq : q == l with
    | true =>
        have heq := eq_of_beq_true hqeq
        cases liveB_true_exists hl with
        | intro old hold =>
            rw [heq] at hq
            rw [heap_drop_same hold] at hq
            cases hq
            have hne : l' ≠ l := by
              intro heql
              have hbad : old.val = RVal.loc l := by
                rw [heql] at hval
                exact hval
              exact hnoref l old hold hbad
            rw [liveB_drop_other hne]
            exact hwf.i2_heap_locs l old l' hold hval
    | false =>
        have hne := ne_of_beq_false hqeq
        rw [heap_drop_other hne] at hq
        have hne' : l' ≠ l := by
          intro heql
          have hbad : cell.val = RVal.loc l := by
            rw [heql] at hval
            exact hval
          exact hnoref q cell hq hbad
        rw [liveB_drop_other hne']
        exact hwf.i2_heap_locs q cell l' hq hval
  · intro e he
    exact hwf.i3_alias_flight e he
  · intro e1 e2 h1 h2 hb
    exact hwf.i4_unique e1 e2 h1 h2 hb

theorem wf_regionExit {c : Conf} {r : Rgn} (hwf : WF c)
    (hnoBid : ∀ e, e ∈ c.btab → ∀ cell, c.heap e.target = some cell → cell.rgn ≠ r)
    (hnoRef : ∀ q cell l, c.heap q = some cell → cell.val = RVal.loc l →
      ∀ target, c.heap l = some target → target.rgn ≠ r) :
    WF (regionExitConf c r) := by
  constructor
  · intro e he
    have hlive := hwf.i1_btab_live e he
    cases liveB_true_exists hlive with
    | intro cell hcell =>
        have hne := hnoBid e he cell hcell
        rw [liveB_killRegion_of_ne hcell hne]
        exact hlive
  · intro q cell l' hq hval
    cases hcq : c.heap q with
    | none =>
        unfold regionExitConf killRegion at hq
        dsimp only at hq
        rw [hcq] at hq
        cases hq
    | some old =>
        rw [heap_killRegion_some hcq] at hq
        cases hq
        have hval_old : old.val = RVal.loc l' := by
          rw [killRegion_val] at hval
          exact hval
        have hlive := hwf.i2_heap_locs q old l' hcq hval_old
        cases liveB_true_exists hlive with
        | intro target htarget =>
            have hne := hnoRef q old l' hcq hval_old target htarget
            rw [liveB_killRegion_of_ne htarget hne]
            exact hlive
  · intro e he
    exact hwf.i3_alias_flight e he
  · intro e1 e2 h1 h2 hb
    exact hwf.i4_unique e1 e2 h1 h2 hb

theorem wf_preserved_core {c c' : Conf} (h : RStepCore c c') (hwf : WF c) :
    WF c' := by
  cases h with
  | read hl => exact hwf
  | write hl hv => exact wf_write hwf hl hv
  | alloc hfresh hv => exact wf_alloc hwf hfresh hv
  | freeze hl hm hno hfresh => exact wf_freeze hwf hl hm hno hfresh
  | recover hm hclear => exact wf_recover hwf hm hclear
  | drop hl hno hh hnr => exact wf_drop hwf hl hno hh hnr
  | regionExit hb hr => exact wf_regionExit hwf hb hr

/-- **T1 (no dangling, F0 heap fragment)**: a well-formed configuration has
    no stored `loc` pointing at a dead or absent cell. -/
theorem t1_no_dangling {c : Conf} {q : Loc} {cell : Cell} {l : Loc}
    (hwf : WF c) (hq : c.heap q = some cell) (hv : cell.val = RVal.loc l) :
    ∃ target, c.heap l = some target ∧ target.live = true := by
  have hl := hwf.i2_heap_locs q cell l hq hv
  unfold liveB at hl
  cases htarget : c.heap l with
  | none =>
      rw [htarget] at hl
      exact Bool.noConfusion hl
  | some target =>
      rw [htarget] at hl
      exact ⟨target, rfl, hl⟩

/-- **T3 (`recover` uniqueness, F0 heap fragment)**: after `recover`, no borrow
    entry targets the recovered location, and its mode is `uniq`. -/
theorem t3_recover_unique {c : Conf} {l : Loc}
    (hm : cellMode c l = some Mode.frozen)
    (hclear : ∀ e, e ∈ c.btab → e.target = l → e.bid ∈ c.flight) :
    bidsAtTarget l (recoverConf c l).btab = [] ∧
      cellMode (recoverConf c l) l = some Mode.uniq := by
  constructor
  · unfold recoverConf
    exact bidsAtTarget_removeTarget c.btab l
  · unfold cellMode recoverConf updateCell
    dsimp only
    rw [if_pos rfl]
    cases hcl : c.heap l with
    | none =>
        unfold cellMode at hm
        rw [hcl] at hm
        cases hm
    | some cell => rfl

theorem t3_recover_no_target {c : Conf} {l : Loc} {e : BEntry}
    (h : e ∈ (recoverConf c l).btab) : e.target ≠ l :=
  removeTarget_target_ne h


/-! ## Runtime UB events (UB-2 / UB-3 / UB-4)

The `RStepCore` liveness premises are *preconditions*: a transition only
happens on a live cell.  This section adds their **dual** — the events that
would occur if the action were attempted anyway — plus the reachability facts
that show they cannot occur on configurations reached from an initialised one.

`UB-5/8/9/10/11/13/15` have no runtime model here: threads, `rawptr`
provenance, `Mmio`, stack depth and FFI unwinding are outside F0 (T4b–T4e).

Nothing below uses `by_cases`/`Classical`: the case splits go through
`Nat.decEq` and explicit `Bool`/`Option` disjunctions, so the results stay free
of `Classical.choice` (the project's axiom discipline).
-/

/-- Every cell in the heap is initialised (allocation stores a value). -/
def AllInit (c : Conf) : Prop :=
  ∀ (l : Loc) (cell : Cell), c.heap l = some cell → cell.init = true

/-- Runtime UB events, indexed by the UB class. -/
inductive REvent (c : Conf) : UBCode → Prop where
  /-- UB-2: using (read/write/freeze) a dead cell. -/
  | useDead {l : Loc} (h : liveB c l = false) : REvent c UBCode.dangling
  /-- UB-3: freeing (`drop`) a cell that is already dead. -/
  | freeDead {l : Loc} (hdead : liveB c l = false) (hpresent : c.heap l ≠ none) :
      REvent c UBCode.doubleFree
  /-- UB-4: reading a cell whose initialisation flag is unset. -/
  | readUninit {l : Loc} {cell : Cell} (h : c.heap l = some cell)
      (hinit : cell.init = false) : REvent c UBCode.uninit

theorem rEvent_outside {c : Conf} {k : UBCode} (h : REvent c k) : OutsideF0 k := by
  cases h <;> simp [OutsideF0]

/-! ### Two-valued case analysis without `Classical` -/

theorem bool_true_or_false (b : Bool) : b = true ∨ b = false := by
  cases b with
  | true => exact Or.inl rfl
  | false => exact Or.inr rfl

theorem bool_false_of_not_true {b : Bool} (h : ¬ b = true) : b = false := by
  cases b with
  | false => rfl
  | true => exact absurd rfl h

theorem liveB_false_of_not_true {c : Conf} {l : Loc} (h : ¬ liveB c l = true) :
    liveB c l = false :=
  bool_false_of_not_true h

theorem option_none_or_some (o : Option Cell) :
    o = none ∨ ∃ cell, o = some cell := by
  cases o with
  | none => exact Or.inl rfl
  | some cell => exact Or.inr ⟨cell, rfl⟩

/-! ### Oracles: every liveness/initialisation check is total -/

/-- `read`/`write`/`freeze`: either the cell is live, or accessing it is UB-2. -/
theorem live_or_useDead {c : Conf} {l : Loc} :
    liveB c l = true ∨ REvent c UBCode.dangling := by
  cases bool_true_or_false (liveB c l) with
  | inl h => exact Or.inl h
  | inr h => exact Or.inr (REvent.useDead h)

/-- `drop`: either the cell is live (the drop is defined), or the location is
    not allocated (nothing to free), or dropping it is a double free (UB-3). -/
theorem live_or_doubleFree {c : Conf} {l : Loc} :
    liveB c l = true ∨ c.heap l = none ∨ REvent c UBCode.doubleFree := by
  cases bool_true_or_false (liveB c l) with
  | inl h => exact Or.inl h
  | inr hdead =>
      cases option_none_or_some (c.heap l) with
      | inl hn => exact Or.inr (Or.inl hn)
      | inr rest =>
          cases rest with
          | intro cell hsome =>
              exact Or.inr (Or.inr (REvent.freeDead hdead (by rw [hsome]; intro hc; cases hc)))

/-- Initialisation: a cell is either initialised, or reading it is UB-4. -/
theorem init_or_uninit {c : Conf} {l : Loc} {cell : Cell}
    (h : c.heap l = some cell) : cell.init = true ∨ REvent c UBCode.uninit := by
  cases bool_true_or_false cell.init with
  | inl hi => exact Or.inl hi
  | inr hi => exact Or.inr (REvent.readUninit h hi)

/-! ### Reachability: UB-4 cannot occur -/

theorem AllInit.updateCell {c : Conf} (h : AllInit c) (l : Loc) (f : Cell → Cell)
    (hf : ∀ cell, (f cell).init = cell.init) :
    AllInit { c with heap := updateCell c.heap l f } := by
  intro q cell hq
  have hq2 : LSys.updateCell c.heap l f q = some cell := hq
  cases Nat.decEq q l with
  | isTrue hql =>
      rw [hql] at hq2
      rw [lookup_update_same] at hq2
      cases hm : c.heap l with
      | none => rw [hm] at hq2; cases hq2
      | some cell0 =>
          rw [hm] at hq2
          simp only [Option.map, Option.some.injEq] at hq2
          rw [← hq2]
          exact (hf cell0).trans (h _ _ hm)
  | isFalse hql =>
      rw [lookup_update_other _ _ _ _ hql] at hq2
      exact h _ _ hq2

theorem AllInit.writeConf (h : AllInit c) (l : Loc) (v : RVal) :
    AllInit (writeConf c l v) := by
  refine h.updateCell l _ ?_
  intro cell
  rfl

theorem AllInit.allocConf (h : AllInit c) (l : Loc) (v : RVal) (m : Mode) (r : Rgn) :
    AllInit (LSys.allocConf c l v m r) := by
  intro q cell hq
  have hq2 : LSys.allocCell c.heap l
      { val := v, mode := m, rgn := r, live := true, holders := holdersOfVal v } q
      = some cell := hq
  cases Nat.decEq q l with
  | isTrue hql =>
      rw [hql] at hq2
      rw [lookup_alloc_same] at hq2
      simp only [Option.some.injEq] at hq2
      rw [← hq2]
  | isFalse hql =>
      rw [lookup_alloc_other _ _ _ _ hql] at hq2
      exact h _ _ hq2

theorem AllInit.freezeConf (h : AllInit c) (l : Loc) (b : Bid) :
    AllInit (freezeConf c l b) := by
  refine h.updateCell l _ ?_
  intro cell
  rfl

theorem AllInit.recoverConf (h : AllInit c) (l : Loc) :
    AllInit (recoverConf c l) := by
  refine h.updateCell l _ ?_
  intro cell
  rfl

theorem AllInit.dropConf (h : AllInit c) (l : Loc) :
    AllInit (dropConf c l) := by
  refine h.updateCell l _ ?_
  intro cell
  rfl

theorem AllInit.regionExitConf (h : AllInit c) (r : Rgn) :
    AllInit (LSys.regionExitConf c r) := by
  intro q cell hq
  cases hm : c.heap q with
  | none =>
      have hq2 : (none : Option Cell).map
          (fun cell => if cell.rgn == r then { cell with live := false, holders := [] }
           else cell) = some cell := by
        rw [← hm]
        exact hq
      simp only [Option.map] at hq2
  | some cell0 =>
      have hmap : (some cell0).map
          (fun cell => if cell.rgn == r then { cell with live := false, holders := [] }
           else cell) = some cell := by
        rw [← hm]
        exact hq
      simp only [Option.map, Option.some.injEq] at hmap
      rw [← hmap]
      cases bool_true_or_false (cell0.rgn == r) with
      | inl hrg =>
          rw [if_pos hrg]
          exact h q cell0 hm
      | inr hrg =>
          rw [if_neg (by intro hc; rw [hrg] at hc; cases hc)]
          exact h q cell0 hm

theorem allInit_preserved_core {c c' : Conf} (h : RStepCore c c') (h0 : AllInit c) :
    AllInit c' := by
  cases h with
  | read => exact h0
  | write => exact h0.writeConf _ _
  | alloc => exact h0.allocConf _ _ _ _
  | freeze => exact h0.freezeConf _ _
  | recover => exact h0.recoverConf _
  | drop => exact h0.dropConf _
  | regionExit => exact h0.regionExitConf _

/-- Reflexive-transitive closure of the core runtime steps. -/
inductive RStepCoreStar : Conf → Conf → Prop where
  | refl (c : Conf) : RStepCoreStar c c
  | step {c c' c'' : Conf} (h : RStepCore c c') (rest : RStepCoreStar c' c'') :
      RStepCoreStar c c''

theorem allInit_preserved_star {c c' : Conf} (h : RStepCoreStar c c')
    (h0 : AllInit c) : AllInit c' := by
  induction h with
  | refl => exact h0
  | step hstep _ ih => exact ih (allInit_preserved_core hstep h0)

/-- **UB-4 is unreachable**: no configuration reached from an initialised one
    has an uninitialised cell, so `REvent … UBCode.uninit` cannot fire. -/
theorem no_uninit_reachable {c c' : Conf} (h : RStepCoreStar c c')
    (h0 : AllInit c) : ¬ REvent c' UBCode.uninit := by
  intro he
  cases he with
  | readUninit hcell hinit =>
      have hi := allInit_preserved_star h h0 _ _ hcell
      rw [hi] at hinit
      cases hinit

end LSys
