/-
  LSys/LamStep.lean

  **Composition of the Λ-only effect with a configuration step**
  (`LamEff.step_compose`, §8.3 step 2).

  Given a step `e → c'.expr` (state `σ → σ'`) and a `Λ`-effect of the residual,
  the same effect can be pulled back to `e`, with an output whose `Λ` contains
  the residual's `Λ` (at triple granularity).

  The proof is an induction on `EffHStepEvalCK`:

  * redex rules: the residual's `LamEff` is determined by the redex shape, so we
    invert it and rebuild the corresponding `LamEff` rule for `e`; the only
    mismatch is that rules like `write`/`move`/`drop`/`recover` leave `Λ`
    unchanged (`holders` only) or only remove entries
    (`lamSub_consumeResult`);
  * context rules: the residual is `op u b`, `let x = u in b`, … and its
    `LamEff` is the corresponding binary/prefix rule.  The stepping part is
    handled by the induction hypothesis; the *following* part (`b`) has to be
    replayed from the coarsened state, which is `LamEff.mono`.
-/

import LSys.EffHCK
import LSys.LamEff

namespace LSys

set_option linter.unusedVariables false

/-- An aborting continuation still has *some* `Λ`-effect, and that effect
    contains the starting `Λ` (`LamEff.total` + `LamEff.le`).  This is the goal
    shape of every `abortCtx` step in `LamEff.step_compose`. -/
theorem lamEff_abort_goal {E : Expr} {σ : Sigma} :
    ∃ σ₁, LamEff E σ σ₁ ∧ LamSub σ σ₁ := by
  cases LamEff.total E σ with
  | intro σ₁ h => exact ⟨σ₁, h, LamEff.le h⟩

