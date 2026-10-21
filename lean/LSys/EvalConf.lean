/-
  LSys/EvalConf.lean

  Configuration-level evaluation steps with actual environment/heap values.

  `StepEval` (syntax-level) cannot express the value read from `var x`,
  `move p`, or `read p`.  `StepEvalC` adds an environment and a value heap:

    EvalConf = (expr, env, heap, state)

  The value-carrying rules are `varV`, `moveV`, `readV`; every canonical
  redex has its own rule (`op`, `letV`, `freeze`, ...), matching
  `EffStepEvalC`.  The step relation is therefore not the total raw `Step`:
  the raw `ctx`/`val`/borrow-frame steps are deliberately excluded so that
  effects correspond one-to-one.
-/

import LSys.StepEval
import LSys.Runtime
import LSys.Effect

namespace LSys

set_option linter.unusedVariables false

abbrev EvalEnv := Var → Option RVal
abbrev EvalHeap := Place → Option RVal

/-- `env'` preserves every binding of `env` (an environment extension). -/
def EnvExtends (env env' : EvalEnv) : Prop :=
  ∀ x v, env x = some v → env' x = some v

theorem EnvExtends.refl (env : EvalEnv) : EnvExtends env env :=
  fun _ _ h => h

theorem EnvExtends.trans {a b c : EvalEnv}
    (h1 : EnvExtends a b) (h2 : EnvExtends b c) : EnvExtends a c :=
  fun x v hx => h2 x v (h1 x v hx)

/-- Inverse of `toVal` on the value constructors. -/
def ofVal : Val → RVal
  | Val.unit => RVal.unit
  | Val.nat n => RVal.nat n
  | Val.loc l => RVal.loc l
  | Val.valH b => RVal.valH b
  | Val.refH b => RVal.refH b

def toVal : RVal → Val
  | RVal.unit => Val.unit
  | RVal.nat n => Val.nat n
  | RVal.loc l => Val.loc l
  | RVal.valH b => Val.valH b
  | RVal.refH b => Val.refH b

def holdersOfR : RVal → List Bid
  | RVal.valH b => [b]
  | RVal.refH b => [b]
  | _ => []

structure EvalConf where
  expr : Expr
  env : EvalEnv
  heap : EvalHeap
  state : State

def withExpr (c : EvalConf) (e : Expr) : EvalConf :=
  { c with expr := e }

inductive StepEvalC : EvalConf → EvalConf → Prop where
  | varV {c : EvalConf} {x : Var} {v : RVal}
      (h : c.env x = some v) :
      StepEvalC { c with expr := Expr.var x } (withExpr c (Expr.val (toVal v)))
  | moveV {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      StepEvalC { c with expr := Expr.move p } (withExpr c (Expr.val (toVal v)))
  | readV {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      StepEvalC { c with expr := Expr.read p } (withExpr c (Expr.val (toVal v)))
  -- Canonical redex rules (one per `EffStepEvalC` redex).
  | op {c : EvalConf} {a b : Nat} :
      StepEvalC { c with expr := Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)) }
        (withExpr c (Expr.val (Val.nat (a + b))))
  | opAny {c : EvalConf} {v w : Val} :
      StepEvalC { c with expr := Expr.op (Expr.val v) (Expr.val w) }
        (withExpr c (Expr.val (Val.nat 0)))
  | letV {c : EvalConf} {x : Var} {v : Val} {b : Expr} :
      StepEvalC { c with expr := Expr.letE x (Expr.val v) b } (withExpr c b)
  | seqV {c : EvalConf} {v : Val} {b : Expr} :
      StepEvalC { c with expr := Expr.seq (Expr.val v) b } (withExpr c b)
  | callV {c : EvalConf} {f : Nat} {v : Val} {body : Expr} :
      StepEvalC { c with expr := Expr.call f (Expr.val v) body } (withExpr c body)
  | freeze {c : EvalConf} {p : Place} {b : Bid} :
      StepEvalC { c with expr := Expr.freeze p }
        (withExpr c (Expr.val (Val.valH b)))
  | recover {c : EvalConf} {b : Bid} {l : Nat} :
      StepEvalC { c with expr := Expr.recover (Expr.val (Val.valH b)) }
        (withExpr c (Expr.val (Val.loc l)))
  | recoverAny {c : EvalConf} {v : Val} :
      StepEvalC { c with expr := Expr.recover (Expr.val v) }
        (withExpr c (Expr.val (Val.loc 0)))
  | write {c : EvalConf} {p : Place} {v : Val} :
      StepEvalC { c with expr := Expr.write p (Expr.val v) }
        (withExpr c (Expr.val Val.unit))
  | alloc {c : EvalConf} {a : Nat} {v : Val} {l : Nat} :
      StepEvalC { c with expr := Expr.alloc a (Expr.val v) }
        (withExpr c (Expr.val (Val.loc l)))
  | drop {c : EvalConf} {p : Place} :
      StepEvalC { c with expr := Expr.drop p } (withExpr c (Expr.val Val.unit))
  | regionV {c : EvalConf} {r : Rgn} {v : Val} :
      StepEvalC { c with expr := Expr.region r (Expr.val v) }
        (withExpr c (Expr.val v))
  | retV {c : EvalConf} {v : Val} :
      StepEvalC { c with expr := Expr.ret (Expr.val v) } (withExpr c (Expr.val v))
  | spawnV {c : EvalConf} {f : Nat} {v : Val} :
      StepEvalC { c with expr := Expr.spawn f (Expr.val v) }
        (withExpr c (Expr.val Val.unit))
  | atomicV {c : EvalConf} {p : Place} {v : Val} :
      StepEvalC { c with expr := Expr.atomic p (Expr.val v) }
        (withExpr c (Expr.val v))
  | unsafeV {c : EvalConf} {v : Val} :
      StepEvalC { c with expr := Expr.unsafeE (Expr.val v) }
        (withExpr c (Expr.val v))
  | derefV {c : EvalConf} {l : Nat} {v : Val} :
      StepEvalC { c with expr := Expr.derefRaw (Expr.val (Val.loc l)) }
        (withExpr c (Expr.val v))
  | derefAny {c : EvalConf} {v : Val} :
      StepEvalC { c with expr := Expr.derefRaw (Expr.val v) }
        (withExpr c (Expr.val (Val.nat 0)))
  | borrowEnter {c : EvalConf} {p : Place} {x : Var} {e : Expr} :
      StepEvalC { c with expr := Expr.borrow p x e }
        { c with expr := e, state := State.mk (c.state.borrow + 1) }
  | borrowExit {c : EvalConf} {v : Val} {n : Nat} :
      StepEvalC { c with expr := Expr.val v, state := State.mk (n + 1) }
        { c with expr := Expr.val v, state := State.mk n }
  | abortBorrow {c : EvalConf} {k : Nat} {n : Nat} :
      StepEvalC { c with expr := Expr.abort k, state := State.mk (n + 1) }
        { c with expr := Expr.abort k, state := State.mk n }
  -- Prefix-aware context rules: `env`/`heap` are untouched, only the
  -- expression and the (borrow-frame) state advance.
  | opL {c : EvalConf} {a b a' : Expr} {s' : State}
      (h : StepEvalC { c with expr := a } { c with expr := a', state := s' }) :
      StepEvalC { c with expr := Expr.op a b }
        { c with expr := Expr.op a' b, state := s' }
  | opR {c : EvalConf} {a b b' : Expr} {s' : State} (hv : IsVal a)
      (h : StepEvalC { c with expr := b } { c with expr := b', state := s' }) :
      StepEvalC { c with expr := Expr.op a b }
        { c with expr := Expr.op a b', state := s' }
  | letB {c : EvalConf} {x : Var} {a b a' : Expr} {s' : State}
      (h : StepEvalC { c with expr := a } { c with expr := a', state := s' }) :
      StepEvalC { c with expr := Expr.letE x a b }
        { c with expr := Expr.letE x a' b, state := s' }
  | writeB {c : EvalConf} {p : Place} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.write p e }
        { c with expr := Expr.write p e', state := s' }
  | seqL {c : EvalConf} {a b a' : Expr} {s' : State}
      (h : StepEvalC { c with expr := a } { c with expr := a', state := s' }) :
      StepEvalC { c with expr := Expr.seq a b }
        { c with expr := Expr.seq a' b, state := s' }
  | allocB {c : EvalConf} {a : Nat} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.alloc a e }
        { c with expr := Expr.alloc a e', state := s' }
  | regionB {c : EvalConf} {r : Rgn} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.region r e }
        { c with expr := Expr.region r e', state := s' }
  | recoverB {c : EvalConf} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.recover e }
        { c with expr := Expr.recover e', state := s' }
  | callB {c : EvalConf} {f : Nat} {a body a' : Expr} {s' : State}
      (h : StepEvalC { c with expr := a } { c with expr := a', state := s' }) :
      StepEvalC { c with expr := Expr.call f a body }
        { c with expr := Expr.call f a' body, state := s' }
  | retB {c : EvalConf} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.ret e }
        { c with expr := Expr.ret e', state := s' }
  | spawnB {c : EvalConf} {f : Nat} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.spawn f e }
        { c with expr := Expr.spawn f e', state := s' }
  | atomicB {c : EvalConf} {p : Place} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.atomic p e }
        { c with expr := Expr.atomic p e', state := s' }
  | unsafeB {c : EvalConf} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.unsafeE e }
        { c with expr := Expr.unsafeE e', state := s' }
  | derefB {c : EvalConf} {e e' : Expr} {s' : State}
      (h : StepEvalC { c with expr := e } { c with expr := e', state := s' }) :
      StepEvalC { c with expr := Expr.derefRaw e }
        { c with expr := Expr.derefRaw e', state := s' }


