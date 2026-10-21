/-
  LSys/LetHandle.lean

  Handle-valued `let` with the **tagged** variable-place encoding.

  `varPlace x = [0, x]` has length 2 while heap places `[l]` have length 1, so
  the two never collide.  Therefore a handle-valued `let` can be represented
  statically by prepending the new holder entry at `varPlace x`:

    bindHolders σ x A = { σ with holders := (varPlace x, A) :: σ.holders }

  `MatchUS.letVarWithHolders` shows that `bindHolders σ x (holdersOfVal v)`
  matches `letVar c x v` for *any* value `v` (including handle values).  No
  freshness condition on `envHolds` is needed: `letVar` overwrites the entry
  and `lookupPlace` returns the most recent binding.
-/

import LSys.Preservation
import LSys.Env

namespace LSys

set_option linter.unusedVariables false

/-- Heap place `[l]` and tagged variable place `[0, x]` differ (lengths 1 vs 2). -/
theorem heapPlace_ne_varPlace (l : Loc) (x : Var) : ([l] : Place) ≠ varPlace x := by
  intro h
  have hlen := congrArg List.length h
  simp [varPlace] at hlen

/-- Tagged variable places are injective. -/
theorem varPlace_inj {x y : Var} (h : varPlace x = varPlace y) : x = y := by
  have h' : (0 :: [x]) = (0 :: [y]) := h
  injection h' with _ h1
  injection h1 with hx _

/-- Handle-valued (indeed arbitrary) `let` preserves `MatchUS` after updating
    the static holders at `varPlace x`. -/
theorem MatchUS.letVarWithHolders {σ : Sigma} {c : ConfE} {s : State}
    {x : Var} {v : RVal} (hm : MatchUS σ c s) :
    MatchUS (bindHolders σ x (holdersOfVal v)) (LSys.letVar c x v) s := by
  constructor
  · -- static domain ⊆ runtime domain: the runtime env only grows
    intro y hy
    cases Nat.decEq y x with
    | isTrue hxy =>
        cases hxy
        have hlt : (LSys.letVar c x v).env x = some v := by
          dsimp only [LSys.letVar]
          rw [setEnv_same]
        rw [hlt]
        rfl
    | isFalse hxy =>
        have hlt : (LSys.letVar c x v).env y = c.env y := by
          dsimp only [LSys.letVar]
          rw [setEnv_other hxy]
        rw [hlt]
        exact hm.gamma_dom_sub y hy
  · exact hm.btab_sound
  · exact hm.btab_complete
  · -- holder occurrences: the new entry is exactly at `varPlace x`
    intro o
    cases o with
    | mk pos bid =>
        cases pos with
        | heap l =>
            have hne : ¬ ((varPlace x) = ([l] : Place)) :=
              fun hh => heapPlace_ne_varPlace l x hh.symm
            have hbids : bidsAt (bindHolders σ x (holdersOfVal v)) [l]
                = bidsAt σ [l] := by
              simp [bindHolders, bidsAt, lookupPlace, hne]
            dsimp only [HoldOccurs, holdsInSigma, IsHolder]
            rw [hbids]
            exact hm.holders (Occ.mk (HoldPos.heap l) bid)
        | env y =>
            cases Nat.decEq y x with
            | isTrue hxy =>
                cases hxy
                have hrun : holdsAtPos (LSys.letVar c x v) (HoldPos.env x)
                    = holdersOfVal v := by
                  simp [holdsAtPos, LSys.letVar]
                have hstat : bidsAt (bindHolders σ x (holdersOfVal v)) (varPlace x)
                    = holdersOfVal v := by
                  simp [bindHolders, bidsAt, lookupPlace]
                dsimp only [HoldOccurs, holdsInSigma, IsHolder]
                rw [hrun, hstat]
                exact Iff.rfl
            | isFalse hxy =>
                have hne : ¬ ((varPlace x) = (varPlace y)) :=
                  fun hh => hxy (varPlace_inj hh).symm
                have hbids : bidsAt (bindHolders σ x (holdersOfVal v)) (varPlace y)
                    = bidsAt σ (varPlace y) := by
                  simp [bindHolders, bidsAt, lookupPlace, hne]
                have hrun : holdsAtPos (LSys.letVar c x v) (HoldPos.env y)
                    = holdsAtPos c (HoldPos.env y) := by
                  simp [holdsAtPos, LSys.letVar, hxy]
                dsimp only [HoldOccurs, holdsInSigma, IsHolder]
                rw [hrun, hbids]
                exact hm.holders (Occ.mk (HoldPos.env y) bid)
  · exact hm.borrow

end LSys
