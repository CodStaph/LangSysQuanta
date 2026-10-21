/-
  LSys/EffHMeasure.lean

  Link from the configuration-level effect relation `EffHStepEvalC` to the
  canonical step relation `StepEvalC`.

  `EffHStepEvalC` has two stutter rules (`val`, `abort`) that do not change the
  expression; every other rule corresponds one-to-one to a `StepEvalC` rule.
  Consequently each effect step is either a stutter or strictly decreases the
  measure `M = (w, r)` (via `stepEvalC_decreases`).

  This gives termination/well-foundedness of configuration-level effect steps,
  which is needed when the `EffStepStar` closure is used for whole-program
  reasoning.
-/

import LSys.EvalConf
import LSys.EvalEff

namespace LSys

set_option linter.unusedVariables false

/-- Every `EffHStepEvalC` step is either a stutter or a `StepEvalC` step. -/
theorem EffHStepEvalC.toStepEvalC {σ σ' : Sigma} {c c' : EvalConf}
    {e : Expr} {A : List Bid}
    (h : EffHStepEvalC σ c e c' σ' A) :
    c' = withExpr c e ∨ StepEvalC { c with expr := e } c' := by
  induction h with
  | varV hv => exact Or.inr (StepEvalC.varV hv)
  | moveV hv => exact Or.inr (StepEvalC.moveV hv)
  | readV hv => exact Or.inr (StepEvalC.readV hv)
  | val => exact Or.inl rfl
  | abort => exact Or.inl rfl
  | op => exact Or.inr StepEvalC.op
  | opAny => exact Or.inr StepEvalC.opAny
  | letV => exact Or.inr StepEvalC.letV
  | seqV => exact Or.inr StepEvalC.seqV
  | callV => exact Or.inr StepEvalC.callV
  | freeze => exact Or.inr (StepEvalC.freeze (b := freshBid σ))
  | recover => exact Or.inr StepEvalC.recover
  | recoverAny _ => exact Or.inr StepEvalC.recoverAny
  | write => exact Or.inr StepEvalC.write
  | alloc => exact Or.inr StepEvalC.alloc
  | drop => exact Or.inr StepEvalC.drop
  | regionV => exact Or.inr StepEvalC.regionV
  | retV => exact Or.inr StepEvalC.retV
  | spawnV => exact Or.inr StepEvalC.spawnV
  | atomicV => exact Or.inr StepEvalC.atomicV
  | unsafeV => exact Or.inr StepEvalC.unsafeV
  | derefV => exact Or.inr StepEvalC.derefV
  | derefAny => exact Or.inr StepEvalC.derefAny
  | borrowEnter => exact Or.inr StepEvalC.borrowEnter
  | borrowExit => exact Or.inr StepEvalC.borrowExit
  | abortBorrow => exact Or.inr StepEvalC.abortBorrow
  | opL h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.opL hstep)
  | opR hv h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.opR hv hstep)
  | letB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.letB hstep)
  | writeB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.writeB hstep)
  | seqL h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.seqL hstep)
  | allocB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.allocB hstep)
  | regionB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.regionB hstep)
  | recoverB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.recoverB hstep)
  | callB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.callB hstep)
  | retB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.retB hstep)
  | spawnB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.spawnB hstep)
  | atomicB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.atomicB hstep)
  | unsafeB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.unsafeB hstep)
  | derefB h ih =>
      cases ih with
      | inl hstut => exact Or.inl (by cases hstut; rfl)
      | inr hstep => exact Or.inr (StepEvalC.derefB hstep)

/-- Each `EffHStepEvalC` step either stutters or strictly decreases `M`. -/
theorem EffHStepEvalC.step_decreases_or {σ σ' : Sigma} {c c' : EvalConf}
    {e : Expr} {A : List Bid}
    (h : EffHStepEvalC σ c e c' σ' A) :
    c' = withExpr c e ∨ Mlt (M c'.expr c'.state) (M e c.state) := by
  cases EffHStepEvalC.toStepEvalC h with
  | inl hstut => exact Or.inl hstut
  | inr hstep => exact Or.inr (stepEvalC_decreases hstep)

end LSys