/-- Projection to the raw syntax-level `Step` (for L-Term/L-Progress). -/
theorem StepEvalC.toStep {c c' : EvalConf} (h : StepEvalC c c') :
    Step c.expr c.state c'.expr c'.state := by
  induction h with
  | varV h => exact Step.varV
  | moveV h => exact Step.moveV
  | readV h => exact Step.readV
  | op => exact Step.op
  | opAny => exact Step.opAny
  | letV => exact Step.letV
  | seqV => exact Step.seqV
  | callV => exact Step.callV
  | freeze => exact Step.freezeV
  | recover => exact Step.recoverV
  | recoverAny => exact Step.recoverAny
  | write => exact Step.writeV
  | alloc => exact Step.allocV
  | drop => exact Step.dropV
  | regionV => exact Step.regionV
  | retV => exact Step.retV
  | spawnV => exact Step.spawnV
  | atomicV => exact Step.atomicV
  | unsafeV => exact Step.unsafeV
  | derefV => exact Step.derefV
  | derefAny => exact Step.derefAny
  | borrowEnter => exact Step.borrowEnter
  | borrowExit => exact Step.borrowExit
  | abortBorrow => exact Step.abortBorrow
  | opL h ih => exact Step.ctx (C := Ctx.opL Ctx.hole _) ih
  | opR hv h ih => exact Step.ctx (C := Ctx.opR _ Ctx.hole) ih
  | letB h ih => exact Step.ctx (C := Ctx.letB _ Ctx.hole _) ih
  | writeB h ih => exact Step.ctx (C := Ctx.writeB _ Ctx.hole) ih
  | seqL h ih => exact Step.ctx (C := Ctx.seqL Ctx.hole _) ih
  | allocB h ih => exact Step.ctx (C := Ctx.allocB _ Ctx.hole) ih
  | regionB h ih => exact Step.ctx (C := Ctx.regionB _ Ctx.hole) ih
  | recoverB h ih => exact Step.ctx (C := Ctx.recoverB Ctx.hole) ih
  | callB h ih => exact Step.ctx (C := Ctx.callB _ Ctx.hole _) ih
  | retB h ih => exact Step.ctx (C := Ctx.retB Ctx.hole) ih
  | spawnB h ih => exact Step.ctx (C := Ctx.spawnB _ Ctx.hole) ih
  | atomicB h ih => exact Step.ctx (C := Ctx.atomicB _ Ctx.hole) ih
  | unsafeB h ih => exact Step.ctx (C := Ctx.unsafeB Ctx.hole) ih
  | derefB h ih => exact Step.ctx (C := Ctx.derefB Ctx.hole) ih


