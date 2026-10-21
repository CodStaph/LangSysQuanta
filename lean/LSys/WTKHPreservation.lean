/-
  LSys/WTKHPreservation.lean

  Preservation for route A's outcome-typed `WTKH`.

  Because the typing carries an `Outcome` (`ok σ' A` or `aborts σ`), a step
  **does not change the outcome**: it only threads the intermediate states.
  The preservation statement is therefore simply

    `WTKH env heap e σ o → e ⇝ c'.expr → WTKH c'.env c'.heap c'.expr σ' o`

  with the *same* `o`.  This is what makes abort propagation typable in every
  congruence context: for `op (abort k) b` the typing is `aborts σ` (the
  aborting prefix swallows the continuation), and so is the typing of `abort k`.

  Two layers:

  * `WTKH.preserved_redex` — canonical **redex** steps (`RedexK`);
  * `WTKH.preserved` — the full `EffHStepEvalCK`, adding the congruence
    contexts (the stepped sub-expression uses the induction hypothesis; the
    continuation moves along `EnvExtends`/heap equality via `env_heap_trans`)
    and all 14 abort rules.
-/

import LSys.WTKH
import LSys.WTKHEnv
import LSys.RedexK
import LSys.LamStep

namespace LSys

set_option linter.unusedVariables false

/-! ## Transport helpers -/

/-- A step only extends the environment; with `c.env = env` this gives the
    extension from `env`. -/
theorem EffHStepEvalCK.env_ext' {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (h : EffHStepEvalCK σ c e c' σ' A) {env : EvalEnv}
    (hc : c.env = env) : EnvExtends env c'.env :=
  hc ▸ EffHStepEvalCK.env_ext h

/-- A step never changes the heap; with `c.heap = heap` this gives the
    equality from `heap` to the post-configuration. -/
theorem EffHStepEvalCK.heap_same' {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (h : EffHStepEvalCK σ c e c' σ' A) {heap : EvalHeap}
    (hh : c.heap = heap) : heap = c'.heap :=
  hh.symm.trans (EffHStepEvalCK.heap_same h).symm

/-- `WTKH` is insensitive to the concrete heap, provided the whole derivation is
    transported along a heap equality (the `heap` only shows up in the
    `move`/`read`/`deref` premises). -/
