/-
  LSys/State.lean

  Machine-checked model of the static state
  `Σ = (Γ, Λ, M, H)` from `spec/semantics.md` §2.2, together with

  * the matching relation `Match(Σ,S)` (M1–M5) from `spec/t4-proof.md` §3.5.0;
  * `ConsumeResult`;
  * the invariant underlying **L-Holder** and the exact occurrence-removal
    statement **L-Consume**.

  Places are field/index paths (`List Nat`); `isPrefix`/`overlap` model
  `Desc*`/`Anc*` from the paper.  `H` (`holders`) is kept as an association
  list so that every lemma is constructive and Mathlib-free.
-/

import LSys.Term

namespace LSys

abbrev Place := Path
abbrev Var := Nat
abbrev Bid := Nat
abbrev Rgn := Nat

/-! ## Types, modes, bindings -/

inductive Ty where
  | unit
  | int
  | bool
  | scalar
  | ref (r : Rgn) (t : Ty)
  | val (r : Rgn) (t : Ty)
  | box (r : Rgn) (t : Ty)
  | slice (r : Rgn) (t : Ty)
  | iso (t : Ty)
  | shared (t : Ty)
  | named (id : Nat)
  deriving Repr, DecidableEq

inductive Mode where
  | uniq
  | frozen
  | mut
  | atom
  | raw
  deriving Repr, DecidableEq

structure Borrow where
  bid : Bid
  place : Place
  mode : Mode
  rgn : Rgn
  deriving Repr, DecidableEq

structure Binding where
  ty : Ty
  mode : Mode
  rgn : Rgn
  deriving Repr, DecidableEq

structure Caps where
  alloc : Bool
  effects : List Nat
  deriving Repr, DecidableEq

/-! ## Static state `Σ = (Γ, Λ, M, H)` -/

structure Sigma where
  gamma : List (Place × Binding)
  lam : List Borrow
  moved : List Place
  holders : List (Place × List Bid)
  caps : Caps
  deriving Repr, DecidableEq

/-! ## Generic association-list helpers -/

def lookupPlace {α : Type} : List (Place × α) → Place → Option α
  | [], _ => none
  | (k, v) :: rest, n => if k == n then some v else lookupPlace rest n

def removeBids (A : List Bid) : List Bid → List Bid
  | [] => []
  | b :: bs => if A.elem b then removeBids A bs else b :: removeBids A bs

theorem not_mem_of_elem_false {A : List Bid} {b : Bid} (h : A.elem b = false) :
    b ∉ A := by
  intro hb
  have ht : A.elem b = true := List.elem_eq_true_of_mem hb
  rw [h] at ht
  exact Bool.noConfusion ht

theorem mem_removeBids {A bs : List Bid} {b : Bid} :
    b ∈ removeBids A bs ↔ b ∈ bs ∧ b ∉ A := by
  induction bs with
  | nil => exact ⟨fun h => nomatch h, fun h => nomatch h.1⟩
  | cons c cs ih =>
      cases hc : A.elem c with
      | false =>
          have hcnot : c ∉ A := not_mem_of_elem_false hc
          simp [removeBids, hc]
          constructor
          · intro h
            cases h with
            | head => exact ⟨List.Mem.head cs, hcnot⟩
            | tail _ hmem =>
                have h' := ih.mp hmem
                exact ⟨List.Mem.tail c h'.1, h'.2⟩
          · intro h
            cases h.1 with
            | head => exact List.Mem.head _
            | tail _ hmem =>
                exact List.Mem.tail c (ih.mpr ⟨hmem, h.2⟩)
      | true =>
          have hcin : c ∈ A := List.mem_of_elem_eq_true hc
          simp [removeBids, hc]
          rw [ih]
          constructor
          · intro h
            exact ⟨List.Mem.tail c h.1, h.2⟩
          · intro h
            cases h.1 with
            | head => exact absurd hcin h.2
            | tail _ hmem => exact ⟨hmem, h.2⟩

theorem lookupPlace_map_remove (l : List (Place × List Bid)) (q : Place) (A : List Bid) :
    lookupPlace (l.map (fun qb => (qb.1, removeBids A qb.2))) q
      = (lookupPlace l q).map (removeBids A) := by
  induction l with
  | nil => rfl
  | cons hd tl ih =>
      cases hd with
      | mk k bs =>
      cases hk : k == q with
      | false => simp [lookupPlace, hk, ih]
      | true => simp [lookupPlace, hk]; rfl

