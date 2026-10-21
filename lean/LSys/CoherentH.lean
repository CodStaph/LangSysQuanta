/-
  LSys/CoherentH.lean

  A handle-aware, prefix-aware replacement for the `sctx` rule.

  `Coherent.StepPM` is built on the raw, total `Step` relation, so its
  context rule needs the post-typing premise `hwt_out : WT σ' (plug C e')`.
  The naive bridge from raw `Step` to `EffHStepEvalC` is false
  (`StepBridge.not_match_step_naive`), and `WTyH` conditions live at the
  firing state, so `WTyH` cannot be projected to the input-only `WT`.

  `StepPMH` therefore takes the **configuration-level** step as its source:
  a matched `ConfE` (`MatchUS`), the value alignment `MatchV`, the runtime step
  `RStepE`, and the post matches.  The expression step is
  `EffHStepEvalC σ c e c' σ' A'`, which already resolves values from
  `env`/`heap`.

  Consequences (`StepPMH.wt`, `StepPMH.wt_ctx`): the post typing is *derived*
  from the pre-typing by `WTyH.preserved` / `WTyH.plug_preserved`, so no
  `hwt_out` premise is needed.  The remaining work is to connect this relation
  to the runtime semantics (value-consistent `StepPM` rules and the
  `let`/`borrow` environment updates), tracked in `MEMORY.md` §8.3.
-/

import LSys.StepBridge
import LSys.WTyHStar

namespace LSys

set_option linter.unusedVariables false

