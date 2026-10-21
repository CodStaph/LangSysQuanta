/-
  LSys/EffHCK.lean

  `EffHStepEvalCK`: the canonical, prefix-aware configuration step for route A.

  Compared with `EffHStepEvalC`, the environment is no longer constant:

  * `letV` outputs `env := setEnv c.env x (ofVal v)` and
    `Σ' := bindHolders σ x (holdersOfV v)`;
  * `borrowEnter` outputs `env := setEnv c.env x (RVal.refH 0)` and
    `Σ' := addBorrow σ 0 p mut`.

  Context rules therefore **thread the whole output configuration** `c'`
  instead of assuming `env`/`state` are unchanged:

    opL : step a to c'  ⟹  op a b  steps to  { c' with expr := op c'.expr b }

  This is what lets a `let` inside a subexpression update the environment and
  be observed by the surrounding context.
-/

import LSys.EvalConf
import LSys.Effect
import LSys.Env
import LSys.EnvExt

namespace LSys

set_option linter.unusedVariables false

/-- Canonical, prefix-aware step with environment/state threading. -/
inductive EffHStepEvalCK :
    Sigma → EvalConf → Expr → EvalConf → Sigma → List Bid → Prop where
  | varV {σ : Sigma} {c : EvalConf} {x : Var} {v : RVal}
      (h : c.env x = some v) :
      EffHStepEvalCK σ { c with expr := Expr.var x } (Expr.var x)
        { c with expr := Expr.val (toVal v) } σ (holdersOfR v)
  | moveV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      EffHStepEvalCK σ { c with expr := Expr.move p } (Expr.move p)
        { c with expr := Expr.val (toVal v) } (clearPlace σ p)
        (holdersOfR v)
  | readV {σ : Sigma} {c : EvalConf} {p : Place} {v : RVal}
      (h : c.heap p = some v) :
      EffHStepEvalCK σ { c with expr := Expr.read p } (Expr.read p)
        { c with expr := Expr.val (toVal v) }
        (addBorrow σ (freshBid σ) p Mode.frozen) (holdersOfR v)
  | val {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.val v } (Expr.val v)
        { c with expr := Expr.val v } σ (Effect.holdersOfV v)
  | abort {σ : Sigma} {c : EvalConf} {k : Nat} :
      EffHStepEvalCK σ { c with expr := Expr.abort k } (Expr.abort k)
        { c with expr := Expr.abort k } σ []
  | op {σ : Sigma} {c : EvalConf} {a b : Nat} :
      EffHStepEvalCK σ
        { c with expr := Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)) }
        (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        { c with expr := Expr.val (Val.nat (a + b)) } σ []
  | opAny {σ : Sigma} {c : EvalConf} {v w : Val} :
      EffHStepEvalCK σ { c with expr := Expr.op (Expr.val v) (Expr.val w) }
        (Expr.op (Expr.val v) (Expr.val w))
        { c with expr := Expr.val (Val.nat 0) } σ []
  | letV {σ : Sigma} {c : EvalConf} {x : Var} {v : Val} {b : Expr}
      (hfresh : c.env x = none) :
      EffHStepEvalCK σ { c with expr := Expr.letE x (Expr.val v) b }
        (Expr.letE x (Expr.val v) b)
        { c with expr := b, env := setEnv c.env x (ofVal v) }
        (bindHolders σ x (Effect.holdersOfV v)) []
  | seqV {σ : Sigma} {c : EvalConf} {v : Val} {b : Expr} :
      EffHStepEvalCK σ { c with expr := Expr.seq (Expr.val v) b }
        (Expr.seq (Expr.val v) b) { c with expr := b } σ []
  | callV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} {body : Expr} :
      EffHStepEvalCK σ { c with expr := Expr.call f (Expr.val v) body }
        (Expr.call f (Expr.val v) body) { c with expr := body } σ []
  | freeze {σ : Sigma} {c : EvalConf} {p : Place} :
      EffHStepEvalCK σ { c with expr := Expr.freeze p } (Expr.freeze p)
        { c with expr := Expr.val (Val.valH (freshBid σ)) }
        (addBorrow σ (freshBid σ) p Mode.frozen) [freshBid σ]
  | recover {σ : Sigma} {c : EvalConf} {b : Bid} {l : Nat} :
      EffHStepEvalCK σ { c with expr := Expr.recover (Expr.val (Val.valH b)) }
        (Expr.recover (Expr.val (Val.valH b)))
        { c with expr := Expr.val (Val.loc l) } (ConsumeResult σ [b]) []
  | recoverAny {σ : Sigma} {c : EvalConf} {v : Val}
      (hV : Effect.holdersOfV v = []) :
      EffHStepEvalCK σ { c with expr := Expr.recover (Expr.val v) }
        (Expr.recover (Expr.val v))
        { c with expr := Expr.val (Val.loc 0) } (ConsumeResult σ []) []
  | write {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.write p (Expr.val v) }
        (Expr.write p (Expr.val v))
        { c with expr := Expr.val Val.unit }
        (setHolders σ p (Effect.holdersOfV v)) []
  | alloc {σ : Sigma} {c : EvalConf} {a : Nat} {v : Val} {l : Nat} :
      EffHStepEvalCK σ { c with expr := Expr.alloc a (Expr.val v) }
        (Expr.alloc a (Expr.val v))
        { c with expr := Expr.val (Val.loc l) } σ []
  | drop {σ : Sigma} {c : EvalConf} {p : Place} :
      EffHStepEvalCK σ { c with expr := Expr.drop p } (Expr.drop p)
        { c with expr := Expr.val Val.unit } (clearPlace σ p) []
  | regionV {σ : Sigma} {c : EvalConf} {r : Rgn} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.region r (Expr.val v) }
        (Expr.region r (Expr.val v)) { c with expr := Expr.val v } σ []
  | retV {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.ret (Expr.val v) }
        (Expr.ret (Expr.val v)) { c with expr := Expr.val v } σ []
  | spawnV {σ : Sigma} {c : EvalConf} {f : Nat} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.spawn f (Expr.val v) }
        (Expr.spawn f (Expr.val v))
        { c with expr := Expr.val Val.unit } σ []
  | atomicV {σ : Sigma} {c : EvalConf} {p : Place} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.atomic p (Expr.val v) }
        (Expr.atomic p (Expr.val v)) { c with expr := Expr.val v } σ []
  | unsafeV {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.unsafeE (Expr.val v) }
        (Expr.unsafeE (Expr.val v)) { c with expr := Expr.val v } σ []
  | derefV {σ : Sigma} {c : EvalConf} {l : Nat} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.derefRaw (Expr.val (Val.loc l)) }
        (Expr.derefRaw (Expr.val (Val.loc l)))
        { c with expr := Expr.val v } σ []
  | derefAny {σ : Sigma} {c : EvalConf} {v : Val} :
      EffHStepEvalCK σ { c with expr := Expr.derefRaw (Expr.val v) }
        (Expr.derefRaw (Expr.val v))
        { c with expr := Expr.val (Val.nat 0) } σ []
  | borrowEnter {σ : Sigma} {c : EvalConf} {p : Place} {x : Var} {e : Expr}
      (hfresh : c.env x = none) :
      EffHStepEvalCK σ { c with expr := Expr.borrow p x e } (Expr.borrow p x e)
        { c with expr := e, env := setEnv c.env x (RVal.refH 0), state := State.mk (c.state.borrow + 1) }
        (addBorrow σ 0 p Mode.mut) []
  | borrowExit {σ : Sigma} {c : EvalConf} {v : Val} {n : Nat} :
      EffHStepEvalCK σ { c with expr := Expr.val v, state := State.mk (n + 1) }
        (Expr.val v) { c with expr := Expr.val v, state := State.mk n } σ []
  | abortBorrow {σ : Sigma} {c : EvalConf} {k : Nat} {n : Nat} :
      EffHStepEvalCK σ { c with expr := Expr.abort k, state := State.mk (n + 1) }
        (Expr.abort k) { c with expr := Expr.abort k, state := State.mk n } σ []
  -- Context rules: thread the whole output configuration `c'`.
  | opL {σ σ' : Sigma} {c : EvalConf} {a b : Expr} {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := a } a c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.op a b } (Expr.op a b)
        { c' with expr := Expr.op c'.expr b } σ' A
  | opR {σ σ' : Sigma} {c : EvalConf} {a b : Expr} {c' : EvalConf} {A : List Bid}
      (hv : IsVal a)
      (h : EffHStepEvalCK σ { c with expr := b } b c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.op a b } (Expr.op a b)
        { c' with expr := Expr.op a c'.expr } σ' A
  | letB {σ σ' : Sigma} {c : EvalConf} {x : Var} {a b : Expr}
      {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := a } a c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.letE x a b } (Expr.letE x a b)
        { c' with expr := Expr.letE x c'.expr b } σ' A
  | writeB {σ σ' : Sigma} {c : EvalConf} {p : Place} {e : Expr}
      {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.write p e } (Expr.write p e)
        { c' with expr := Expr.write p c'.expr } σ' A
  | seqL {σ σ' : Sigma} {c : EvalConf} {a b : Expr} {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := a } a c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.seq a b } (Expr.seq a b)
        { c' with expr := Expr.seq c'.expr b } σ' A
  | allocB {σ σ' : Sigma} {c : EvalConf} {a : Nat} {e : Expr}
      {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.alloc a e } (Expr.alloc a e)
        { c' with expr := Expr.alloc a c'.expr } σ' A
  | regionB {σ σ' : Sigma} {c : EvalConf} {r : Rgn} {e : Expr}
      {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.region r e } (Expr.region r e)
        { c' with expr := Expr.region r c'.expr } σ' A
  | recoverB {σ σ' : Sigma} {c : EvalConf} {e : Expr} {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.recover e } (Expr.recover e)
        { c' with expr := Expr.recover c'.expr } σ' A
  | callB {σ σ' : Sigma} {c : EvalConf} {f : Nat} {a body : Expr}
      {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := a } a c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.call f a body } (Expr.call f a body)
        { c' with expr := Expr.call f c'.expr body } σ' A
  | retB {σ σ' : Sigma} {c : EvalConf} {e : Expr} {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.ret e } (Expr.ret e)
        { c' with expr := Expr.ret c'.expr } σ' A
  | spawnB {σ σ' : Sigma} {c : EvalConf} {f : Nat} {e : Expr}
      {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.spawn f e } (Expr.spawn f e)
        { c' with expr := Expr.spawn f c'.expr } σ' A
  | atomicB {σ σ' : Sigma} {c : EvalConf} {p : Place} {e : Expr}
      {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.atomic p e } (Expr.atomic p e)
        { c' with expr := Expr.atomic p c'.expr } σ' A
  | unsafeB {σ σ' : Sigma} {c : EvalConf} {e : Expr} {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.unsafeE e } (Expr.unsafeE e)
        { c' with expr := Expr.unsafeE c'.expr } σ' A
  | derefB {σ σ' : Sigma} {c : EvalConf} {e : Expr} {c' : EvalConf} {A : List Bid}
      (h : EffHStepEvalCK σ { c with expr := e } e c' σ' A) :
      EffHStepEvalCK σ { c with expr := Expr.derefRaw e } (Expr.derefRaw e)
        { c' with expr := Expr.derefRaw c'.expr } σ' A

/-- `EffHStepEvalCK` never changes the heap. -/
theorem EffHStepEvalCK.heap_same {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (h : EffHStepEvalCK σ c e c' σ' A) : c'.heap = c.heap := by
  induction h with
  | varV _ => rfl
  | moveV _ => rfl
  | readV _ => rfl
  | val => rfl
  | abort => rfl
  | op => rfl
  | opAny => rfl
  | letV => rfl
  | seqV => rfl
  | callV => rfl
  | freeze => rfl
  | recover => rfl
  | recoverAny _ => rfl
  | write => rfl
  | alloc => rfl
  | drop => rfl
  | regionV => rfl
  | retV => rfl
  | spawnV => rfl
  | atomicV => rfl
  | unsafeV => rfl
  | derefV => rfl
  | derefAny => rfl
  | borrowEnter => rfl
  | borrowExit => rfl
  | abortBorrow => rfl
  | opL _ ih => exact ih
  | opR _ _ ih => exact ih
  | letB _ ih => exact ih
  | writeB _ ih => exact ih
  | seqL _ ih => exact ih
  | allocB _ ih => exact ih
  | regionB _ ih => exact ih
  | recoverB _ ih => exact ih
  | callB _ ih => exact ih
  | retB _ ih => exact ih
  | spawnB _ ih => exact ih
  | atomicB _ ih => exact ih
  | unsafeB _ ih => exact ih
  | derefB _ ih => exact ih

/-- Every `EffHStepEvalCK` step only extends the environment. -/
theorem EffHStepEvalCK.env_ext {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (h : EffHStepEvalCK σ c e c' σ' A) :
    EnvExtends c.env c'.env := by
  induction h with
  | varV _ => exact EnvExtends.refl _
  | moveV _ => exact EnvExtends.refl _
  | readV _ => exact EnvExtends.refl _
  | val => exact EnvExtends.refl _
  | abort => exact EnvExtends.refl _
  | op => exact EnvExtends.refl _
  | opAny => exact EnvExtends.refl _
  | letV hfresh => exact EnvExtends.setEnv_self hfresh
  | seqV => exact EnvExtends.refl _
  | callV => exact EnvExtends.refl _
  | freeze => exact EnvExtends.refl _
  | recover => exact EnvExtends.refl _
  | recoverAny _ => exact EnvExtends.refl _
  | write => exact EnvExtends.refl _
  | alloc => exact EnvExtends.refl _
  | drop => exact EnvExtends.refl _
  | regionV => exact EnvExtends.refl _
  | retV => exact EnvExtends.refl _
  | spawnV => exact EnvExtends.refl _
  | atomicV => exact EnvExtends.refl _
  | unsafeV => exact EnvExtends.refl _
  | derefV => exact EnvExtends.refl _
  | derefAny => exact EnvExtends.refl _
  | borrowEnter hfresh => exact EnvExtends.setEnv_self hfresh
  | borrowExit => exact EnvExtends.refl _
  | abortBorrow => exact EnvExtends.refl _
  | opL _ ih => exact ih
  | opR _ _ ih => exact ih
  | letB _ ih => exact ih
  | writeB _ ih => exact ih
  | seqL _ ih => exact ih
  | allocB _ ih => exact ih
  | regionB _ ih => exact ih
  | recoverB _ ih => exact ih
  | callB _ ih => exact ih
  | retB _ ih => exact ih
  | spawnB _ ih => exact ih
  | atomicB _ ih => exact ih
  | unsafeB _ ih => exact ih
  | derefB _ ih => exact ih

/-- Every `EffHStepEvalCK` step leaves `Γ` unchanged. -/
theorem EffHStepEvalCK.gamma_same {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (h : EffHStepEvalCK σ c e c' σ' A) : σ'.gamma = σ.gamma := by
  induction h with
  | varV _ => rfl
  | moveV _ => rfl
  | readV _ => rfl
  | val => rfl
  | abort => rfl
  | op => rfl
  | opAny => rfl
  | letV _ => rfl
  | seqV => rfl
  | callV => rfl
  | freeze => rfl
  | recover => rfl
  | recoverAny _ => rfl
  | write => rfl
  | alloc => rfl
  | drop => rfl
  | regionV => rfl
  | retV => rfl
  | spawnV => rfl
  | atomicV => rfl
  | unsafeV => rfl
  | derefV => rfl
  | derefAny => rfl
  | borrowEnter _ => rfl
  | borrowExit => rfl
  | abortBorrow => rfl
  | opL _ ih => exact ih
  | opR _ _ ih => exact ih
  | letB _ ih => exact ih
  | writeB _ ih => exact ih
  | seqL _ ih => exact ih
  | allocB _ ih => exact ih
  | regionB _ ih => exact ih
  | recoverB _ ih => exact ih
  | callB _ ih => exact ih
  | retB _ ih => exact ih
  | spawnB _ ih => exact ih
  | atomicB _ ih => exact ih
  | unsafeB _ ih => exact ih
  | derefB _ ih => exact ih

end LSys