theorem LamEff.step_compose {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (hstep : EffHStepEvalCK σ c e c' σ' A) {σ'' : Sigma}
    (hres : LamEff c'.expr σ' σ'') :
    ∃ σ₁, LamEff e σ σ₁ ∧ LamSub σ'' σ₁ := by
  induction hstep generalizing σ'' with
  -- value-projection and stutter redexes
  | varV _ =>
      cases hres with
      | val => exact ⟨σ, LamEff.var, LamSub.refl σ⟩
  | moveV _ =>
      cases hres with
      | val => exact ⟨σ, LamEff.move, LamSub.refl σ⟩
  | readV _ =>
      cases hres with
      | val => exact ⟨_, LamEff.read, LamSub.refl _⟩
  | val =>
      cases hres with
      | val => exact ⟨σ, LamEff.val, LamSub.refl σ⟩
  | abort =>
      cases hres with
      | abort => exact ⟨σ, LamEff.abort, LamSub.refl σ⟩
  -- arithmetical redexes
  | op =>
      cases hres with
      | val => exact ⟨σ, LamEff.op LamEff.val LamEff.val, LamSub.refl σ⟩
  | opAny =>
      cases hres with
      | val => exact ⟨σ, LamEff.op LamEff.val LamEff.val, LamSub.refl σ⟩
  -- redexes that enter a sub-expression
  | letV _ =>
      -- `bindHolders` only touches `holders`, so `Λ` is unchanged; replay the
      -- body from `σ` itself.
      cases LamEff.mono (τ := σ) hres rfl (LamSub.refl σ) with
      | intro σb rest =>
          cases rest with
          | intro hb hsub =>
              exact ⟨σb, LamEff.letE LamEff.val hb, hsub⟩
  | seqV =>
      exact ⟨σ'', LamEff.seq LamEff.val hres, LamSub.refl σ''⟩
  | callV =>
      exact ⟨σ'', LamEff.call LamEff.val hres, LamSub.refl σ''⟩
  | borrowEnter _ =>
      exact ⟨σ'', LamEff.borrow hres, LamSub.refl σ''⟩
  -- state-changing redexes
  | freeze =>
      cases hres with
      | val => exact ⟨_, LamEff.freeze, LamSub.refl _⟩
  | recover =>
      cases hres with
      | val =>
          exact ⟨σ, LamEff.recoverCtx LamEff.val, lamSub_consumeResult σ [_]⟩
  | recoverAny _ =>
      cases hres with
      | val =>
          exact ⟨σ, LamEff.recoverCtx LamEff.val, lamSub_consumeResult σ []⟩
  | write =>
      cases hres with
      | val => exact ⟨σ, LamEff.write LamEff.val, LamSub.refl σ⟩
  | alloc =>
      cases hres with
      | val => exact ⟨σ, LamEff.alloc LamEff.val, LamSub.refl σ⟩
  | drop =>
      cases hres with
      | val => exact ⟨σ, LamEff.drop, LamSub.refl σ⟩
  | regionV =>
      cases hres with
      | val => exact ⟨σ, LamEff.region LamEff.val, LamSub.refl σ⟩
  | retV =>
      cases hres with
      | val => exact ⟨σ, LamEff.ret LamEff.val, LamSub.refl σ⟩
  | spawnV =>
      cases hres with
      | val => exact ⟨σ, LamEff.spawn LamEff.val, LamSub.refl σ⟩
  | atomicV =>
      cases hres with
      | val => exact ⟨σ, LamEff.atomic LamEff.val, LamSub.refl σ⟩
  | unsafeV =>
      cases hres with
      | val => exact ⟨σ, LamEff.unsafeE LamEff.val, LamSub.refl σ⟩
  | derefV =>
      cases hres with
      | val => exact ⟨σ, LamEff.deref LamEff.val, LamSub.refl σ⟩
  | derefAny =>
      cases hres with
      | val => exact ⟨σ, LamEff.deref LamEff.val, LamSub.refl σ⟩
  | borrowExit =>
      cases hres with
      | val => exact ⟨σ, LamEff.val, LamSub.refl σ⟩
  | abortBorrow =>
      cases hres with
      | abort => exact ⟨σ, LamEff.abort, LamSub.refl σ⟩
  -- abort propagation (`abortCtx`, tail contexts only)
  | abortOpR _ =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortAlloc =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortRegion =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortRet =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortSpawn =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortAtomic =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortUnsafe =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortDeref =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortOpL =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortLetB =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortSeqL =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortCallB =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortWriteB =>
      cases hres with
      | abort => exact lamEff_abort_goal
  | abortRecoverB =>
      cases hres with
      | abort => exact lamEff_abort_goal
  -- context rules whose continuation must be replayed (`LamEff.mono`)
  | opL h ih =>
      cases hres with
      | op hu hb =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  have hγ := (LamEff.gamma_eq hu).trans
                    ((EffHStepEvalCK.gamma_same h).trans
                      (LamEff.gamma_eq ha').symm)
                  cases LamEff.mono hb hγ hsub_a with
                  | intro σb rest2 =>
                      cases rest2 with
                      | intro hb' hsub_b =>
                          exact ⟨σb, LamEff.op ha' hb', hsub_b⟩
  | letB h ih =>
      cases hres with
      | letE hu hb =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  have hγ := (LamEff.gamma_eq hu).trans
                    ((EffHStepEvalCK.gamma_same h).trans
                      (LamEff.gamma_eq ha').symm)
                  cases LamEff.mono hb hγ hsub_a with
                  | intro σb rest2 =>
                      cases rest2 with
                      | intro hb' hsub_b =>
                          exact ⟨σb, LamEff.letE ha' hb', hsub_b⟩
  | seqL h ih =>
      cases hres with
      | seq hu hb =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  have hγ := (LamEff.gamma_eq hu).trans
                    ((EffHStepEvalCK.gamma_same h).trans
                      (LamEff.gamma_eq ha').symm)
                  cases LamEff.mono hb hγ hsub_a with
                  | intro σb rest2 =>
                      cases rest2 with
                      | intro hb' hsub_b =>
                          exact ⟨σb, LamEff.seq ha' hb', hsub_b⟩
  | callB h ih =>
      cases hres with
      | call hu hb =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  have hγ := (LamEff.gamma_eq hu).trans
                    ((EffHStepEvalCK.gamma_same h).trans
                      (LamEff.gamma_eq ha').symm)
                  cases LamEff.mono hb hγ hsub_a with
                  | intro σb rest2 =>
                      cases rest2 with
                      | intro hb' hsub_b =>
                          exact ⟨σb, LamEff.call ha' hb', hsub_b⟩
  -- context rules with a single prefix position
  | opR hv _ ih =>
      cases IsVal.exists_val hv with
      | intro v he =>
          subst he
          cases hres with
          | op hu hb =>
              cases hu
              cases ih hb with
              | intro σ₁ rest =>
                  cases rest with
                  | intro hb' hsub =>
                      exact ⟨σ₁, LamEff.op LamEff.val hb', hsub⟩
  | writeB _ ih =>
      cases hres with
      | write hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.write ha', hsub_a⟩
  | allocB _ ih =>
      cases hres with
      | alloc hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.alloc ha', hsub_a⟩
  | regionB _ ih =>
      cases hres with
      | region hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.region ha', hsub_a⟩
  | recoverB _ ih =>
      cases hres with
      | recoverCtx hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.recoverCtx ha', hsub_a⟩
  | retB _ ih =>
      cases hres with
      | ret hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.ret ha', hsub_a⟩
  | spawnB _ ih =>
      cases hres with
      | spawn hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.spawn ha', hsub_a⟩
  | atomicB _ ih =>
      cases hres with
      | atomic hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.atomic ha', hsub_a⟩
  | unsafeB _ ih =>
      cases hres with
      | unsafeE hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.unsafeE ha', hsub_a⟩
  | derefB _ ih =>
      cases hres with
      | deref hu =>
          cases ih hu with
          | intro σa rest =>
              cases rest with
              | intro ha' hsub_a =>
                  exact ⟨σa, LamEff.deref ha', hsub_a⟩

/-- **Region safety is preserved by one step** (§8.3 step 3).

    If every `Λ`-effect of `e` from `σ` has no borrow in `R`, then the same
    holds for the residual `c'.expr` from `σ'`.  This is `LamEff.step_compose`
    composed with `noEscape_of_lamSub`. -/
theorem regionSafeLam_step {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} {R : Rgn} (hsafe : RegionSafeLam σ R e)
    (hstep : EffHStepEvalCK σ c e c' σ' A) :
    RegionSafeLam σ' R c'.expr := by
  intro σ'' hres
  cases LamEff.step_compose hstep hres with
  | intro σ₁ rest =>
      cases rest with
      | intro h₁ hsub =>
          exact noEscape_of_lamSub hsub (hsafe σ₁ h₁)

end LSys