/-! ## Places: `Desc*` / `Anc*` via path prefix -/

def isPrefix : List Nat → List Nat → Bool
  | [], _ => true
  | _ :: _, [] => false
  | a :: as, b :: bs => (a = b) && isPrefix as bs

/-- `overlap(p,q)`: one place path is a prefix of the other (`spec/semantics.md` §2.2). -/
def overlap (p q : Place) : Bool := isPrefix p q || isPrefix q p

/-! ## `Λ`, `M`, `H` projections -/

def lamBids (σ : Sigma) : List Bid := σ.lam.map (fun br => br.bid)

def bidsAt (σ : Sigma) (q : Place) : List Bid :=
  match lookupPlace σ.holders q with
  | some bs => bs
  | none => []

def IsHolder (σ : Sigma) (q : Place) (b : Bid) : Prop := b ∈ bidsAt σ q

def holdersOf : List (Place × List Bid) → Bid → List Place
  | [], _ => []
  | (q, bs) :: rest, b =>
      if bs.elem b then q :: holdersOf rest b else holdersOf rest b

def Holders (σ : Sigma) (b : Bid) : List Place := holdersOf σ.holders b

def HStar (σ : Sigma) (p : Place) : List Bid :=
  (σ.holders.filter (fun qb => overlap p qb.1)).bind (fun qb => qb.2)

def refsOf : List Borrow → Place → List Bid
  | [], _ => []
  | br :: rest, p =>
      if overlap br.place p then br.bid :: refsOf rest p else refsOf rest p

def live (σ : Sigma) (p : Place) : List Bid := refsOf σ.lam p

def AliasesStar (σ : Sigma) (p : Place) : List (Place × Bid) :=
  (live σ p).bind (fun b => (Holders σ b).map (fun q => (q, b)))

def targetOf (σ : Sigma) (b : Bid) : Option Place :=
  (σ.lam.find? (fun br => br.bid == b)).map (fun br => br.place)

def modeOf (σ : Sigma) (p : Place) : Option Mode :=
  (lookupPlace σ.gamma p).map (fun g => g.mode)

def tyOf (σ : Sigma) (p : Place) : Option Ty :=
  (lookupPlace σ.gamma p).map (fun g => g.ty)

def moved (σ : Sigma) (p : Place) : Prop :=
  ∃ q, q ∈ σ.moved ∧ overlap q p = true

/-! ## `ConsumeResult` -/

def removeOcc (σ : Sigma) (A : List Bid) : Sigma :=
  { σ with holders := σ.holders.map (fun qb => (qb.1, removeBids A qb.2)) }

def consumeLam (σ : Sigma) : List Borrow → List Borrow
  | [] => []
  | br :: rest =>
      if (holdersOf σ.holders br.bid).isEmpty then consumeLam σ rest
      else br :: consumeLam σ rest

def ConsumeResult (σ : Sigma) (A : List Bid) : Sigma :=
  let σ₁ := removeOcc σ A
  { σ₁ with lam := consumeLam σ₁ σ₁.lam }

/-- `consumeLam` only *drops* borrows; it never introduces new ones. -/
theorem mem_consumeLam {σ : Sigma} :
    ∀ {l : List Borrow} {br : Borrow}, br ∈ consumeLam σ l → br ∈ l
  | [], br, h => nomatch h
  | b :: bs, br, h => by
      simp only [consumeLam] at h
      cases hc : (holdersOf σ.holders b.bid).isEmpty with
      | true =>
          rw [hc] at h
          simp only at h
          exact List.Mem.tail _ (mem_consumeLam h)
      | false =>
          rw [hc] at h
          simp only at h
          cases h with
          | head => exact List.Mem.head _
          | tail _ ht => exact List.Mem.tail _ (mem_consumeLam ht)

theorem bidsAt_removeOcc (σ : Sigma) (A : List Bid) (q : Place) :
    bidsAt (removeOcc σ A) q = removeBids A (bidsAt σ q) := by
  unfold bidsAt removeOcc
  rw [lookupPlace_map_remove]
  cases lookupPlace σ.holders q with
  | none => rfl
  | some bs => rfl