theorem stepEvalC_decreases {c c' : EvalConf} (h : StepEvalC c c') :
    Mlt (M c'.expr c'.state) (M c.expr c.state) :=
  step_decreases (StepEvalC.toStep h)

/-- Step effect with actual values and handles. -/
inductive EffHStepEvalC : Sigma → EvalConf → Expr → EvalConf → Sigma → List Bid → Prop where
  | varV {σ : Sigma} {c : EvalConf} {x : Var} {v : RVal}
      (h : c.env x = some v) :
      EffHStepEvalC σ c (Expr.var x) (withExpr c (Expr.val (toVal v))) σ
        (holdersOfR v)
  | moveV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      EffHStepEvalC σ c (Expr.move p) (withExpr c (Expr.val (toVal v)))
        (clearPlace σ p) (holdersOfR v)
  | readV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      EffHStepEvalC σ c (Expr.read p) (withExpr c (Expr.val (toVal v)))
        (addBorrow σ (freshBid σ) p Mode.frozen) (holdersOfR v)
  -- Redex rules with the static result handles `A` of the step.
  | val {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalC σ c (Expr.val v) (withExpr c (Expr.val v)) σ
        (Effect.holdersOfV v)
  | abort {σ : Sigma} {c : EvalConf} {k : Nat} :
      EffHStepEvalC σ c (Expr.abort k) (withExpr c (Expr.abort k)) σ []
  | op {σ : Sigma} {c : EvalConf} {a b : Nat} :
      EffHStepEvalC σ c (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        (withExpr c (Expr.val (Val.nat (a + b)))) σ []
  | opAny {σ : Sigma} {c : EvalConf} {v w : Val} :
      EffHStepEvalC σ c (Expr.op (Expr.val v) (Expr.val w))
        (withExpr c (Expr.val (Val.nat 0))) σ []
  | letV {σ : Sigma} {c : EvalConf} {x : Var} {v : Val} {b : Expr} :
      EffHStepEvalC σ c (Expr.letE x (Expr.val v) b) (withExpr c b) σ []
  | seqV {σ : Sigma} {c : EvalConf} {v : Val} {b : Expr} :
      EffHStepEvalC σ c (Expr.seq (Expr.val v) b) (withExpr c b) σ []
  | callV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} {body : Expr} :
      EffHStepEvalC σ c (Expr.call f (Expr.val v) body) (withExpr c body) σ []
  | freeze {σ : Sigma} {c : EvalConf} {p : Place} :
      EffHStepEvalC σ c (Expr.freeze p)
        (withExpr c (Expr.val (Val.valH (freshBid σ))))
        (addBorrow σ (freshBid σ) p Mode.frozen) [freshBid σ]
  | recover {σ : Sigma} {c : EvalConf} {b : Bid} {l : Nat} :
      EffHStepEvalC σ c (Expr.recover (Expr.val (Val.valH b)))
        (withExpr c (Expr.val (Val.loc l))) (ConsumeResult σ [b]) []
  | recoverAny {σ : Sigma} {c : EvalConf} {v : Val}
      (hV : Effect.holdersOfV v = []) :
      EffHStepEvalC σ c (Expr.recover (Expr.val v))
        (withExpr c (Expr.val (Val.loc 0))) (ConsumeResult σ []) []
  | write {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      EffHStepEvalC σ c (Expr.write p (Expr.val v))
        (withExpr c (Expr.val Val.unit)) (setHolders σ p (Effect.holdersOfV v)) []
  | alloc {σ : Sigma} {c : EvalConf} {a : Nat} {v : Val} {l : Nat} :
      EffHStepEvalC σ c (Expr.alloc a (Expr.val v))
        (withExpr c (Expr.val (Val.loc l))) σ []
  | drop {σ : Sigma} {c : EvalConf} {p : Place} :
      EffHStepEvalC σ c (Expr.drop p) (withExpr c (Expr.val Val.unit))
        (clearPlace σ p) []
  | regionV {σ : Sigma} {c : EvalConf} {r : Rgn} {v : Val} :
      EffHStepEvalC σ c (Expr.region r (Expr.val v)) (withExpr c (Expr.val v)) σ []
  | retV {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalC σ c (Expr.ret (Expr.val v)) (withExpr c (Expr.val v)) σ []
  | spawnV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} :
      EffHStepEvalC σ c (Expr.spawn f (Expr.val v))
        (withExpr c (Expr.val Val.unit)) σ []
  | atomicV {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      EffHStepEvalC σ c (Expr.atomic p (Expr.val v)) (withExpr c (Expr.val v)) σ []
  | unsafeV {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalC σ c (Expr.unsafeE (Expr.val v)) (withExpr c (Expr.val v)) σ []
  | derefV {σ : Sigma} {c : EvalConf} {l : Nat} {v : Val} :
      EffHStepEvalC σ c (Expr.derefRaw (Expr.val (Val.loc l)))
        (withExpr c (Expr.val v)) σ []
  | derefAny {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalC σ c (Expr.derefRaw (Expr.val v))
        (withExpr c (Expr.val (Val.nat 0))) σ []
  | borrowEnter {σ : Sigma} {c : EvalConf} {p : Place} {x : Var} {e : Expr} :
      EffHStepEvalC σ c (Expr.borrow p x e)
        { c with expr := e, state := State.mk (c.state.borrow + 1) }
        (addBorrow σ 0 p Mode.mut) []
  | borrowExit {σ : Sigma} {c : EvalConf} {v : Val} {n : Nat} :
      EffHStepEvalC σ { c with expr := Expr.val v, state := State.mk (n + 1) }
        (Expr.val v) { c with expr := Expr.val v, state := State.mk n } σ []
  | abortBorrow {σ : Sigma} {c : EvalConf} {k : Nat} {n : Nat} :
      EffHStepEvalC σ { c with expr := Expr.abort k, state := State.mk (n + 1) }
        (Expr.abort k) { c with expr := Expr.abort k, state := State.mk n } σ []
  -- Prefix-aware context rules: `env`/`heap` untouched; the sub-step keeps
  -- its result handles `A`.
  | opL {σ σ' : Sigma} {c : EvalConf} {a b a' : Expr} {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.op a b } (Expr.op a b)
        { c with expr := Expr.op a' b, state := s' } σ' A
  | opR {σ σ' : Sigma} {c : EvalConf} {a b b' : Expr} {s' : State}
      {A : List Bid} (hv : IsVal a)
      (h : EffHStepEvalC σ { c with expr := b } b
        { c with expr := b', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.op a b } (Expr.op a b)
        { c with expr := Expr.op a b', state := s' } σ' A
  | letB {σ σ' : Sigma} {c : EvalConf} {x : Var} {a b a' : Expr}
      {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.letE x a b } (Expr.letE x a b)
        { c with expr := Expr.letE x a' b, state := s' } σ' A
  | writeB {σ σ' : Sigma} {c : EvalConf} {p : Place} {e e' : Expr}
      {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.write p e } (Expr.write p e)
        { c with expr := Expr.write p e', state := s' } σ' A
  | seqL {σ σ' : Sigma} {c : EvalConf} {a b a' : Expr} {s' : State}
      {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.seq a b } (Expr.seq a b)
        { c with expr := Expr.seq a' b, state := s' } σ' A
  | allocB {σ σ' : Sigma} {c : EvalConf} {a : Nat} {e e' : Expr}
      {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.alloc a e } (Expr.alloc a e)
        { c with expr := Expr.alloc a e', state := s' } σ' A
  | regionB {σ σ' : Sigma} {c : EvalConf} {r : Rgn} {e e' : Expr}
      {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.region r e } (Expr.region r e)
        { c with expr := Expr.region r e', state := s' } σ' A
  | recoverB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.recover e } (Expr.recover e)
        { c with expr := Expr.recover e', state := s' } σ' A
  | callB {σ σ' : Sigma} {c : EvalConf} {f : Nat} {a body a' : Expr}
      {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := a } a
        { c with expr := a', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.call f a body } (Expr.call f a body)
        { c with expr := Expr.call f a' body, state := s' } σ' A
  | retB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.ret e } (Expr.ret e)
        { c with expr := Expr.ret e', state := s' } σ' A
  | spawnB {σ σ' : Sigma} {c : EvalConf} {f : Nat} {e e' : Expr}
      {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.spawn f e } (Expr.spawn f e)
        { c with expr := Expr.spawn f e', state := s' } σ' A
  | atomicB {σ σ' : Sigma} {c : EvalConf} {p : Place} {e e' : Expr}
      {s' : State} {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.atomic p e } (Expr.atomic p e)
        { c with expr := Expr.atomic p e', state := s' } σ' A
  | unsafeB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.unsafeE e } (Expr.unsafeE e)
        { c with expr := Expr.unsafeE e', state := s' } σ' A
  | derefB {σ σ' : Sigma} {c : EvalConf} {e e' : Expr} {s' : State}
      {A : List Bid}
      (h : EffHStepEvalC σ { c with expr := e } e
        { c with expr := e', state := s' } σ' A) :
      EffHStepEvalC σ { c with expr := Expr.derefRaw e } (Expr.derefRaw e)
        { c with expr := Expr.derefRaw e', state := s' } σ' A

end LSys
