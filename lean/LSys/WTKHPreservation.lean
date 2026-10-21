/-
  LSys/WTKHPreservation.lean

  Redex-level preservation for route A's `WTKH`.

  Two layers:

  * `WTKH.preserved_redex` — canonical **redex** steps (`RedexK`), including the
    value-dependent `let`/`borrow` steps with their `setEnv` / `bindHolders` /
    `addBorrow` updates.
  * `WTKH.preserved` — the full statement, adding the 14 **context** rules.  The
    stepped sub-expression is handled by the induction hypothesis; the
    continuation (and siblings) move to the extended environment via
    `WTKH.env_ext` (a step only extends `env`, and never changes `heap`); the
    `region` premise is updated by `regionSafeLam_step`.
-/

import LSys.WTKH
import LSys.WTKHEnv
import LSys.RedexK
import LSys.LamStep

namespace LSys

set_option linter.unusedVariables false

/-- Redex-level preservation of `WTKH` (includes `let`/`borrow` bindings). -/
theorem WTKH.preserved_redex :
    ∀ {env : EvalEnv} {heap : EvalHeap} {e : Expr} {σ σ₁ : Sigma}
      {A : List Bid},
      WTKH env heap e σ σ₁ A →
      ∀ {c c' : EvalConf} {σ' : Sigma} {A' : List Bid},
        RedexK σ c e c' σ' A' →
        c.env = env → c.heap = heap →
        WTKH c'.env c'.heap c'.expr σ' σ₁ A := by
  intro env heap e σ σ₁ A hwt
  induction hwt with
  | val =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | val => exact WTKH.val
      | borrowExit => exact WTKH.val
  | var hx' =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | varV hx =>
          rw [hc] at hx
          rw [hx] at hx'
          cases hx'
          exact holdersOfV_toVal _ ▸ WTKH.val
  | abort =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | abort => exact WTKH.abort
      | abortBorrow => exact WTKH.abort
  | op ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | op =>
          cases ha
          cases hb
          exact WTKH.val
      | opAny =>
          cases ha
          cases hb
          exact WTKH.val
  | letE ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | letV _ =>
          cases ha
          rw [hc, hh]
          exact hb _
  | move hp =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | moveV hstepH =>
          rw [hh] at hstepH
          rw [hstepH] at hp
          cases hp
          exact holdersOfV_toVal _ ▸ WTKH.val
  | read hp hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | readV hstepH =>
          rw [hh] at hstepH
          rw [hstepH] at hp
          cases hp
          exact holdersOfV_toVal _ ▸ WTKH.val
  | write he hw ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | write =>
          cases he
          exact WTKH.val
  | seq ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | seqV =>
          cases ha
          rw [hc, hh]
          exact hb
  | region he hsafe hno ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | regionV =>
          cases he
          exact WTKH.val
  | alloc he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | alloc =>
          cases he
          exact WTKH.val
  | freeze hm hl =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | freeze => exact WTKH.val
  | recover he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | recover =>
          cases he
          exact WTKH.val
      | recoverAny hV =>
          cases he
          rw [hV]
          exact WTKH.val
  | borrow hm he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | borrowEnter _ =>
          rw [hc, hh]
          exact he
  | drop hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | drop => exact WTKH.val
  | call ha hcap hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | callV =>
          cases ha
          rw [hc, hh]
          exact hb
  | ret he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | retV =>
          cases he
          exact WTKH.val
  | spawn he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | spawnV =>
          cases he
          exact WTKH.val
  | atomic he hm ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | atomicV =>
          cases he
          exact WTKH.val
  | unsafeE he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | unsafeV =>
          cases he
          exact WTKH.val


/-- `let`-context rule where the continuation is typed under a *smaller*
    environment (`hext : EnvExtends env env'`).  Isolated so that the bound
    variable `x` can be named (it is implicit in the `WTKH.letE` constructor). -/
theorem WTKH.letE_ctx_ext {env env' : EvalEnv} {heap : EvalHeap}
    {x : Var} {a b : Expr} {σ_a σ' σ₁ : Sigma} {A_a A : List Bid}
    (ha' : WTKH env' heap a σ' σ_a A_a)
    (hb : ∀ v : Val,
      WTKH (setEnv env x (ofVal v)) heap b
        (bindHolders σ_a x (Effect.holdersOfV v)) σ₁ A)
    (hext : EnvExtends env env') :
    WTKH env' heap (Expr.letE x a b) σ' σ₁ A :=
  WTKH.letE ha'
    (fun v => WTKH.env_ext (hb v) (EnvExtends.setEnv hext x (ofVal v)))

/-- `WTKH` is insensitive to the concrete `heap`, provided the whole
    derivation is transported along a heap equality (the `heap` only shows up
    in the `move`/`read` premises). -/
theorem WTKH.heap_trans {env : EvalEnv} {heap heap' : EvalHeap} {e : Expr}
    {σ σ' : Sigma} {A : List Bid} (hwt : WTKH env heap e σ σ' A)
    (hh : heap = heap') : WTKH env heap' e σ σ' A :=
  hh ▸ hwt

/-- Combined env + heap transport (a step only extends `env`, and never
    changes `heap`). -/
theorem WTKH.env_heap_trans {env env' : EvalEnv} {heap heap' : EvalHeap}
    {e : Expr} {σ σ' : Sigma} {A : List Bid} (hwt : WTKH env heap e σ σ' A)
    (he : EnvExtends env env') (hh : heap = heap') :
    WTKH env' heap' e σ σ' A :=
  hh ▸ WTKH.env_ext hwt he

/-- **Full preservation for `WTKH`** (§8.3 step 5).

    Redex steps are delegated to `WTKH.preserved_redex`; context steps use the
    induction hypothesis for the stepped sub-expression, transport the
    continuation along `EnvExtends` (`WTKH.env_ext`, since a step only extends
    `env` and never changes `heap`), and update the `region` premise with
    `regionSafeLam_step`. -/
theorem WTKH.preserved :
    ∀ {env : EvalEnv} {heap : EvalHeap} {e : Expr} {σ σ₁ : Sigma} {A : List Bid},
      WTKH env heap e σ σ₁ A →
      ∀ {c c' : EvalConf} {σ' : Sigma} {A' : List Bid},
        EffHStepEvalCK σ c e c' σ' A' → c.env = env → c.heap = heap →
        WTKH c'.env c'.heap c'.expr σ' σ₁ A := by
  intro env heap e σ σ₁ A hwt
  induction hwt with
  | val =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | val => exact WTKH.preserved_redex WTKH.val RedexK.val hc hh
      | borrowExit => exact WTKH.preserved_redex WTKH.val RedexK.borrowExit hc hh
  | var hx' =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | varV hx => exact WTKH.preserved_redex (WTKH.var hx') (RedexK.varV hx) hc hh
  | abort =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | abort => exact WTKH.preserved_redex WTKH.abort RedexK.abort hc hh
      | abortBorrow =>
          exact WTKH.preserved_redex WTKH.abort RedexK.abortBorrow hc hh
  | op ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | op => exact WTKH.preserved_redex (WTKH.op ha hb) RedexK.op hc hh
      | opAny => exact WTKH.preserved_redex (WTKH.op ha hb) RedexK.opAny hc hh
      | opL h =>
          exact WTKH.op (iha h hc hh)
            (WTKH.env_heap_trans hb
              (by
                have h1 := EffHStepEvalCK.env_ext h
                rw [hc] at h1
                exact h1)
              (by
                have h1 := EffHStepEvalCK.heap_same h
                exact hh.symm.trans h1.symm))
      | opR hv h =>
          cases IsVal.exists_val hv with
          | intro v he =>
              subst he
              cases ha
              exact WTKH.op WTKH.val (ihb h hc hh)
  | letE ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | letV hfresh =>
          exact WTKH.preserved_redex (WTKH.letE ha hb) (RedexK.letV hfresh) hc hh
      | letB h =>
          exact WTKH.letE_ctx_ext (iha h hc hh)
            (fun v => WTKH.heap_trans (hb v)
              (by
                have h1 := EffHStepEvalCK.heap_same h
                exact hh.symm.trans h1.symm))
            (by
              have h1 := EffHStepEvalCK.env_ext h
              rw [hc] at h1
              exact h1)
  | move hp =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | moveV h => exact WTKH.preserved_redex (WTKH.move hp) (RedexK.moveV h) hc hh
  | read hp hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | readV h =>
          exact WTKH.preserved_redex (WTKH.read hp hm) (RedexK.readV h) hc hh
  | write he hw ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | write => exact WTKH.preserved_redex (WTKH.write he hw) RedexK.write hc hh
      | writeB h => exact WTKH.write (ihe h hc hh) hw
  | seq ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | seqV => exact WTKH.preserved_redex (WTKH.seq ha hb) RedexK.seqV hc hh
      | seqL h =>
          exact WTKH.seq (iha h hc hh)
            (WTKH.env_heap_trans hb
              (by
                have h1 := EffHStepEvalCK.env_ext h
                rw [hc] at h1
                exact h1)
              (by
                have h1 := EffHStepEvalCK.heap_same h
                exact hh.symm.trans h1.symm))
  | region he hsafe hno ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | regionV => exact WTKH.preserved_redex (WTKH.region he hsafe hno) RedexK.regionV hc hh
      | regionB h =>
          exact WTKH.region (ihe h hc hh) (regionSafeLam_step hsafe h) hno
  | alloc he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | alloc => exact WTKH.preserved_redex (WTKH.alloc he hcap) RedexK.alloc hc hh
      | allocB h => exact WTKH.alloc (ihe h hc hh) hcap
  | freeze hm hl =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | freeze => exact WTKH.preserved_redex (WTKH.freeze hm hl) RedexK.freeze hc hh
  | recover he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | recover => exact WTKH.preserved_redex (WTKH.recover he) RedexK.recover hc hh
      | recoverAny hV =>
          exact WTKH.preserved_redex (WTKH.recover he) (RedexK.recoverAny hV) hc hh
      | recoverB h => exact WTKH.recover (ihe h hc hh)
  | borrow hm he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | borrowEnter hfresh =>
          exact WTKH.preserved_redex (WTKH.borrow hm he) (RedexK.borrowEnter hfresh) hc hh
  | drop hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | drop => exact WTKH.preserved_redex (WTKH.drop hm) RedexK.drop hc hh
  | call ha hcap hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | callV => exact WTKH.preserved_redex (WTKH.call ha hcap hb) RedexK.callV hc hh
      | callB h =>
          exact WTKH.call (iha h hc hh) hcap
            (WTKH.env_heap_trans hb
              (by
                have h1 := EffHStepEvalCK.env_ext h
                rw [hc] at h1
                exact h1)
              (by
                have h1 := EffHStepEvalCK.heap_same h
                exact hh.symm.trans h1.symm))
  | ret he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | retV => exact WTKH.preserved_redex (WTKH.ret he) RedexK.retV hc hh
      | retB h => exact WTKH.ret (ihe h hc hh)
  | spawn he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | spawnV => exact WTKH.preserved_redex (WTKH.spawn he hcap) RedexK.spawnV hc hh
      | spawnB h => exact WTKH.spawn (ihe h hc hh) hcap
  | atomic he hm ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | atomicV => exact WTKH.preserved_redex (WTKH.atomic he hm) RedexK.atomicV hc hh
      | atomicB h => exact WTKH.atomic (ihe h hc hh) hm
  | unsafeE he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | unsafeV => exact WTKH.preserved_redex (WTKH.unsafeE he) RedexK.unsafeV hc hh
      | unsafeB h => exact WTKH.unsafeE (ihe h hc hh)

-- NOTE: `WTKH` has **no** rule for `Expr.derefRaw` (see §8.2 #8: the result
-- handle comes from the runtime heap, which `EvalConf.heap` cannot resolve
-- without an explicit loc→heap link).  Hence there is no `deref` case here,
-- and the `derefV`/`derefAny`/`derefB` steps of `EffHStepEvalCK` are vacuously
-- covered for well-typed terms.

end LSys