theorem WTKH.heap_trans {env : EvalEnv} {heap heap' : EvalHeap} {e : Expr}
    {σ : Sigma} {o : Outcome} (hwt : WTKH env heap e σ o) (hh : heap = heap') :
    WTKH env heap' e σ o :=
  hh ▸ hwt

/-- Combined environment + heap transport. -/
theorem WTKH.env_heap_trans {env env' : EvalEnv} {heap heap' : EvalHeap}
    {e : Expr} {σ : Sigma} {o : Outcome} (hwt : WTKH env heap e σ o)
    (he : EnvExtends env env') (hh : heap = heap') :
    WTKH env' heap' e σ o :=
  hh ▸ WTKH.env_ext hwt he

/-- `let`-context rule where the continuation is typed under a *smaller*
    environment (`hext : EnvExtends env env'`).  Isolated so that the bound
    variable `x` can be named (it is implicit in the `WTKH.letOk` constructor). -/
theorem WTKH.letE_ctx_ext {env env' : EvalEnv} {heap : EvalHeap}
    {x : Var} {a b : Expr} {σa σ' : Sigma} {Aa : List Bid} {Ob : Outcome}
    (ha' : WTKH env' heap a σ' (.ok σa Aa))
    (hb : ∀ v : Val,
      WTKH (setEnv env x (ofVal v)) heap b
        (bindHolders σa x (Effect.holdersOfV v)) Ob)
    (hext : EnvExtends env env') :
    WTKH env' heap (Expr.letE x a b) σ' Ob :=
  WTKH.letOk ha'
    (fun v => WTKH.env_ext (hb v) (EnvExtends.setEnv hext x (ofVal v)))

/-! ## Redex-level preservation -/

/-- Redex-level preservation of `WTKH`: the outcome is unchanged. -/
theorem WTKH.preserved_redex :
    ∀ {env : EvalEnv} {heap : EvalHeap} {e : Expr} {σ : Sigma} {o : Outcome},
      WTKH env heap e σ o →
      ∀ {c c' : EvalConf} {σ' : Sigma} {A' : List Bid},
        RedexK σ c e c' σ' A' → c.env = env → c.heap = heap →
        WTKH c'.env c'.heap c'.expr σ' o := by
  intro env heap e σ o hwt
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
  | opOk ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | op => cases ha; cases hb; exact WTKH.val
      | opAny => cases ha; cases hb; exact WTKH.val
  | opAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | op => cases ha
      | opAny => cases ha
  | letOk ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | letV _ =>
          cases ha
          exact WTKH.env_heap_trans (hb _)
            (EnvExtends.setEnv (by intro y w hy; rw [hc]; exact hy) _ (ofVal _))
            hh.symm
  | letAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | letV _ => cases ha
  | move hp =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | moveV h =>
          rw [hh] at h
          rw [h] at hp
          cases hp
          exact holdersOfV_toVal _ ▸ WTKH.val
  | read hp hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | readV h =>
          rw [hh] at h
          rw [h] at hp
          cases hp
          exact holdersOfV_toVal _ ▸ WTKH.val
  | writeOk he hw ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | write => cases he; exact WTKH.val
  | writeAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | write => cases he
  | seqOk ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | seqV =>
          cases ha
          exact WTKH.env_heap_trans hb
            (by intro y w hy; rw [hc]; exact hy) hh.symm
  | seqAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | seqV => cases ha
  | regionOk he hsafe hno ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | regionV => cases he; exact WTKH.val
  | regionAborts he hsafe ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | regionV => cases he
  | allocOk he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | alloc => cases he; exact WTKH.val
  | allocAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | alloc => cases he
  | freeze hm hl =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | freeze => exact WTKH.val
  | recoverOk he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | recover => cases he; exact WTKH.val
      | recoverAny hV => cases he; rw [hV]; exact WTKH.val
  | recoverAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | recover => cases he
      | recoverAny _ => cases he
  | borrow hm he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | borrowEnter _ =>
          exact WTKH.env_heap_trans he
            (EnvExtends.setEnv (by intro y w hy; rw [hc]; exact hy) _ (RVal.refH 0))
            hh.symm
  | drop hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | drop => exact WTKH.val
  | callOk ha hcap hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | callV =>
          cases ha
          exact WTKH.env_heap_trans hb
            (by intro y w hy; rw [hc]; exact hy) hh.symm
  | callAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | callV => cases ha
  | ret he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | retV => cases he; exact WTKH.val
  | spawnOk he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | spawnV => cases he; exact WTKH.val
  | spawnAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | spawnV => cases he
  | atomicOk he hm ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | atomicV => cases he; exact WTKH.val
  | atomicAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | atomicV => cases he
  | unsafeE he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | unsafeV => cases he; exact WTKH.val
  | deref hp =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | derefV h =>
          rw [hh] at h
          rw [h] at hp
          cases hp
          exact holdersOfV_toVal _ ▸ WTKH.val
      | derefAny hv => exact False.elim (hv _ rfl)

/-! ## Full preservation -/

/-- **Preservation for `WTKH`**: every configuration step preserves typing, and
    the outcome is invariant. -/
theorem WTKH.preserved :
    ∀ {env : EvalEnv} {heap : EvalHeap} {e : Expr} {σ : Sigma} {o : Outcome},
      WTKH env heap e σ o →
      ∀ {c c' : EvalConf} {σ' : Sigma} {A' : List Bid},
        EffHStepEvalCK σ c e c' σ' A' → c.env = env → c.heap = heap →
        WTKH c'.env c'.heap c'.expr σ' o := by
  intro env heap e σ o hwt
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
  | opOk ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | op => exact WTKH.preserved_redex (WTKH.opOk ha hb) RedexK.op hc hh
      | opAny => exact WTKH.preserved_redex (WTKH.opOk ha hb) RedexK.opAny hc hh
      | opL h =>
          exact WTKH.opOk (iha h hc hh)
            (WTKH.env_heap_trans hb (EffHStepEvalCK.env_ext' h hc)
              (EffHStepEvalCK.heap_same' h hh))
      | opR hv h =>
          cases IsVal.exists_val hv with
          | intro v he =>
              subst he
              cases ha
              exact WTKH.opOk WTKH.val (ihb h hc hh)
      | abortOpL => cases ha
      | abortOpR hv =>
          cases IsVal.exists_val hv with
          | intro v he =>
              subst he
              cases ha
              cases hb
              exact WTKH.abort
  | opAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | op => cases ha
      | opAny => cases ha
      | opL h => exact WTKH.opAborts (iha h hc hh)
      | opR hv _ =>
          cases IsVal.exists_val hv with
          | intro v he => subst he; cases ha
      | abortOpL => cases ha; exact WTKH.abort
      | abortOpR hv =>
          cases IsVal.exists_val hv with
          | intro v he => subst he; cases ha
  | letOk ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | letV hfresh =>
          exact WTKH.preserved_redex (WTKH.letOk ha hb) (RedexK.letV hfresh) hc hh
      | letB h =>
          exact WTKH.letE_ctx_ext (iha h hc hh)
            (fun v => WTKH.heap_trans (hb v) (EffHStepEvalCK.heap_same' h hh))
            (EffHStepEvalCK.env_ext' h hc)
      | abortLetB => cases ha
  | letAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | letV _ => cases ha
      | letB h => exact WTKH.letAborts (iha h hc hh)
      | abortLetB => cases ha; exact WTKH.abort
  | move hp =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | moveV h => exact WTKH.preserved_redex (WTKH.move hp) (RedexK.moveV h) hc hh
  | read hp hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | readV h =>
          exact WTKH.preserved_redex (WTKH.read hp hm) (RedexK.readV h) hc hh
  | writeOk he hw ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | write => exact WTKH.preserved_redex (WTKH.writeOk he hw) RedexK.write hc hh
      | writeB h => exact WTKH.writeOk (ihe h hc hh) hw
      | abortWriteB => cases he
  | writeAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | write => cases he
      | writeB h => exact WTKH.writeAborts (ihe h hc hh)
      | abortWriteB => cases he; exact WTKH.abort
  | seqOk ha hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | seqV => exact WTKH.preserved_redex (WTKH.seqOk ha hb) RedexK.seqV hc hh
      | seqL h =>
          exact WTKH.seqOk (iha h hc hh)
            (WTKH.env_heap_trans hb (EffHStepEvalCK.env_ext' h hc)
              (EffHStepEvalCK.heap_same' h hh))
      | abortSeqL => cases ha
  | seqAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | seqV => cases ha
      | seqL h => exact WTKH.seqAborts (iha h hc hh)
      | abortSeqL => cases ha; exact WTKH.abort
  | regionOk he hsafe hno ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | regionV =>
          exact WTKH.preserved_redex (WTKH.regionOk he hsafe hno) RedexK.regionV hc hh
      | regionB h =>
          exact WTKH.regionOk (ihe h hc hh) (regionSafeLam_step hsafe h) hno
      | abortRegion => cases he
  | regionAborts he hsafe ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | regionV => cases he
      | regionB h =>
          exact WTKH.regionAborts (ihe h hc hh) (regionSafeLam_step hsafe h)
      | abortRegion => cases he; exact WTKH.abort
  | allocOk he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | alloc => exact WTKH.preserved_redex (WTKH.allocOk he hcap) RedexK.alloc hc hh
      | allocB h => exact WTKH.allocOk (ihe h hc hh) hcap
      | abortAlloc => cases he
  | allocAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | alloc => cases he
      | allocB h => exact WTKH.allocAborts (ihe h hc hh)
      | abortAlloc => cases he; exact WTKH.abort
  | freeze hm hl =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | freeze => exact WTKH.preserved_redex (WTKH.freeze hm hl) RedexK.freeze hc hh
  | recoverOk he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | recover => exact WTKH.preserved_redex (WTKH.recoverOk he) RedexK.recover hc hh
      | recoverAny hV =>
          exact WTKH.preserved_redex (WTKH.recoverOk he) (RedexK.recoverAny hV) hc hh
      | recoverB h => exact WTKH.recoverOk (ihe h hc hh)
      | abortRecoverB => cases he
  | recoverAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | recover => cases he
      | recoverAny _ => cases he
      | recoverB h => exact WTKH.recoverAborts (ihe h hc hh)
      | abortRecoverB => cases he; exact WTKH.abort
  | borrow hm he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | borrowEnter hfresh =>
          exact WTKH.preserved_redex (WTKH.borrow hm he) (RedexK.borrowEnter hfresh) hc hh
  | drop hm =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | drop => exact WTKH.preserved_redex (WTKH.drop hm) RedexK.drop hc hh
  | callOk ha hcap hb iha ihb =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | callV => exact WTKH.preserved_redex (WTKH.callOk ha hcap hb) RedexK.callV hc hh
      | callB h =>
          exact WTKH.callOk (iha h hc hh) hcap
            (WTKH.env_heap_trans hb (EffHStepEvalCK.env_ext' h hc)
              (EffHStepEvalCK.heap_same' h hh))
      | abortCallB => cases ha
  | callAborts ha iha =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | callV => cases ha
      | callB h => exact WTKH.callAborts (iha h hc hh)
      | abortCallB => cases ha; exact WTKH.abort
  | ret he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | retV => exact WTKH.preserved_redex (WTKH.ret he) RedexK.retV hc hh
      | retB h => exact WTKH.ret (ihe h hc hh)
      | abortRet => cases he; exact WTKH.abort
  | spawnOk he hcap ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | spawnV => exact WTKH.preserved_redex (WTKH.spawnOk he hcap) RedexK.spawnV hc hh
      | spawnB h => exact WTKH.spawnOk (ihe h hc hh) hcap
      | abortSpawn => cases he
  | spawnAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | spawnV => cases he
      | spawnB h => exact WTKH.spawnAborts (ihe h hc hh)
      | abortSpawn => cases he; exact WTKH.abort
  | atomicOk he hm ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | atomicV => exact WTKH.preserved_redex (WTKH.atomicOk he hm) RedexK.atomicV hc hh
      | atomicB h => exact WTKH.atomicOk (ihe h hc hh) hm
      | abortAtomic => cases he
  | atomicAborts he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | atomicV => cases he
      | atomicB h => exact WTKH.atomicAborts (ihe h hc hh)
      | abortAtomic => cases he; exact WTKH.abort
  | unsafeE he ihe =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | unsafeV => exact WTKH.preserved_redex (WTKH.unsafeE he) RedexK.unsafeV hc hh
      | unsafeB h => exact WTKH.unsafeE (ihe h hc hh)
      | abortUnsafe => cases he; exact WTKH.abort
  | deref hp =>
      intro c c' σ' A' hstep hc hh
      cases hstep with
      | derefV h =>
          exact WTKH.preserved_redex (WTKH.deref hp) (RedexK.derefV h) hc hh
      | derefAny hv =>
          exact WTKH.preserved_redex (WTKH.deref hp) (RedexK.derefAny hv) hc hh
      | derefB h =>
          have hE := EffHStepEvalCK.env_ext h
          rw [hc] at hE
          have hH := EffHStepEvalCK.heap_same h
          rw [hh] at hH
          cases EffHStepEvalCK.val_step h with
          | intro hexpr hσ =>
              subst hσ
              rw [hexpr]
              exact WTKH.env_heap_trans (WTKH.deref hp) hE hH.symm

end LSys
