/-
  LSys/WTyHCtx.lean

  Context preservation for `WTyH` and `RegionSafeHC`.

  `CtxCong` is the set of congruence (evaluation-order) contexts: `hole`, the
  prefix-aware contexts of `EffHStepEvalC`, and `opR a c` only when `a` is a
  value.  Only `borrowB` is excluded (its body is entered by the `borrowEnter`
  redex step, not by a congruence step).

  Three results, all over `EffHStepEvalC`:

  * `EffHC.plug_step_compose`: an effect of the residual `plug C e'` can be
    pulled back to an effect of `plug C e`;
  * `RegionSafeHC.plug_preserved`: region safety is preserved in a context;
  * `WTyH.plug_preserved`: typing, final state and handles are preserved.
-/

import LSys.WTyH

namespace LSys

set_option linter.unusedVariables false

/-- Congruence contexts (all `Ctx` constructors except `borrowB`). -/
inductive CtxCong : Ctx → Prop where
  | hole : CtxCong Ctx.hole
  | opL {c : Ctx} {b : Expr} (h : CtxCong c) : CtxCong (Ctx.opL c b)
  | opR {a : Expr} {c : Ctx} (hv : IsVal a) (h : CtxCong c) :
      CtxCong (Ctx.opR a c)
  | letB {x : Var} {c : Ctx} {b : Expr} (h : CtxCong c) :
      CtxCong (Ctx.letB x c b)
  | writeB {p : Place} {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.writeB p c)
  | seqL {c : Ctx} {b : Expr} (h : CtxCong c) : CtxCong (Ctx.seqL c b)
  | allocB {a : Nat} {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.allocB a c)
  | regionB {r : Rgn} {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.regionB r c)
  | recoverB {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.recoverB c)
  | callB {f : Nat} {c : Ctx} {body : Expr} (h : CtxCong c) :
      CtxCong (Ctx.callB f c body)
  | retB {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.retB c)
  | spawnB {f : Nat} {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.spawnB f c)
  | atomicB {p : Place} {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.atomicB p c)
  | unsafeB {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.unsafeB c)
  | derefB {c : Ctx} (h : CtxCong c) : CtxCong (Ctx.derefB c)

/-- Pull an effect of the residual `plug C c'.expr` back to the original
    `plug C e`, along a step `e → c'.expr`. -/
