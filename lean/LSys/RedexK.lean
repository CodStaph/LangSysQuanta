/-
  LSys/RedexK.lean

  The **redex-only** fragment of `EffHStepEvalCK`: the canonical steps at the
  root, excluding the prefix-aware context rules.  This is the fragment in
  which the value-dependent `let`/`borrow` steps (with `setEnv`/`bindHolders`
  updates) can be preserved without an environment-agreement layer.
-/

import LSys.EffHCK

namespace LSys

set_option linter.unusedVariables false

inductive RedexK :
    Sigma → EvalConf → Expr → EvalConf → Sigma → List Bid → Prop where
  | varV {σ : Sigma} {c : EvalConf} {x : Var} {v : RVal}
      (h : c.env x = some v) :
      RedexK σ { c with expr := Expr.var x } (Expr.var x)
        { c with expr := Expr.val (toVal v) } σ (holdersOfR v)
  | moveV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      RedexK σ { c with expr := Expr.move p } (Expr.move p)
        { c with expr := Expr.val (toVal v) } (clearPlace σ p)
        (holdersOfR v)
  | readV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      RedexK σ { c with expr := Expr.read p } (Expr.read p)
        { c with expr := Expr.val (toVal v) }
        (addBorrow σ (freshBid σ) p Mode.frozen) (holdersOfR v)
  | val {σ : Sigma} {c : EvalConf} {v : Val} :
      RedexK σ { c with expr := Expr.val v } (Expr.val v)
        { c with expr := Expr.val v } σ (Effect.holdersOfV v)
  | abort {σ : Sigma} {c : EvalConf} {k : Nat} :
      RedexK σ { c with expr := Expr.abort k } (Expr.abort k)
        { c with expr := Expr.abort k } σ []
  | op {σ : Sigma} {c : EvalConf} {a b : Nat} :
      RedexK σ
        { c with expr := Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)) }
        (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        { c with expr := Expr.val (Val.nat (a + b)) } σ []
  | opAny {σ : Sigma} {c : EvalConf} {v w : Val} :
      RedexK σ { c with expr := Expr.op (Expr.val v) (Expr.val w) }
        (Expr.op (Expr.val v) (Expr.val w))
        { c with expr := Expr.val (Val.nat 0) } σ []
  | letV {σ : Sigma} {c : EvalConf} {x : Var} {v : Val} {b : Expr}
      (hfresh : c.env x = none) :
      RedexK σ { c with expr := Expr.letE x (Expr.val v) b }
        (Expr.letE x (Expr.val v) b)
        { c with expr := b, env := setEnv c.env x (ofVal v) }
        (bindHolders σ x (Effect.holdersOfV v)) []
  | seqV {σ : Sigma} {c : EvalConf} {v : Val} {b : Expr} :
      RedexK σ { c with expr := Expr.seq (Expr.val v) b }
        (Expr.seq (Expr.val v) b) { c with expr := b } σ []
  | callV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} {body : Expr} :
      RedexK σ { c with expr := Expr.call f (Expr.val v) body }
        (Expr.call f (Expr.val v) body) { c with expr := body } σ []
  | freeze {σ : Sigma} {c : EvalConf} {p : Place} :
      RedexK σ { c with expr := Expr.freeze p } (Expr.freeze p)
        { c with expr := Expr.val (Val.valH (freshBid σ)) }
        (addBorrow σ (freshBid σ) p Mode.frozen) [freshBid σ]
  | recover {σ : Sigma} {c : EvalConf} {b : Bid} {l : Nat} :
      RedexK σ { c with expr := Expr.recover (Expr.val (Val.valH b)) }
        (Expr.recover (Expr.val (Val.valH b)))
        { c with expr := Expr.val (Val.loc l) } (ConsumeResult σ [b]) []
  | recoverAny {σ : Sigma} {c : EvalConf} {v : Val}
      (hV : Effect.holdersOfV v = []) :
      RedexK σ { c with expr := Expr.recover (Expr.val v) }
        (Expr.recover (Expr.val v))
        { c with expr := Expr.val (Val.loc 0) } (ConsumeResult σ []) []
  | write {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      RedexK σ { c with expr := Expr.write p (Expr.val v) }
        (Expr.write p (Expr.val v))
        { c with expr := Expr.val Val.unit }
        (setHolders σ p (Effect.holdersOfV v)) []
  | alloc {σ : Sigma} {c : EvalConf} {a : Nat} {v : Val} {l : Nat} :
      RedexK σ { c with expr := Expr.alloc a (Expr.val v) }
        (Expr.alloc a (Expr.val v))
        { c with expr := Expr.val (Val.loc l) } σ []
  | drop {σ : Sigma} {c : EvalConf} {p : Place} :
      RedexK σ { c with expr := Expr.drop p } (Expr.drop p)
        { c with expr := Expr.val Val.unit } (clearPlace σ p) []
  | regionV {σ : Sigma} {c : EvalConf} {r : Rgn} {v : Val} :
      RedexK σ { c with expr := Expr.region r (Expr.val v) }
        (Expr.region r (Expr.val v)) { c with expr := Expr.val v } σ []
  | retV {σ : Sigma} {c : EvalConf} {v : Val} :
      RedexK σ { c with expr := Expr.ret (Expr.val v) }
        (Expr.ret (Expr.val v)) { c with expr := Expr.val v } σ []
  | spawnV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} :
      RedexK σ { c with expr := Expr.spawn f (Expr.val v) }
        (Expr.spawn f (Expr.val v))
        { c with expr := Expr.val Val.unit } σ []
  | atomicV {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      RedexK σ { c with expr := Expr.atomic p (Expr.val v) }
        (Expr.atomic p (Expr.val v)) { c with expr := Expr.val v } σ []
  | unsafeV {σ : Sigma} {c : EvalConf} {v : Val} :
      RedexK σ { c with expr := Expr.unsafeE (Expr.val v) }
        (Expr.unsafeE (Expr.val v)) { c with expr := Expr.val v } σ []
  | derefV {σ : Sigma} {c : EvalConf} {l : Nat} {v : Val} :
      RedexK σ { c with expr := Expr.derefRaw (Expr.val (Val.loc l)) }
        (Expr.derefRaw (Expr.val (Val.loc l)))
        { c with expr := Expr.val v } σ []
  | derefAny {σ : Sigma} {c : EvalConf} {v : Val} :
      RedexK σ { c with expr := Expr.derefRaw (Expr.val v) }
        (Expr.derefRaw (Expr.val v))
        { c with expr := Expr.val (Val.nat 0) } σ []
  | borrowEnter {σ : Sigma} {c : EvalConf} {p : Place} {x : Var} {e : Expr}
      (hfresh : c.env x = none) :
      RedexK σ { c with expr := Expr.borrow p x e } (Expr.borrow p x e)
        { c with expr := e, env := setEnv c.env x (RVal.refH 0), state := State.mk (c.state.borrow + 1) }
        (addBorrow σ 0 p Mode.mut) []
  | borrowExit {σ : Sigma} {c : EvalConf} {v : Val} {n : Nat} :
      RedexK σ { c with expr := Expr.val v, state := State.mk (n + 1) }
        (Expr.val v) { c with expr := Expr.val v, state := State.mk n } σ []
  | abortBorrow {σ : Sigma} {c : EvalConf} {k : Nat} {n : Nat} :
      RedexK σ { c with expr := Expr.abort k, state := State.mk (n + 1) }
        (Expr.abort k) { c with expr := Expr.abort k, state := State.mk n } σ []

/-- Every redex step is a configuration step. -/
theorem RedexK.toEffHStepEvalCK {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (h : RedexK σ c e c' σ' A) :
    EffHStepEvalCK σ c e c' σ' A := by
  induction h with
  | varV h => exact EffHStepEvalCK.varV h
  | moveV h => exact EffHStepEvalCK.moveV h
  | readV h => exact EffHStepEvalCK.readV h
  | val => exact EffHStepEvalCK.val
  | abort => exact EffHStepEvalCK.abort
  | op => exact EffHStepEvalCK.op
  | opAny => exact EffHStepEvalCK.opAny
  | letV hfresh => exact EffHStepEvalCK.letV hfresh
  | seqV => exact EffHStepEvalCK.seqV
  | callV => exact EffHStepEvalCK.callV
  | freeze => exact EffHStepEvalCK.freeze
  | recover => exact EffHStepEvalCK.recover
  | recoverAny hV => exact EffHStepEvalCK.recoverAny hV
  | write => exact EffHStepEvalCK.write
  | alloc => exact EffHStepEvalCK.alloc
  | drop => exact EffHStepEvalCK.drop
  | regionV => exact EffHStepEvalCK.regionV
  | retV => exact EffHStepEvalCK.retV
  | spawnV => exact EffHStepEvalCK.spawnV
  | atomicV => exact EffHStepEvalCK.atomicV
  | unsafeV => exact EffHStepEvalCK.unsafeV
  | derefV => exact EffHStepEvalCK.derefV
  | derefAny => exact EffHStepEvalCK.derefAny
  | borrowEnter hfresh => exact EffHStepEvalCK.borrowEnter hfresh
  | borrowExit => exact EffHStepEvalCK.borrowExit
  | abortBorrow => exact EffHStepEvalCK.abortBorrow

end LSys