/-- Handle-aware, prefix-aware step coupled with the runtime configuration. -/
structure StepPMH (A' : List Bid) (σ : Sigma) (c : EvalConf) (e : Expr)
    (ce : ConfE) (s : State) (σ' : Sigma) (c' : EvalConf) (ce' : ConfE)
    (s' : State) : Prop where
  hstep : EffHStepEvalC σ c e c' σ' A'
  match_pre : MatchUS σ ce s
  value_pre : MatchV ce c.env c.heap
  rstep : RStepE ce ce'
  match_post : MatchUS σ' ce' s'
  value_post : MatchV ce' c'.env c'.heap

/-- Pure expression steps (no runtime change) use the identity runtime step. -/
theorem StepPMH.ofStepRefl {A' : List Bid} {σ : Sigma} {c : EvalConf}
    {e : Expr} {c' : EvalConf} {σ' : Sigma} {ce : ConfE} {s : State}
    (hstep : EffHStepEvalC σ c e c' σ' A')
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hm' : MatchUS σ' ce s) (hmv' : MatchV ce c'.env c'.heap) :
    StepPMH A' σ c e ce s σ' c' ce s :=
  ⟨hstep, hm, hmv, RStepE.refl, hm', hmv'⟩

/-- Post `WTyH` at the hole: derived, no `hwt_out`. -/
theorem StepPMH.wt {A' : List Bid} {σ : Sigma} {c : EvalConf} {e : Expr}
    {ce : ConfE} {s : State} {σ' : Sigma} {c' : EvalConf} {ce' : ConfE}
    {s' : State} (h : StepPMH A' σ c e ce s σ' c' ce' s')
    {σ₁ : Sigma} {A : List Bid}
    (hwt : WTyH c.env c.heap e σ σ₁ A) :
    WTyH c'.env c'.heap c'.expr σ' σ₁ A :=
  WTyH.preserved e hwt h.hstep rfl rfl

/-- Post `WTyH` for a congruence context: derived, no `hwt_out`. -/
theorem StepPMH.wt_ctx {C : Ctx} (hC : CtxCong C)
    {σ : Sigma} {c : EvalConf} {e : Expr} {ce : ConfE} {s : State}
    {σ' : Sigma} {c' : EvalConf} {ce' : ConfE} {s' : State}
    {A' : List Bid} (h : StepPMH A' σ c e ce s σ' c' ce' s')
    {σ₁ : Sigma} {A : List Bid}
    (hwt : WTyH c.env c.heap (plug C e) σ σ₁ A) :
    WTyH c'.env c'.heap (plug C c'.expr) σ' σ₁ A :=
  WTyH.plug_preserved hC h.hstep hwt

/-- Multi-step version for a congruence context. -/
theorem StepPMH.wt_ctx_star {C : Ctx} (hC : CtxCong C)
    {σ : Sigma} {c : EvalConf} {e : Expr} {σ' : Sigma} {c' : EvalConf}
    {e' : Expr} {σ₁ : Sigma} {A : List Bid}
    (hstar : EffStepStar σ c e σ' c' e')
    (hwt : WTyH c.env c.heap (plug C e) σ σ₁ A) :
    WTyH c'.env c'.heap (plug C e') σ' σ₁ A :=
  WTyH.plug_star_preserved hC hstar hwt

/-- `borrow` entry: the expression step pushes a borrow frame, paired with the
    runtime `borrowPush` step.  The post `MatchUS` is a premise (as in
    `StepPMH`); `MatchV` is transported because only `flight` changes. -/
theorem StepPMH.borrowEnter {σ : Sigma} {c : EvalConf} {p : Place} {x : Var}
    {e : Expr} {ce : ConfE} {s : State} {b : Bid}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hm' : MatchUS (addBorrow σ 0 p Mode.mut)
      { ce with flight := b :: ce.flight } (State.mk (s.borrow + 1))) :
    StepPMH [] σ c (Expr.borrow p x e) ce s
      (addBorrow σ 0 p Mode.mut)
      { c with expr := e, state := State.mk (c.state.borrow + 1) }
      { ce with flight := b :: ce.flight } (State.mk (s.borrow + 1)) :=
  ⟨EffHStepEvalC.borrowEnter, hm, hmv, RStepE.borrowPush, hm',
    ⟨hmv.env_sub, by rw [evalHeapOfConf_push]; exact hmv.heap_eq⟩⟩

/-- `borrow` frame exit: the expression pops a borrow frame, paired with the
    runtime `borrowPop` step.  The post `MatchUS` is derived by
    `MatchUS.borrowPop`. -/
theorem StepPMH.borrowExit {σ : Sigma} {c : EvalConf} {v : Val} {n : Nat}
    {ce : ConfE} {b : Bid}
    (hm : MatchUS σ { ce with flight := b :: ce.flight } (State.mk (n + 1)))
    (hmv : MatchV { ce with flight := b :: ce.flight } c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.val v, state := State.mk (n + 1) }
      (Expr.val v) { ce with flight := b :: ce.flight } (State.mk (n + 1))
      σ { c with expr := Expr.val v, state := State.mk n } ce (State.mk n) :=
  ⟨EffHStepEvalC.borrowExit, hm, hmv, RStepE.borrowPop, MatchUS.borrowPop hm,
    ⟨hmv.env_sub, by rw [← evalHeapOfConf_push]; exact hmv.heap_eq⟩⟩

/-- `abort` frame exit: the abort pops a borrow frame, paired with the runtime
    `borrowPop` step. -/
theorem StepPMH.abortBorrow {σ : Sigma} {c : EvalConf} {k : Nat} {n : Nat}
    {ce : ConfE} {b : Bid}
    (hm : MatchUS σ { ce with flight := b :: ce.flight } (State.mk (n + 1)))
    (hmv : MatchV { ce with flight := b :: ce.flight } c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.abort k, state := State.mk (n + 1) }
      (Expr.abort k) { ce with flight := b :: ce.flight } (State.mk (n + 1))
      σ { c with expr := Expr.abort k, state := State.mk n } ce (State.mk n) :=
  ⟨EffHStepEvalC.abortBorrow, hm, hmv, RStepE.borrowPop, MatchUS.borrowPop hm,
    ⟨hmv.env_sub, by rw [← evalHeapOfConf_push]; exact hmv.heap_eq⟩⟩

/-- Value-consistent `var` step: the residual value is the one bound in `env`;
    the runtime configuration is unchanged (`RStepE.refl`), and both post
    matches coincide with the pre matches. -/
theorem StepPMH.varV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {x : Var} {v : RVal} (hm : MatchUS σ ce s)
    (hmv : MatchV ce c.env c.heap) (h : c.env x = some v) :
    StepPMH (holdersOfR v) σ { c with expr := Expr.var x } (Expr.var x) ce s
      σ (withExpr c (Expr.val (toVal v))) ce s :=
  ⟨EffHStepEvalC.varV h, hm, hmv, RStepE.refl, hm, hmv⟩

/-- Value-consistent `move` step (lookup premise); the runtime step and post
    matches are premises because `move` changes `Σ` (and possibly the heap). -/
theorem StepPMH.moveV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {p : Place} {v : RVal}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (h : c.heap p = some v)
    (hr : RStepE ce ce') (hm' : MatchUS (clearPlace σ p) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (toVal v))) :
    StepPMH (holdersOfR v) σ { c with expr := Expr.move p } (Expr.move p) ce s
      (clearPlace σ p) c' ce' s' := by
  subst hexpr
  exact ⟨EffHStepEvalC.moveV h, hm, hmv, hr, hm', hmv'⟩

/-- Value-consistent `read` step (lookup premise). -/
theorem StepPMH.readV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {p : Place} {v : RVal}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (h : c.heap p = some v)
    (hr : RStepE ce ce')
    (hm' : MatchUS (addBorrow σ (freshBid σ) p Mode.frozen) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (toVal v))) :
    StepPMH (holdersOfR v) σ { c with expr := Expr.read p } (Expr.read p) ce s
      (addBorrow σ (freshBid σ) p Mode.frozen) c' ce' s' := by
  subst hexpr
  exact ⟨EffHStepEvalC.readV h, hm, hmv, hr, hm', hmv'⟩

/-- Multi-step closure of `StepPMH`, carrying the runtime configuration/state. -/
inductive StepPMHStar :
    Sigma → EvalConf → Expr → ConfE → State →
    Sigma → EvalConf → Expr → ConfE → State → Prop where
  | refl {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State} :
      StepPMHStar σ c c.expr ce s σ c c.expr ce s
  | step {σ : Sigma} {c : EvalConf} {e : Expr} {ce : ConfE} {s : State}
      {σ' : Sigma} {c' : EvalConf} {ce' : ConfE} {s' : State}
      {A' : List Bid} (h : StepPMH A' σ c e ce s σ' c' ce' s')
      {σ'' : Sigma} {c'' : EvalConf} {e'' : Expr} {ce'' : ConfE} {s'' : State}
      (rest : StepPMHStar σ' c' c'.expr ce' s' σ'' c'' e'' ce'' s'') :
      StepPMHStar σ c e ce s σ'' c'' e'' ce'' s''

/-- Projection of the runtime-coupled star to the expression-level star. -/
theorem StepPMHStar.toEffStepStar {σ : Sigma} {c : EvalConf} {e : Expr}
    {ce : ConfE} {s : State} {σ' : Sigma} {c' : EvalConf} {e' : Expr}
    {ce' : ConfE} {s' : State}
    (h : StepPMHStar σ c e ce s σ' c' e' ce' s') :
    EffStepStar σ c e σ' c' e' := by
  induction h with
  | refl => exact EffStepStar.refl
  | step hstep _ ih => exact EffStepStar.step hstep.hstep ih

/-- `WTyH` is preserved along any number of runtime-coupled steps. -/
theorem WTyH.preserved_stepPMH_star :
    ∀ {σ σ₁ : Sigma} {A : List Bid} {e : Expr} {c : EvalConf}
      {ce : ConfE} {s : State},
      WTyH c.env c.heap e σ σ₁ A →
      ∀ {σ' : Sigma} {c' : EvalConf} {e' : Expr} {ce' : ConfE} {s' : State},
        StepPMHStar σ c e ce s σ' c' e' ce' s' →
        WTyH c'.env c'.heap e' σ' σ₁ A := by
  intro σ σ₁ A e c ce s hwt σ' c' e' ce' s' hstar
  induction hstar with
  | refl => exact hwt
  | step h _ ih => exact ih (StepPMH.wt h hwt)

/-- Whole-run preservation in a congruence context (no `hwt_out`). -/
theorem StepPMHStar.wt_ctx {C : Ctx} (hC : CtxCong C)
    {σ σ₁ : Sigma} {A : List Bid} {e : Expr} {c : EvalConf} {ce : ConfE}
    {s : State} {σ' : Sigma} {c' : EvalConf} {e' : Expr} {ce' : ConfE}
    {s' : State}
    (hstar : StepPMHStar σ c e ce s σ' c' e' ce' s')
    (hwt : WTyH c.env c.heap (plug C e) σ σ₁ A) :
    WTyH c'.env c'.heap (plug C e') σ' σ₁ A :=
  WTyH.plug_star_preserved hC (StepPMHStar.toEffStepStar hstar) hwt

/-- `let` binding of a **non-handle** value: the expression step leaves `Σ`
    unchanged, the runtime `letVar` grows the environment, and `MatchUS.letVar`
    / `MatchV.letVar` keep the alignment. -/
theorem StepPMH.letV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {x : Var} {v : Val} {b : Expr}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hfresh : ce.env x = none) (hfreshH : ce.envHolds x = none)
    (hV : holdersOfVal (ofVal v) = []) :
    StepPMH [] σ { c with expr := Expr.letE x (Expr.val v) b }
      (Expr.letE x (Expr.val v) b) ce s
      σ (withExpr c b) (letVar ce x (ofVal v)) s :=
  ⟨EffHStepEvalC.letV, hm, hmv, RStepE.letVar hfresh,
    MatchUS.letVar hm hfreshH hV, MatchV.letVar hmv hfresh⟩

/-- Generic migrated redex: any `EffHStepEvalC` rule together with the runtime
    step and post matches (the shape of the old `Coherent.StepPM` constructors).
    Pure expression steps instantiate `hr := RStepE.refl` and `hm' := hm`. -/
theorem StepPMH.redex {A' : List Bid} {σ : Sigma} {c : EvalConf} {e : Expr}
    {c' : EvalConf} {σ' : Sigma} {ce : ConfE} {s : State} {ce' : ConfE}
    {s' : State} (hstep : EffHStepEvalC σ c e c' σ' A')
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce') (hm' : MatchUS σ' ce' s')
    (hmv' : MatchV ce' c'.env c'.heap) :
    StepPMH A' σ c e ce s σ' c' ce' s' :=
  ⟨hstep, hm, hmv, hr, hm', hmv'⟩

theorem StepPMH.op {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {a b : Nat} (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ
      { c with expr := Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)) }
      (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b))) ce s
      σ (withExpr c (Expr.val (Val.nat (a + b)))) ce s :=
  ⟨EffHStepEvalC.op, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.opAny {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {v w : Val} (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.op (Expr.val v) (Expr.val w) }
      (Expr.op (Expr.val v) (Expr.val w)) ce s
      σ (withExpr c (Expr.val (Val.nat 0))) ce s :=
  ⟨EffHStepEvalC.opAny, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.seqV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {v : Val} {b : Expr} (hm : MatchUS σ ce s)
    (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.seq (Expr.val v) b }
      (Expr.seq (Expr.val v) b) ce s σ (withExpr c b) ce s :=
  ⟨EffHStepEvalC.seqV, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.callV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {f : Nat} {v : Val} {body : Expr} (hm : MatchUS σ ce s)
    (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.call f (Expr.val v) body }
      (Expr.call f (Expr.val v) body) ce s σ (withExpr c body) ce s :=
  ⟨EffHStepEvalC.callV, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.retV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {v : Val} (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.ret (Expr.val v) }
      (Expr.ret (Expr.val v)) ce s σ (withExpr c (Expr.val v)) ce s :=
  ⟨EffHStepEvalC.retV, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.spawnV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {f : Nat} {v : Val} (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.spawn f (Expr.val v) }
      (Expr.spawn f (Expr.val v)) ce s σ (withExpr c (Expr.val Val.unit)) ce s :=
  ⟨EffHStepEvalC.spawnV, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.atomicV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {p : Place} {v : Val} (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.atomic p (Expr.val v) }
      (Expr.atomic p (Expr.val v)) ce s σ (withExpr c (Expr.val v)) ce s :=
  ⟨EffHStepEvalC.atomicV, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.unsafeV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {v : Val} (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.unsafeE (Expr.val v) }
      (Expr.unsafeE (Expr.val v)) ce s σ (withExpr c (Expr.val v)) ce s :=
  ⟨EffHStepEvalC.unsafeV, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.regionV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {r : Rgn} {v : Val} (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap) :
    StepPMH [] σ { c with expr := Expr.region r (Expr.val v) }
      (Expr.region r (Expr.val v)) ce s σ (withExpr c (Expr.val v)) ce s :=
  ⟨EffHStepEvalC.regionV, hm, hmv, RStepE.refl, hm, hmv⟩

theorem StepPMH.write {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {p : Place} {v : Val}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce')
    (hm' : MatchUS (setHolders σ p (Effect.holdersOfV v)) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val Val.unit)) :
    StepPMH [] σ { c with expr := Expr.write p (Expr.val v) }
      (Expr.write p (Expr.val v)) ce s
      (setHolders σ p (Effect.holdersOfV v)) c' ce' s' := by
  subst hexpr
  exact StepPMH.redex EffHStepEvalC.write hm hmv hr hm' hmv'

theorem StepPMH.alloc {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {a : Nat} {v : Val} {l : Nat}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce') (hm' : MatchUS σ ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (Val.loc l))) :
    StepPMH [] σ { c with expr := Expr.alloc a (Expr.val v) }
      (Expr.alloc a (Expr.val v)) ce s σ c' ce' s' := by
  subst hexpr
  exact StepPMH.redex EffHStepEvalC.alloc hm hmv hr hm' hmv'

theorem StepPMH.freeze {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {p : Place}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce')
    (hm' : MatchUS (addBorrow σ (freshBid σ) p Mode.frozen) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (Val.valH (freshBid σ)))) :
    StepPMH [freshBid σ] σ { c with expr := Expr.freeze p }
      (Expr.freeze p) ce s
      (addBorrow σ (freshBid σ) p Mode.frozen) c' ce' s' := by
  subst hexpr
  exact StepPMH.redex EffHStepEvalC.freeze hm hmv hr hm' hmv'

theorem StepPMH.recover {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {b : Bid} {l : Nat}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce')
    (hm' : MatchUS (ConsumeResult σ [b]) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (Val.loc l))) :
    StepPMH [] σ { c with expr := Expr.recover (Expr.val (Val.valH b)) }
      (Expr.recover (Expr.val (Val.valH b))) ce s
      (ConsumeResult σ [b]) c' ce' s' := by
  subst hexpr
  exact StepPMH.redex EffHStepEvalC.recover hm hmv hr hm' hmv'

theorem StepPMH.recoverAny {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {v : Val}
    (hV : Effect.holdersOfV v = [])
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce')
    (hm' : MatchUS (ConsumeResult σ []) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (Val.loc 0))) :
    StepPMH [] σ { c with expr := Expr.recover (Expr.val v) }
      (Expr.recover (Expr.val v)) ce s
      (ConsumeResult σ []) c' ce' s' := by
  subst hexpr
  exact StepPMH.redex (EffHStepEvalC.recoverAny hV) hm hmv hr hm' hmv'

theorem StepPMH.drop {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {p : Place}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce') (hm' : MatchUS (clearPlace σ p) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val Val.unit)) :
    StepPMH [] σ { c with expr := Expr.drop p } (Expr.drop p) ce s
      (clearPlace σ p) c' ce' s' := by
  subst hexpr
  exact StepPMH.redex EffHStepEvalC.drop hm hmv hr hm' hmv'

theorem StepPMH.derefV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {l : Nat} {v : Val}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce') (hm' : MatchUS σ ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val v)) :
    StepPMH [] σ { c with expr := Expr.derefRaw (Expr.val (Val.loc l)) }
      (Expr.derefRaw (Expr.val (Val.loc l))) ce s σ c' ce' s' := by
  subst hexpr
  exact StepPMH.redex EffHStepEvalC.derefV hm hmv hr hm' hmv'

theorem StepPMH.derefAny {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {v : Val}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce') (hm' : MatchUS σ ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (Val.nat 0))) :
    StepPMH [] σ { c with expr := Expr.derefRaw (Expr.val v) }
      (Expr.derefRaw (Expr.val v)) ce s σ c' ce' s' := by
  subst hexpr
  exact StepPMH.redex EffHStepEvalC.derefAny hm hmv hr hm' hmv'


/-- Active preservation interface for the handle-aware layer: the post typing
    and post matching are derived from the step itself (no `hwt_out`). -/
theorem StepPMH.preservation {A' : List Bid} {σ : Sigma} {c : EvalConf}
    {e : Expr} {ce : ConfE} {s : State} {σ' : Sigma} {c' : EvalConf}
    {ce' : ConfE} {s' : State}
    (h : StepPMH A' σ c e ce s σ' c' ce' s')
    {σ₁ : Sigma} {A : List Bid}
    (hwt : WTyH c.env c.heap e σ σ₁ A) :
    WTyH c'.env c'.heap c'.expr σ' σ₁ A ∧ MatchUS σ' ce' s' :=
  ⟨StepPMH.wt h hwt, h.match_post⟩

/-- Whole-run preservation for the handle-aware layer. -/
theorem StepPMHStar.preservation {σ σ₁ : Sigma} {A : List Bid} {e : Expr}
    {c : EvalConf} {ce : ConfE} {s : State} {σ' : Sigma} {c' : EvalConf}
    {e' : Expr} {ce' : ConfE} {s' : State}
    (h : StepPMHStar σ c e ce s σ' c' e' ce' s')
    (hwt : WTyH c.env c.heap e σ σ₁ A) :
    WTyH c'.env c'.heap e' σ' σ₁ A :=
  WTyH.preserved_stepPMH_star hwt h

/-- Whole-run preservation inside a congruence context. -/
theorem StepPMHStar.preservation_ctx {C : Ctx} (hC : CtxCong C)
    {σ σ₁ : Sigma} {A : List Bid} {e : Expr} {c : EvalConf} {ce : ConfE}
    {s : State} {σ' : Sigma} {c' : EvalConf} {e' : Expr} {ce' : ConfE}
    {s' : State} (h : StepPMHStar σ c e ce s σ' c' e' ce' s')
    (hwt : WTyH c.env c.heap (plug C e) σ σ₁ A) :
    WTyH c'.env c'.heap (plug C e') σ' σ₁ A :=
  StepPMHStar.wt_ctx hC h hwt

end LSys
