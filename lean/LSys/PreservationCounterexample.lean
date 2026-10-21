/-
  LSys/PreservationCounterexample.lean

  Check of the current `Preservation` statement.

  Result: **the statement is false as defined**, because `StepPM` conjoins
  `Eff` and `RStepE` without requiring that the runtime step implements the
  static effect.  A `val` expression (static effect = identity) can be paired
  with `RStepE.letVar`, which adds an environment binding; `MatchU` then fails
  on `gamma_dom`.

  The missing definition is a coherence relation between `Eff` and `RStepE`
  (or a `StepPM` inductive whose constructors couple them rule by rule).
-/

import LSys.Preservation

namespace LSys

set_option linter.unusedVariables false

def cexSigmaP : Sigma :=
  { gamma := [],
    lam := [],
    moved := [],
    holders := [],
    caps := { alloc := true, effects := [] } }

def cexConfP : ConfE :=
  { heap := fun _ => none,
    env := fun _ => none,
    envHolds := fun _ => none,
    btab := [],
    flight := [0] }

def cexS0 : State := ⟨1⟩
def cexS1 : State := ⟨0⟩

theorem cex_match_in : MatchU cexSigmaP cexConfP cexS0 := by
  constructor
  · intro x
    unfold cexSigmaP cexConfP varPlace lookupPlace
    rfl
  · intro e he
    cases he
  · intro br hbr
    cases hbr
  · intro o
    cases o with
    | mk pos bid =>
        cases pos with
        | heap l =>
            simp [HoldOccurs, holdsAtPos, holdsInSigma, cexConfP, cexSigmaP,
              bidsAt, lookupPlace, IsHolder]
        | env x =>
            simp [HoldOccurs, holdsAtPos, holdsInSigma, cexConfP, cexSigmaP,
              bidsAt, lookupPlace, IsHolder]
  · rfl

theorem cex_stepPM :
    StepPM cexSigmaP cexConfP (Expr.val Val.unit) cexS0
      cexSigmaP (letVar cexConfP 0 (RVal.nat 0)) (Expr.val Val.unit) cexS1 := by
  refine ⟨cex_match_in, ?_, ?_, ?_, ?_⟩
  · exact Step.borrowExit
  · exact RStepE.letVar (by rfl)
  · trivial
  · exact Eff.val _ _

theorem cex_not_match_out :
    ¬ MatchU cexSigmaP (letVar cexConfP 0 (RVal.nat 0)) cexS1 := by
  intro h
  have hg := h.gamma_dom 0
  unfold cexSigmaP letVar cexConfP setEnv varPlace lookupPlace at hg
  dsimp only at hg
  rw [if_pos rfl] at hg
  -- hg : false = true
  cases hg

/-- The current `Preservation` statement is false. -/
theorem not_preservation_current : ¬ Preservation cexSigmaP := by
  intro hp
  have hwt : WT cexSigmaP (Expr.val Val.unit) := WT.val _
  have h := hp hwt cex_match_in cex_stepPM
  exact cex_not_match_out h.2

end LSys
