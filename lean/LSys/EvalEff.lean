/-
  LSys/EvalEff.lean

  Configuration-level **handle-free** step effects.

  `EffHStepEvalC` (in `EvalConf.lean`) tracks result handles, but its
  fixed-output composition with `EffH` is false (see
  `EffHCounterexample.not_effHStepEvalC_eff_compose`): the handles of a value
  bound to a variable are only known from `c.env`/`c.heap`, not from the
  syntax-level `EffH`.

  `EffStepEvalC` drops the handle component and tracks only `Σ`.  It mirrors
  `StepEvalC` one-to-one (canonical redex rules + prefix-aware context rules),
  except that `var`/`move`/`read` resolve their values from the configuration.
  Consequently:

  * `StepEvalC.toEffStepEvalC` gives every configuration step an effect;
  * `effStepEvalC_eff_compose` composes a step effect with the residual effect;
  * `regionSafe_stepC` transports `Effect.RegionSafe` across a step.

  `RegionSafe`/`NoEscape` depend only on `Σ.lam`, so the handle-free effect is
  sufficient for region safety; handle-precise reasoning would need an
  environment-relative `EffH`, which is not built here.
-/

import LSys.EvalConf

namespace LSys

set_option linter.unusedVariables false

/-- Configuration-level handle-free step effect. -/
inductive EffStepEvalC : Sigma → EvalConf → Expr → EvalConf → Sigma → Prop where
  | varV {σ : Sigma} {c : EvalConf} {x : Var} {v : RVal}
      (h : c.env x = some v) :
      EffStepEvalC σ { c with expr := Expr.var x } (Expr.var x)
        (withExpr c (Expr.val (toVal v))) σ
  | moveV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      EffStepEvalC σ { c with expr := Expr.move p } (Expr.move p)
        (withExpr c (Expr.val (toVal v))) (clearPlace σ p)
  | readV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      EffStepEvalC σ { c with expr := Expr.read p } (Expr.read p)
        (withExpr c (Expr.val (toVal v))) (addBorrow σ 0 p Mode.frozen)
  | val {σ : Sigma} {c : EvalConf} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.val v } (Expr.val v)
        (withExpr c (Expr.val v)) σ
  | abort {σ : Sigma} {c : EvalConf} {k : Nat} :
      EffStepEvalC σ { c with expr := Expr.abort k } (Expr.abort k)
        (withExpr c (Expr.abort k)) σ
  | op {σ : Sigma} {c : EvalConf} {a b : Nat} :
      EffStepEvalC σ { c with expr := Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)) }
        (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        (withExpr c (Expr.val (Val.nat (a + b)))) σ
  | opAny {σ : Sigma} {c : EvalConf} {v w : Val} :
      EffStepEvalC σ { c with expr := Expr.op (Expr.val v) (Expr.val w) }
        (Expr.op (Expr.val v) (Expr.val w)) (withExpr c (Expr.val (Val.nat 0))) σ
  | letV {σ : Sigma} {c : EvalConf} {x : Var} {v : Val} {b : Expr} :
      EffStepEvalC σ { c with expr := Expr.letE x (Expr.val v) b }
        (Expr.letE x (Expr.val v) b) (withExpr c b) σ
  | seqV {σ : Sigma} {c : EvalConf} {v : Val} {b : Expr} :
      EffStepEvalC σ { c with expr := Expr.seq (Expr.val v) b }
        (Expr.seq (Expr.val v) b) (withExpr c b) σ
  | callV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} {body : Expr} :
      EffStepEvalC σ { c with expr := Expr.call f (Expr.val v) body }
        (Expr.call f (Expr.val v) body) (withExpr c body) σ
  | freeze {σ : Sigma} {c : EvalConf} {p : Place} {b : Bid} :
      EffStepEvalC σ { c with expr := Expr.freeze p } (Expr.freeze p)
        (withExpr c (Expr.val (Val.valH b))) (addBorrow σ b p Mode.frozen)
  | recover {σ : Sigma} {c : EvalConf} {b : Bid} {l : Nat} :
      EffStepEvalC σ { c with expr := Expr.recover (Expr.val (Val.valH b)) }
        (Expr.recover (Expr.val (Val.valH b)))
        (withExpr c (Expr.val (Val.loc l))) (ConsumeResult σ [b])
  | recoverAny {σ : Sigma} {c : EvalConf} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.recover (Expr.val v) }
        (Expr.recover (Expr.val v)) (withExpr c (Expr.val (Val.loc 0))) σ
  | write {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.write p (Expr.val v) }
        (Expr.write p (Expr.val v)) (withExpr c (Expr.val Val.unit))
        (setHolders σ p (Effect.holdersOfV v))
  | alloc {σ : Sigma} {c : EvalConf} {a : Nat} {v : Val} {l : Nat} :
      EffStepEvalC σ { c with expr := Expr.alloc a (Expr.val v) }
        (Expr.alloc a (Expr.val v)) (withExpr c (Expr.val (Val.loc l))) σ
  | drop {σ : Sigma} {c : EvalConf} {p : Place} :
      EffStepEvalC σ { c with expr := Expr.drop p } (Expr.drop p)
        (withExpr c (Expr.val Val.unit)) (clearPlace σ p)
  | regionV {σ : Sigma} {c : EvalConf} {r : Rgn} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.region r (Expr.val v) }
        (Expr.region r (Expr.val v)) (withExpr c (Expr.val v)) σ
  | retV {σ : Sigma} {c : EvalConf} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.ret (Expr.val v) }
        (Expr.ret (Expr.val v)) (withExpr c (Expr.val v)) σ
  | spawnV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.spawn f (Expr.val v) }
        (Expr.spawn f (Expr.val v)) (withExpr c (Expr.val Val.unit)) σ
  | atomicV {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.atomic p (Expr.val v) }
        (Expr.atomic p (Expr.val v)) (withExpr c (Expr.val v)) σ
  | unsafeV {σ : Sigma} {c : EvalConf} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.unsafeE (Expr.val v) }
        (Expr.unsafeE (Expr.val v)) (withExpr c (Expr.val v)) σ
  | derefV {σ : Sigma} {c : EvalConf} {l : Nat} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.derefRaw (Expr.val (Val.loc l)) }
        (Expr.derefRaw (Expr.val (Val.loc l))) (withExpr c (Expr.val v)) σ
  | derefAny {σ : Sigma} {c : EvalConf} {v : Val} :
      EffStepEvalC σ { c with expr := Expr.derefRaw (Expr.val v) }
        (Expr.derefRaw (Expr.val v)) (withExpr c (Expr.val (Val.nat 0))) σ
  | borrowEnter {σ : Sigma} {c : EvalConf} {p : Place} {x : Var} {e : Expr} :
      EffStepEvalC σ { c with expr := Expr.borrow p x e } (Expr.borrow p x e)
        { c with expr := e, state := State.mk (c.state.borrow + 1) }
        (addBorrow σ 0 p Mode.mut)
  | borrowExit {σ : Sigma} {c : EvalConf} {v : Val} {n : Nat} :
      EffStepEvalC σ { c with expr := Expr.val v, state := State.mk (n + 1) }
        (Expr.val v) { c with expr := Expr.val v, state := State.mk n } σ
  | abortBorrow {σ : Sigma} {c : EvalConf} {k : Nat} {n : Nat} :
      EffStepEvalC σ { c with expr := Expr.abort k, state := State.mk (n + 1) }
        (Expr.abort k) { c with expr := Expr.abort k, state := State.mk n } σ
  | opL {σ σ' : Sigma} {c : EvalConf} {a b a' : Expr} {s' : State}
      (h : EffStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.op a b } (Expr.op a b)
        { c with expr := Expr.op a' b, state := s' } σ'
  | opR {σ σ' : Sigma} {c : EvalConf} {a b b' : Expr} {s' : State}
      (hv : IsVal a)
      (h : EffStepEvalC σ { c with expr := b } b
        { c with expr := b', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.op a b } (Expr.op a b)
        { c with expr := Expr.op a b', state := s' } σ'
  | letB {σ σ' : Sigma} {c : EvalConf} {x : Var} {a b a' : Expr}
      {s' : State}
      (h : EffStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.letE x a b } (Expr.letE x a b)
        { c with expr := Expr.letE x a' b, state := s' } σ'
  | writeB {σ σ' : Sigma} {c : EvalConf} {p : Place} {e e' : Expr}
      {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.write p e } (Expr.write p e)
        { c with expr := Expr.write p e', state := s' } σ'
  | seqL {σ σ' : Sigma} {c : EvalConf} {a b a' : Expr} {s' : State}
      (h : EffStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.seq a b } (Expr.seq a b)
        { c with expr := Expr.seq a' b, state := s' } σ'
  | allocB {σ σ' : Sigma} {c : EvalConf} {a : Nat} {e e' : Expr}
      {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.alloc a e } (Expr.alloc a e)
        { c with expr := Expr.alloc a e', state := s' } σ'
  | regionB {σ σ' : Sigma} {c : EvalConf} {r : Rgn} {e e' : Expr}
      {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.region r e } (Expr.region r e)
        { c with expr := Expr.region r e', state := s' } σ'
  | recoverB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.recover e } (Expr.recover e)
        { c with expr := Expr.recover e', state := s' } σ'
  | callB {σ σ' : Sigma} {c : EvalConf} {f : Nat} {a body a' : Expr}
      {s' : State}
      (h : EffStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.call f a body } (Expr.call f a body)
        { c with expr := Expr.call f a' body, state := s' } σ'
  | retB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.ret e } (Expr.ret e)
        { c with expr := Expr.ret e', state := s' } σ'
  | spawnB {σ σ' : Sigma} {c : EvalConf} {f : Nat} {e e' : Expr}
      {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.spawn f e } (Expr.spawn f e)
        { c with expr := Expr.spawn f e', state := s' } σ'
  | atomicB {σ σ' : Sigma} {c : EvalConf} {p : Place} {e e' : Expr}
      {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.atomic p e } (Expr.atomic p e)
        { c with expr := Expr.atomic p e', state := s' } σ'
  | unsafeB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.unsafeE e } (Expr.unsafeE e)
        { c with expr := Expr.unsafeE e', state := s' } σ'
  | derefB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      (h : EffStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ') :
      EffStepEvalC σ { c with expr := Expr.derefRaw e } (Expr.derefRaw e)
        { c with expr := Expr.derefRaw e', state := s' } σ'

/-- Every configuration step has a configuration-level effect. -/
theorem StepEvalC.toEffStepEvalC {c c' : EvalConf} (h : StepEvalC c c') :
    ∀ σ, ∃ σ', EffStepEvalC σ c c.expr c' σ' := by
  induction h with
  | varV hx => intro σ; exact ⟨σ, EffStepEvalC.varV hx⟩
  | moveV hv => intro σ; exact ⟨clearPlace σ _, EffStepEvalC.moveV hv⟩
  | readV hv => intro σ; exact ⟨addBorrow σ 0 _ Mode.frozen, EffStepEvalC.readV hv⟩
  | op => intro σ; exact ⟨σ, EffStepEvalC.op⟩
  | opAny => intro σ; exact ⟨σ, EffStepEvalC.opAny⟩
  | letV => intro σ; exact ⟨σ, EffStepEvalC.letV⟩
  | seqV => intro σ; exact ⟨σ, EffStepEvalC.seqV⟩
  | callV => intro σ; exact ⟨σ, EffStepEvalC.callV⟩
  | freeze => intro σ; exact ⟨addBorrow σ _ _ Mode.frozen, EffStepEvalC.freeze⟩
  | recover => intro σ; exact ⟨ConsumeResult σ [_], EffStepEvalC.recover⟩
  | recoverAny => intro σ; exact ⟨σ, EffStepEvalC.recoverAny⟩
  | write =>
      intro σ
      exact ⟨setHolders σ _ (Effect.holdersOfV _), EffStepEvalC.write⟩
  | alloc => intro σ; exact ⟨σ, EffStepEvalC.alloc⟩
  | drop => intro σ; exact ⟨clearPlace σ _, EffStepEvalC.drop⟩
  | regionV => intro σ; exact ⟨σ, EffStepEvalC.regionV⟩
  | retV => intro σ; exact ⟨σ, EffStepEvalC.retV⟩
  | spawnV => intro σ; exact ⟨σ, EffStepEvalC.spawnV⟩
  | atomicV => intro σ; exact ⟨σ, EffStepEvalC.atomicV⟩
  | unsafeV => intro σ; exact ⟨σ, EffStepEvalC.unsafeV⟩
  | derefV => intro σ; exact ⟨σ, EffStepEvalC.derefV⟩
  | derefAny => intro σ; exact ⟨σ, EffStepEvalC.derefAny⟩
  | borrowEnter =>
      intro σ
      exact ⟨addBorrow σ 0 _ Mode.mut, EffStepEvalC.borrowEnter⟩
  | borrowExit =>
      intro σ
      exact ⟨σ, EffStepEvalC.borrowExit⟩
  | abortBorrow =>
      intro σ
      exact ⟨σ, EffStepEvalC.abortBorrow⟩
  | opL h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.opL hs⟩
  | opR hv h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.opR hv hs⟩
  | letB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.letB hs⟩
  | writeB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.writeB hs⟩
  | seqL h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.seqL hs⟩
  | allocB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.allocB hs⟩
  | regionB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.regionB hs⟩
  | recoverB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.recoverB hs⟩
  | callB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.callB hs⟩
  | retB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.retB hs⟩
  | spawnB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.spawnB hs⟩
  | atomicB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.atomicB hs⟩
  | unsafeB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.unsafeB hs⟩
  | derefB h ih =>
      intro σ
      cases ih σ with
      | intro σ' hs => exact ⟨σ', EffStepEvalC.derefB hs⟩

/-- Composition: a step effect followed by the residual effect equals the
    effect of the original expression. -/
theorem effStepEvalC_eff_compose {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    (hstep : EffStepEvalC σ c e c' σ') :
    ∀ σ'', Effect.Eff σ' c'.expr σ'' → Effect.Eff σ e σ'' := by
  induction hstep with
  | varV h =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.var _ _
  | moveV h =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.move
  | readV h =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.read
  | val =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.val _ _
  | abort =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.abort _ _
  | op =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.op (Effect.Eff.val _ _) (Effect.Eff.val _ _)
  | opAny =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.op (Effect.Eff.val _ _) (Effect.Eff.val _ _)
  | letV =>
      intro σ'' hres
      exact Effect.Eff.letE (Effect.Eff.val _ _) hres
  | seqV =>
      intro σ'' hres
      exact Effect.Eff.seq (Effect.Eff.val _ _) hres
  | callV =>
      intro σ'' hres
      exact Effect.Eff.call (Effect.Eff.val _ _) hres
  | freeze =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.freeze
  | recover =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.recoverCtxConsume (Effect.Eff.val _ _) _
  | recoverAny =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.recoverCtx (Effect.Eff.val _ _)
  | write =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.write (A := Effect.holdersOfV _) (Effect.Eff.val _ _)
  | alloc =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.alloc (Effect.Eff.val _ _)
  | drop =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.drop
  | regionV =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.region (Effect.Eff.val _ _)
  | retV =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.ret (Effect.Eff.val _ _)
  | spawnV =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.spawn (Effect.Eff.val _ _)
  | atomicV =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.atomic (Effect.Eff.val _ _)
  | unsafeV =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.unsafeE (Effect.Eff.val _ _)
  | derefV =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.deref (Effect.Eff.val _ _)
  | derefAny =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.deref (Effect.Eff.val _ _)
  | borrowEnter =>
      intro σ'' hres
      exact Effect.Eff.borrow hres
  | borrowExit =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.val _ _
  | abortBorrow =>
      intro σ'' hres
      cases hres
      exact Effect.Eff.abort _ _
  | opL h ih =>
      intro σ'' hres
      cases hres with
      | op h1 h2 => exact Effect.Eff.op (ih _ h1) h2
  | opR hv h ih =>
      intro σ'' hres
      cases hres with
      | op h1 h2 =>
          cases Effect.isVal_eq hv with
          | intro v hv' =>
              cases hv'
              cases h1
              exact Effect.Eff.op (Effect.Eff.val _ _) (ih _ h2)
  | letB h ih =>
      intro σ'' hres
      cases hres with
      | letE h1 h2 => exact Effect.Eff.letE (ih _ h1) h2
  | writeB h ih =>
      intro σ'' hres
      cases hres with
      | write h1 => exact Effect.Eff.write (ih _ h1)
  | seqL h ih =>
      intro σ'' hres
      cases hres with
      | seq h1 h2 => exact Effect.Eff.seq (ih _ h1) h2
  | allocB h ih =>
      intro σ'' hres
      cases hres with
      | alloc h1 => exact Effect.Eff.alloc (ih _ h1)
  | regionB h ih =>
      intro σ'' hres
      cases hres with
      | region h1 => exact Effect.Eff.region (ih _ h1)
  | recoverB h ih =>
      intro σ'' hres
      cases hres with
      | recoverCtx h1 => exact Effect.Eff.recoverCtx (ih _ h1)
      | recoverCtxConsume h1 b => exact Effect.Eff.recoverCtxConsume (ih _ h1) b
  | callB h ih =>
      intro σ'' hres
      cases hres with
      | call h1 h2 => exact Effect.Eff.call (ih _ h1) h2
  | retB h ih =>
      intro σ'' hres
      cases hres with
      | ret h1 => exact Effect.Eff.ret (ih _ h1)
  | spawnB h ih =>
      intro σ'' hres
      cases hres with
      | spawn h1 => exact Effect.Eff.spawn (ih _ h1)
  | atomicB h ih =>
      intro σ'' hres
      cases hres with
      | atomic h1 => exact Effect.Eff.atomic (ih _ h1)
  | unsafeB h ih =>
      intro σ'' hres
      cases hres with
      | unsafeE h1 => exact Effect.Eff.unsafeE (ih _ h1)
  | derefB h ih =>
      intro σ'' hres
      cases hres with
      | deref h1 => exact Effect.Eff.deref (ih _ h1)

/-- `RegionSafe` is preserved by a configuration-level step. -/
theorem regionSafe_stepC {σ σ' : Sigma} {R : Rgn} {c c' : EvalConf}
    {e : Expr} (hno : Effect.RegionSafe σ R e)
    (hstep : EffStepEvalC σ c e c' σ') :
    Effect.RegionSafe σ' R c'.expr := by
  intro σ'' hres
  exact hno σ'' (effStepEvalC_eff_compose hstep σ'' hres)

end LSys