theorem isHolder_consume_iff (σ : Sigma) (A : List Bid) (q : Place) (b : Bid) :
    IsHolder (ConsumeResult σ A) q b ↔ IsHolder σ q b ∧ b ∉ A := by
  unfold IsHolder
  dsimp [ConsumeResult]
  show b ∈ bidsAt (removeOcc σ A) q ↔ IsHolder σ q b ∧ b ∉ A
  rw [bidsAt_removeOcc]
  unfold IsHolder
  exact mem_removeBids

theorem consume_removes {σ : Sigma} {A : List Bid} {q : Place} {b : Bid}
    (hb : b ∈ A) : ¬ IsHolder (ConsumeResult σ A) q b := by
  intro h
  exact (isHolder_consume_iff σ A q b).1 h |>.2 hb

theorem consume_keeps {σ : Sigma} {A : List Bid} {q : Place} {b : Bid}
    (hb : b ∉ A) : IsHolder (ConsumeResult σ A) q b ↔ IsHolder σ q b := by
  rw [isHolder_consume_iff]
  exact ⟨fun h => h.1, fun h => ⟨h, hb⟩⟩

/-- `Consumed*(Σ,Σ')` at one occurrence. -/
def Consumed (σ σ' : Sigma) (q : Place) (b : Bid) : Prop :=
  IsHolder σ q b ∧ ¬ IsHolder σ' q b

/-- **L-Consume (occurrence form)**: `ConsumeResult σ A` removes exactly the
    occurrences whose bid is in `A`, and leaves every other occurrence intact. -/
theorem l_consume (σ : Sigma) (A : List Bid) (q : Place) (b : Bid) :
    Consumed σ (ConsumeResult σ A) q b ↔ IsHolder σ q b ∧ b ∈ A := by
  unfold Consumed
  rw [isHolder_consume_iff]
  cases hb : A.elem b with
  | false =>
      have hnb : b ∉ A := not_mem_of_elem_false hb
      constructor
      · intro h
        exact False.elim (absurd ⟨h.1, hnb⟩ h.2)
      · intro h
        exact False.elim (absurd h.2 hnb)
  | true =>
      have hbin : b ∈ A := List.mem_of_elem_eq_true hb
      constructor
      · intro h
        exact ⟨h.1, hbin⟩
      · intro h
        exact ⟨h.1, fun hh => hh.2 hbin⟩

/-! ## Dynamic configuration and `Match(Σ,S)` (M1–M5) -/

structure Dyn where
  gamma : List (Place × Binding)
  beta : List Borrow
  holds : List (Place × Bid)
  moved : List Place
  flight : List Bid
  deriving Repr, DecidableEq

def dynRefs (d : Dyn) (p : Place) : List Bid := refsOf d.beta p

/-- `Match(Σ,S)` from `spec/t4-proof.md` §3.5.0.  `A` is the handle set of the
    value currently in flight (M5). -/
structure Match (σ : Sigma) (d : Dyn) (A : List Bid) : Prop where
  m1 : d.gamma = σ.gamma
  m2 : d.beta = σ.lam
  m3 : ∀ q b, (q, b) ∈ d.holds ↔ IsHolder σ q b
  m4 : d.moved = σ.moved
  m5 : d.flight = A

theorem match_live_refs {σ : Sigma} {d : Dyn} {A : List Bid} {p : Place}
    (hm : Match σ d A) : live σ p = [] ↔ dynRefs d p = [] := by
  unfold live dynRefs
  rw [hm.m2]
  exact Iff.rfl

/-- Invariant I8: every active (not in-flight) borrow has a holder. -/
def LiveAliasInvariant (σ : Sigma) (A : List Bid) : Prop :=
  ∀ b, b ∈ lamBids σ → b ∉ A → ∃ q, IsHolder σ q b

/-- **L-Holder**: an active borrow that is not in flight is held by some place. -/
theorem l_holder {σ : Sigma} {d : Dyn} {A : List Bid} {b : Bid}
    (hm : Match σ d A) (hinv : LiveAliasInvariant σ A)
    (hb : b ∈ lamBids σ) (hfl : b ∉ A) : ∃ q, (q, b) ∈ d.holds := by
  cases hinv b hb hfl with
  | intro q hq => exact ⟨q, (hm.m3 q b).2 hq⟩

end LSys