theorem EffHC.plug_step_compose :
    ∀ {C : Ctx}, CtxCong C →
      ∀ {e : Expr} {σ σ' : Sigma} {A' : List Bid} {c c' : EvalConf},
        EffHStepEvalC σ c e c' σ' A' →
        ∀ {σ'' : Sigma} {B : List Bid},
          EffHC c.env c.heap (plug C c'.expr) σ' σ'' B →
          EffHC c.env c.heap (plug C e) σ σ'' B := by
  intro C hC
  induction hC with
  | hole =>
      intro e σ σ' A' c c' hstep σ'' B hres
      exact effHStepEvalC_effHC_compose hstep σ'' B hres
  | opL hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | op h1 h2 => exact EffHC.op (ih hstep h1) h2
  | opR hv hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | op h1 h2 =>
          cases Effect.isVal_eq hv with
          | intro v hv' =>
              cases hv'
              cases h1
              exact EffHC.op (EffHC.val) (ih hstep h2)
  | letB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | letE h1 h2 => exact EffHC.letE (ih hstep h1) h2
  | writeB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | write h1 => exact EffHC.write (ih hstep h1)
  | seqL hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | seq h1 h2 => exact EffHC.seq (ih hstep h1) h2
  | allocB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | alloc h1 => exact EffHC.alloc (ih hstep h1)
  | regionB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | region h1 => exact EffHC.region (ih hstep h1)
  | recoverB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | recover h1 => exact EffHC.recover (ih hstep h1)
  | callB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | call h1 h2 => exact EffHC.call (ih hstep h1) h2
  | retB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | ret h1 => exact EffHC.ret (ih hstep h1)
  | spawnB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | spawn h1 => exact EffHC.spawn (ih hstep h1)
  | atomicB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | atomic h1 => exact EffHC.atomic (ih hstep h1)
  | unsafeB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | unsafeE h1 => exact EffHC.unsafeE (ih hstep h1)
  | derefB hc ih =>
      intro e σ σ' A' c c' hstep σ'' B hres
      cases hres with
      | deref h1 => exact EffHC.deref (ih hstep h1)

/-- `RegionSafeHC` is preserved by a child step inside a congruence context. -/
theorem RegionSafeHC.plug_preserved {C : Ctx} (hC : CtxCong C)
    {env : EvalEnv} {heap : EvalHeap} {R : Rgn}
    {e : Expr} {σ σ' : Sigma} {A : List Bid} {c c' : EvalConf}
    (hstep : EffHStepEvalC σ c e c' σ' A)
    (henv : c.env = env) (hheap : c.heap = heap)
    (hsafe : RegionSafeHC env heap σ R (plug C e)) :
    RegionSafeHC env heap σ' R (plug C c'.expr) := by
  intro σ'' B hres
  have hres1 : EffHC c.env c.heap (plug C c'.expr) σ' σ'' B :=
    EffHC.env_heap_congr henv.symm hheap.symm hres
  have hcomp : EffHC c.env c.heap (plug C e) σ σ'' B :=
    EffHC.plug_step_compose hC hstep hres1
  exact hsafe σ'' B (EffHC.env_heap_congr henv hheap hcomp)

/-- A child step inside a congruence context preserves `WTyH`, the final
    state and the result handles. -/
theorem WTyH.plug_preserved :
    ∀ {C : Ctx}, CtxCong C →
      ∀ {e : Expr} {σ σ₁ σ' : Sigma} {A A' : List Bid}
        {c c' : EvalConf},
        EffHStepEvalC σ c e c' σ' A' →
        WTyH c.env c.heap (plug C e) σ σ₁ A →
        WTyH c'.env c'.heap (plug C c'.expr) σ' σ₁ A := by
  intro C hC
  induction hC with
  | hole =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      exact WTyH.preserved e hwt hstep rfl rfl
  | opL hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | op ha hb =>
          exact WTyH.op (ih hstep ha)
            (WTyH.env_heap_congr (EffHStepEvalC.env_heap hstep).1.symm
              (EffHStepEvalC.env_heap hstep).2.symm hb)
  | opR hv hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | op ha hb =>
          cases Effect.isVal_eq hv with
          | intro v hv' =>
              cases hv'
              cases ha
              exact WTyH.op (WTyH.val) (ih hstep hb)
  | letB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | letE ha hb =>
          exact WTyH.letE (ih hstep ha)
            (WTyH.env_heap_congr (EffHStepEvalC.env_heap hstep).1.symm
              (EffHStepEvalC.env_heap hstep).2.symm hb)
  | writeB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | write he hw => exact WTyH.write (ih hstep he) hw
  | seqL hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | seq ha hb =>
          exact WTyH.seq (ih hstep ha)
            (WTyH.env_heap_congr (EffHStepEvalC.env_heap hstep).1.symm
              (EffHStepEvalC.env_heap hstep).2.symm hb)
  | allocB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | alloc he hcap => exact WTyH.alloc (ih hstep he) hcap
  | regionB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | region he hsafe hno =>
          exact WTyH.region (ih hstep he)
            (RegionSafeHC.plug_preserved hc hstep
              (EffHStepEvalC.env_heap hstep).1.symm
              (EffHStepEvalC.env_heap hstep).2.symm
              (RegionSafeHC.env_heap_congr
                (env₁ := c.env) (heap₁ := c.heap)
                (env₂ := c'.env) (heap₂ := c'.heap)
                (EffHStepEvalC.env_heap hstep).1.symm
                (EffHStepEvalC.env_heap hstep).2.symm hsafe)) hno
  | recoverB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | recover he => exact WTyH.recover (ih hstep he)
  | callB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | call ha hcap hb =>
          exact WTyH.call (ih hstep ha) hcap
            (WTyH.env_heap_congr (EffHStepEvalC.env_heap hstep).1.symm
              (EffHStepEvalC.env_heap hstep).2.symm hb)
  | retB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | ret he => exact WTyH.ret (ih hstep he)
  | spawnB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | spawn he hcap => exact WTyH.spawn (ih hstep he) hcap
  | atomicB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | atomic he hm => exact WTyH.atomic (ih hstep he) hm
  | unsafeB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt with
      | unsafeE he => exact WTyH.unsafeE (ih hstep he)
  | derefB hc ih =>
      intro e σ σ₁ σ' A A' c c' hstep hwt
      cases hwt

end LSys
