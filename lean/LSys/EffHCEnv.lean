/-
  LSys/EffHCEnv.lean

  `EffHC` only depends on the environment through the variables of the
  expression (`fvE`, the standard free variables; `EffHC`'s `let`/`borrow` do
  not bind in the environment).
-/

import LSys.EffHC
import LSys.FreeVars

namespace LSys

set_option linter.unusedVariables false

theorem EffHC.env_agree :
    ∀ {env env' : EvalEnv} {heap : EvalHeap} {e : Expr} {σ σ' : Sigma}
      {A : List Bid},
      (∀ x, x ∈ fvE e → env x = env' x) →
      EffHC env heap e σ σ' A → EffHC env' heap e σ σ' A := by
  intro env env' heap e σ σ' A hag h
  induction h generalizing env' with
  | val => exact EffHC.val
  | var hx =>
      exact EffHC.var (by rw [← hag _ (List.Mem.head _)]; exact hx)
  | abort => exact EffHC.abort
  | op ha hb iha ihb =>
      exact EffHC.op
        (iha (fun y hy => hag y (List.mem_append_of_mem_left _ hy)))
        (ihb (fun y hy => hag y (List.mem_append_of_mem_right _ hy)))
  | letE ha hb iha ihb =>
      exact EffHC.letE
        (iha (fun y hy => hag y (List.mem_append_of_mem_left _ hy)))
        (ihb (fun y hy => hag y (List.mem_append_of_mem_right _ hy)))
  | move h => exact EffHC.move h
  | read h => exact EffHC.read h
  | write he ihe =>
      exact EffHC.write (ihe (fun y hy => hag y hy))
  | seq ha hb iha ihb =>
      exact EffHC.seq
        (iha (fun y hy => hag y (List.mem_append_of_mem_left _ hy)))
        (ihb (fun y hy => hag y (List.mem_append_of_mem_right _ hy)))
  | region he ihe =>
      exact EffHC.region (ihe (fun y hy => hag y hy))
  | alloc he ihe =>
      exact EffHC.alloc (ihe (fun y hy => hag y hy))
  | freeze => exact EffHC.freeze
  | recover he ihe =>
      exact EffHC.recover (ihe (fun y hy => hag y hy))
  | borrow he ihe =>
      exact EffHC.borrow (ihe (fun y hy => hag y hy))
  | drop => exact EffHC.drop
  | call ha hb iha ihb =>
      exact EffHC.call
        (iha (fun y hy => hag y (List.mem_append_of_mem_left _ hy)))
        (ihb (fun y hy => hag y (List.mem_append_of_mem_right _ hy)))
  | ret he ihe => exact EffHC.ret (ihe (fun y hy => hag y hy))
  | spawn he ihe => exact EffHC.spawn (ihe (fun y hy => hag y hy))
  | atomic he ihe => exact EffHC.atomic (ihe (fun y hy => hag y hy))
  | unsafeE he ihe => exact EffHC.unsafeE (ihe (fun y hy => hag y hy))
  | deref he ihe => exact EffHC.deref (ihe (fun y hy => hag y hy))

/-- `RegionSafeHC` only depends on the environment through `fvE`. -/
theorem RegionSafeHC.env_agree {env env' : EvalEnv} {heap : EvalHeap}
    {σ : Sigma} {R : Rgn} {e : Expr}
    (hsafe : RegionSafeHC env heap σ R e)
    (hag : ∀ x, x ∈ fvE e → env x = env' x) :
    RegionSafeHC env' heap σ R e := by
  intro σ' A hres
  exact hsafe σ' A (EffHC.env_agree (fun x hx => (hag x hx).symm) hres)

/-- Extension version of safety monotonicity, assuming all `fvE` variables of
    the expression are already bound in the old environment.  (The `WTKH.region`
    rule itself quantifies over all extensions, so this is a supporting lemma.) -/
theorem RegionSafeHC.env_ext {env env' : EvalEnv} {heap : EvalHeap}
    {σ : Sigma} {R : Rgn} {e : Expr}
    (hsafe : RegionSafeHC env heap σ R e)
    (hext : EnvExtends env env')
    (hbound : ∀ x, x ∈ fvE e → ∃ v, env x = some v) :
    RegionSafeHC env' heap σ R e := by
  apply RegionSafeHC.env_agree hsafe
  intro x hx
  cases hbound x hx with
  | intro v hv =>
      exact hv.trans (hext x v hv).symm

end LSys
