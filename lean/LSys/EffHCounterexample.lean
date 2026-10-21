/-
  LSys/EffHCounterexample.lean

  The composition statement

    EffHStepEvalC σ c e c' σ' A → EffH σ' c'.expr σ'' B → EffH σ e σ'' B

  is **false**.  The obstruction is that `EffH` is a syntax-level effect and
  cannot know the handles of the value bound to a variable, while a
  configuration step (`varV`/`moveV`/`readV`) resolves the value from the
  environment/heap and reports its actual handles `A`:

    EffH σ (var x) σ []          -- static: no handle information
    effH step  var x ⇒ val v     -- dynamic: A = holdersOfR v = [b]

  Hence even for the leaf step `var x ⇒ val (valH b)` the post handle set
  `[b]` cannot be produced by `EffH` of `var x`, so no fixed-output
  composition can hold.  A surrounding `write` makes the state mismatch
  observable (`setHolders` stores `[]` vs `[b]`).

  The fix is to make the step effect *environment-relative* (`EffH`
  parameterized by `EvalEnv`/`EvalHeap`), or to use the handle-free
  `Effect.Eff` for state (`NoEscape`) reasoning.
-/

import LSys.EvalConf
import LSys.EffHPath

namespace LSys

/-- Inversion of the only `EffH` rule for `var`. -/
theorem effH_var_inv {σ σ' : Sigma} {x : Var} {A : List Bid}
    (h : Effect.EffH σ (Expr.var x) σ' A) : σ' = σ ∧ A = [] := by
  cases h with
  | var => exact ⟨rfl, rfl⟩

/-- The handle list stored by `setHolders` cannot be changed by the static
    effect of `var`; this is the observable form of the obstruction. -/
theorem setHolders_ne (σ : Sigma) {p : Place} {A B : List Bid} (h : A ≠ B) :
    setHolders σ p A ≠ setHolders σ p B := by
  intro he
  apply h
  have hh := congrArg Sigma.holders he
  dsimp only [setHolders] at hh
  injection hh with hpair _
  injection hpair with _ hAB

/-- Refutation of the fixed-output composition of `EffHStepEvalC`/`EffH`. -/
theorem not_effHStepEvalC_eff_compose :
    ¬ (∀ (σ σ' σ'' : Sigma) (c c' : EvalConf) (e : Expr) (A B : List Bid),
        EffHStepEvalC σ c e c' σ' A →
        Effect.EffH σ' c'.expr σ'' B →
        Effect.EffH σ e σ'' B) := by
  intro hcomp
  -- A concrete state with no borrows and no holders.
  let σ0 : Sigma := ⟨[], [], [], [], Caps.mk true []⟩
  -- `x` is bound to the handle value `valH 1`.
  let env0 : EvalEnv := fun x => if x = 0 then some (RVal.valH 1) else none
  let c0 : EvalConf := ⟨Expr.var 0, env0, fun _ => none, State.mk 0⟩
  -- The residual configuration after `var 0 ⇒ val (valH 1)`.
  let c1 : EvalConf := withExpr c0 (Expr.val (Val.valH 1))
  -- The step `var 0 ⇒ val (valH 1)` with actual handles `[1]`.
  have hstep : EffHStepEvalC σ0 c0 (Expr.var 0) c1 σ0 [1] := by
    have hx : c0.env 0 = some (RVal.valH 1) := by
      dsimp only [c0, env0]
      exact if_pos rfl
    have h0 := EffHStepEvalC.varV (σ := σ0) (c := c0) (x := 0)
      (v := RVal.valH 1) hx
    exact h0
  -- The residual effect of the value `valH 1` carries the handle `[1]`.
  have hres : Effect.EffH σ0 c1.expr σ0 [1] :=
    Effect.EffH.val σ0 (Val.valH 1)
  -- Composition would give `EffH σ0 (var 0) σ0 [1]`.
  have hbad : Effect.EffH σ0 (Expr.var 0) σ0 [1] :=
    hcomp σ0 σ0 σ0 c0 c1 (Expr.var 0) [1] [1] hstep hres
  -- But `EffH` of `var 0` has empty handles.
  cases effH_var_inv hbad with
  | intro _ hA =>
      cases hA

end LSys
