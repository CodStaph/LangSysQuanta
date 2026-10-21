/-
  LSys/PlaceWF.lean

  A **well-formedness predicate** for places, added additively (no change to
  `Sigma`/`ConfE`/`Place`):

    WFPlace p  :=  (∃ l, p = [l]) ∨ (∃ x, p = varPlace x)

  Heap places are `[l]` (length 1); tagged variable places are
  `varPlace x = [0, x]` (length 2).  The two families are disjoint, so the
  matching relation can track environment and heap holders separately.

  The lemmas below show that the static operations (`addBorrow`,
  `clearPlace`, `setHolders`, `removeOcc`, `ConsumeResult`) preserve
  well-formedness of the places they store.  This lets a future
  `MatchUS`-with-well-formedness assume `WFPlace` on `Σ.gamma`/`Σ.lam`/
  `Σ.holders` without touching the core definitions.

  Note: arbitrary *field paths* are not `WFPlace` (they are a separate,
  currently unmodelled family); the F0 core treats places as opaque, so this
  is an input well-formedness assumption, not a theorem about programs.
-/

import LSys.LetHandle

namespace LSys

set_option linter.unusedVariables false

/-- Well-formed places: a heap place `[l]` or a tagged variable place. -/
def WFPlace (p : Place) : Prop :=
  (∃ l, p = [l]) ∨ (∃ x, p = varPlace x)

theorem WFPlace.heap (l : Loc) : WFPlace [l] := Or.inl ⟨l, rfl⟩

theorem WFPlace.varPlace (x : Var) : WFPlace (varPlace x) := Or.inr ⟨x, rfl⟩

/-- The places of the borrow table are well-formed. -/
def WFLam (σ : Sigma) : Prop := ∀ br, br ∈ σ.lam → WFPlace br.place

/-- The places of the holder table are well-formed. -/
def WFHolds (σ : Sigma) : Prop := ∀ p A, (p, A) ∈ σ.holders → WFPlace p

/-- The places of the static environment are well-formed. -/
def WFGamma (σ : Sigma) : Prop := ∀ p b, (p, b) ∈ σ.gamma → WFPlace p

/-! ### Membership helpers (core Lean has no `List.mem_map`/`mem_filter`) -/

theorem mem_filter_subset {α : Type} {f : α → Bool} {l : List α} {a : α}
    (h : a ∈ l.filter f) : a ∈ l := by
  induction l with
  | nil => cases h
  | cons b bs ih =>
      simp only [List.filter] at h
      cases hb : f b with
      | true =>
          rw [hb] at h
          simp only at h
          cases h with
          | head => exact List.Mem.head _
          | tail _ ht => exact List.Mem.tail _ (ih ht)
      | false =>
          rw [hb] at h
          simp only at h
          exact List.Mem.tail _ (ih h)

theorem mem_map_subset {α β : Type} {f : α → β} {l : List α} {b : β}
    (h : b ∈ l.map f) : ∃ a, a ∈ l ∧ f a = b := by
  induction l with
  | nil => cases h
  | cons x xs ih =>
      simp only [List.map] at h
      cases h with
      | head => exact ⟨x, List.Mem.head _, rfl⟩
      | tail _ ht =>
          cases ih ht with
          | intro a rest =>
              cases rest with
              | intro ha hb => exact ⟨a, List.Mem.tail _ ha, hb⟩

/-! ### Closure under static operations -/

theorem WFLam.addBorrow {σ : Sigma} {b : Bid} {p : Place} {m : Mode}
    (h : WFLam σ) (hp : WFPlace p) : WFLam (LSys.addBorrow σ b p m) := by
  intro br hbr
  have hlam : (LSys.addBorrow σ b p m).lam
      = { bid := b, place := p, mode := m, rgn := rgnOf σ p } :: σ.lam := rfl
  rw [hlam] at hbr
  cases hbr with
  | head => exact hp
  | tail _ ht => exact h br ht

theorem WFHolds.clearPlace {σ : Sigma} {p : Place} (h : WFHolds σ) :
    WFHolds (LSys.clearPlace σ p) := by
  intro q A hq
  have hh : (LSys.clearPlace σ p).holders
      = σ.holders.filter (fun qb => !(overlap qb.1 p)) := rfl
  rw [hh] at hq
  exact h q A (mem_filter_subset hq)

theorem WFHolds.setHolders {σ : Sigma} {p : Place} {A : List Bid}
    (h : WFHolds σ) (hp : WFPlace p) : WFHolds (LSys.setHolders σ p A) := by
  intro q B hq
  have hh : (LSys.setHolders σ p A).holders = (p, A) :: σ.holders := rfl
  rw [hh] at hq
  cases hq with
  | head => exact hp
  | tail _ ht => exact h q B ht

theorem WFHolds.removeOcc {σ : Sigma} {A : List Bid} (h : WFHolds σ) :
    WFHolds (LSys.removeOcc σ A) := by
  intro q B hq
  have hh : (LSys.removeOcc σ A).holders
      = σ.holders.map (fun qb => (qb.1, removeBids A qb.2)) := rfl
  rw [hh] at hq
  cases mem_map_subset hq with
  | intro a rest =>
      cases rest with
      | intro ha hb =>
          cases a with
          | mk q' bs =>
              simp only at hb
              injection hb with hq' _
              subst hq'
              exact h q' bs ha

theorem WFLam.removeOcc {σ : Sigma} {A : List Bid} (h : WFLam σ) :
    WFLam (LSys.removeOcc σ A) := by
  intro br hbr
  exact h br hbr

theorem WFHolds.consumeResult {σ : Sigma} {A : List Bid} (h : WFHolds σ) :
    WFHolds (LSys.ConsumeResult σ A) :=
  WFHolds.removeOcc h

theorem WFLam.consumeResult {σ : Sigma} {A : List Bid} (h : WFLam σ) :
    WFLam (LSys.ConsumeResult σ A) := by
  intro br hbr
  exact h br (mem_consumeLam hbr)

end LSys
