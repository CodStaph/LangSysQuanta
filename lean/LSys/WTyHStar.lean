/-
  LSys/WTyHStar.lean

  Reflexive-transitive closure of `EffHStepEvalC` and multi-step preservation
  of `WTyH`.

  `EffStepStar σ c e σ' c' e'` runs zero or more configuration steps from
  `e` (under `c`, state `σ`) to `e'` (under `c'`, state `σ'`).  The star is
  needed for contexts whose step is not a single congruence step, e.g. a
  `borrow` wrapper: `borrow p x e` first takes `borrowEnter` to `e` at
  `addBorrow σ 0 p mut`, then `e` runs.

  Main result: `WTyH.preserved_star` keeps the final state and handles along
  an arbitrary number of steps.
-/

import LSys.WTyHCtx

namespace LSys

set_option linter.unusedVariables false

/-- Reflexive-transitive closure of configuration steps. -/
inductive EffStepStar :
    Sigma → EvalConf → Expr → Sigma → EvalConf → Expr → Prop where
  | refl {σ : Sigma} {c : EvalConf} {e : Expr} :
      EffStepStar σ c e σ c e
  | step {σ : Sigma} {c : EvalConf} {e : Expr} {c' : EvalConf}
      {σ' : Sigma} {A' : List Bid}
      (h : EffHStepEvalC σ c e c' σ' A')
      {σ'' : Sigma} {c'' : EvalConf} {e'' : Expr}
      (rest : EffStepStar σ' c' c'.expr σ'' c'' e'') :
      EffStepStar σ c e σ'' c'' e''

/-- `WTyH` is preserved along any number of steps. -/
theorem WTyH.preserved_star :
    ∀ {σ σ₁ : Sigma} {A : List Bid} {e : Expr} {c : EvalConf},
      WTyH c.env c.heap e σ σ₁ A →
      ∀ {σ' : Sigma} {c' : EvalConf} {e' : Expr},
        EffStepStar σ c e σ' c' e' →
        WTyH c'.env c'.heap e' σ' σ₁ A := by
  intro σ σ₁ A e c hwt σ' c' e' hstar
  induction hstar with
  | refl => exact hwt
  | step h rest ih =>
      exact ih (WTyH.preserved _ hwt h rfl rfl)

/-- Concatenation of step sequences. -/
theorem EffStepStar.trans {σ σ' σ'' : Sigma} {c c' c'' : EvalConf}
    {e e' e'' : Expr}
    (h1 : EffStepStar σ c e σ' c' e')
    (h2 : EffStepStar σ' c' e' σ'' c'' e'') :
    EffStepStar σ c e σ'' c'' e'' := by
  induction h1 with
  | refl => exact h2
  | step h _ ih => exact EffStepStar.step h (ih h2)

/-- Multi-step preservation inside a congruence context. -/
theorem WTyH.plug_star_preserved {C : Ctx} (hC : CtxCong C)
    {e e' : Expr} {σ σ₁ σ' : Sigma} {A : List Bid} {c c' : EvalConf}
    (hstar : EffStepStar σ c e σ' c' e')
    (hwt : WTyH c.env c.heap (plug C e) σ σ₁ A) :
    WTyH c'.env c'.heap (plug C e') σ' σ₁ A := by
  induction hstar with
  | refl => exact hwt
  | step h _ ih =>
      exact ih (WTyH.plug_preserved hC h hwt)

end LSys
