/-
  LSys/WTK.lean

  Per-rule continuation-passing static judgement.

  `WTK σ e k σ'` types `e` under continuation `k` and carries the static
  effect `σ → σ'`.  There is no delegation to the input-only `WT`; every
  expression constructor has its own rule, and `region` checks `NoEscape`
  on both the input and output states.
-/

import LSys.Effect
import LSys.Adequacy
import LSys.StepEval

namespace LSys

set_option linter.unusedVariables false

inductive K where
  | halt
  | ctx (C : Ctx) (k : K)

def plugK : K → Expr → Expr
  | K.halt, e => e
  | K.ctx C k, e => plugK k (plug C e)

inductive WTK : Sigma → Expr → K → Sigma → Prop where
  | val {σ v k} : WTK σ (Expr.val v) k σ
  | var {σ x k} (h : (lookupPlace σ.gamma (varPlace x)).isSome = true) :
      WTK σ (Expr.var x) k σ
  | abort {σ k0 k} : WTK σ (Expr.abort k0) k σ

  | op {σ a b k σ₁ σ₂}
      (ha : WTK σ a (K.ctx (Ctx.opL Ctx.hole b) k) σ₁)
      (hb : WTK σ₁ b k σ₂) :
      WTK σ (Expr.op a b) k σ₂

  | letE {σ x a b k σ₁ σ₂}
      (ha : WTK σ a (K.ctx (Ctx.letB x Ctx.hole b) k) σ₁)
      (hb : WTK σ₁ b k σ₂) :
      WTK σ (Expr.letE x a b) k σ₂

  | seq {σ a b k σ₁ σ₂}
      (ha : WTK σ a (K.ctx (Ctx.seqL Ctx.hole b) k) σ₁)
      (hb : WTK σ₁ b k σ₂) :
      WTK σ (Expr.seq a b) k σ₂

  | write {σ p e k σ'} (hm : Writable σ p)
      (h : WTK σ e (K.ctx (Ctx.writeB p Ctx.hole) k) σ') :
      WTK σ (Expr.write p e) k σ'

  | alloc {σ a e k σ'} (hcap : CAP_ALLOC_OK σ)
      (h : WTK σ e (K.ctx (Ctx.allocB a Ctx.hole) k) σ') :
      WTK σ (Expr.alloc a e) k σ'

  | region {σ R e k σ₁}
      (h : WTK σ e (K.ctx (Ctx.regionB R Ctx.hole) k) σ₁)
      (hsafe : Effect.RegionSafe σ R e)
      (hno_out : NoEscape σ₁ R) :
      WTK σ (Expr.region R e) k σ₁

  | freeze {σ p k b} (hm : modeOf σ p = some Mode.uniq)
      (hl : live σ p = []) :
      WTK σ (Expr.freeze p) k (addBorrow σ b p Mode.frozen)

  | recover {σ b p k}
      (ht : targetOf σ b = some p)
      (hok : RecoverOk (ConsumeResult σ [b]) p) :
      WTK σ (Expr.recover (Expr.val (Val.valH b))) k (ConsumeResult σ [b])

  | borrow {σ p x e k σ'} (hm : modeOf σ p = some Mode.uniq)
      (h : WTK (addBorrow σ 0 p Mode.mut) e k σ') :
      WTK σ (Expr.borrow p x e) k σ'

  | drop {σ p k} (hm : modeOf σ p = some Mode.uniq) :
      WTK σ (Expr.drop p) k (clearPlace σ p)

  | call {σ f a body k σ₁ σ₂} (hf : CAPS_OK σ f)
      (ha : WTK σ a (K.ctx (Ctx.callB f Ctx.hole body) k) σ₁)
      (hb : WTK σ₁ body k σ₂) :
      WTK σ (Expr.call f a body) k σ₂

  | ret {σ e k σ'}
      (h : WTK σ e (K.ctx (Ctx.retB Ctx.hole) k) σ') :
      WTK σ (Expr.ret e) k σ'

  | spawn {σ f e k σ'} (hf : CAPS_OK σ f)
      (h : WTK σ e (K.ctx (Ctx.spawnB f Ctx.hole) k) σ') :
      WTK σ (Expr.spawn f e) k σ'

  | atomic {σ p e k σ'} (hm : modeOf σ p = some Mode.atom)
      (h : WTK σ e (K.ctx (Ctx.atomicB p Ctx.hole) k) σ') :
      WTK σ (Expr.atomic p e) k σ'

  | unsafeE {σ e k σ'}
      (h : WTK σ e (K.ctx (Ctx.unsafeB Ctx.hole) k) σ') :
      WTK σ (Expr.unsafeE e) k σ'

  | deref {σ e k σ'}
      (h : WTK σ e (K.ctx (Ctx.derefB Ctx.hole) k) σ') :
      WTK σ (Expr.derefRaw e) k σ'

  | move {σ p k} (hm : modeOf σ p = some Mode.uniq) :
      WTK σ (Expr.move p) k (clearPlace σ p)

  | read {σ p k}
      (hm : modeOf σ p = some Mode.frozen ∨ modeOf σ p = some Mode.mut) :
      WTK σ (Expr.read p) k (addBorrow σ 0 p Mode.frozen)

end LSys
