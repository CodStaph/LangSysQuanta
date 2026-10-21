/-
  LSys/StepEval.lean

  Prefix-aware execution steps.

  `LSys.Term.Step` is the total raw relation (its `ctx` rule ignores
  evaluation order).  `StepEval` keeps the raw redex rules but replaces the
  generic context rule with position-aware rules:

    opL : step the left operand
    opR : step the right operand, only when the left is a value
    letB : step the bound expression
    seqL : step the first statement
    ...

  The raw `Step` is retained for L-Term/L-Progress; `StepEval` is the relation
  used by effect/context reasoning.
-/

import LSys.Term

namespace LSys

set_option linter.unusedVariables false

def IsVal : Expr → Prop
  | Expr.val _ => True
  | _ => False

def isRedex : Expr → Bool
  | Expr.val _ => true
  | Expr.var _ => true
  | Expr.abort _ => true
  | Expr.op (Expr.val _) (Expr.val _) => true
  | Expr.letE _ (Expr.val _) _ => true
  | Expr.move _ => true
  | Expr.read _ => true
  | Expr.write _ (Expr.val _) => true
  | Expr.seq (Expr.val _) _ => true
  | Expr.region _ (Expr.val _) => true
  | Expr.alloc _ (Expr.val _) => true
  | Expr.freeze _ => true
  | Expr.recover (Expr.val _) => true
  | Expr.borrow _ _ _ => true
  | Expr.drop _ => true
  | Expr.call _ (Expr.val _) _ => true
  | Expr.ret (Expr.val _) => true
  | Expr.spawn _ (Expr.val _) => true
  | Expr.atomic _ (Expr.val _) => true
  | Expr.unsafeE (Expr.val _) => true
  | Expr.derefRaw (Expr.val _) => true
  | _ => false

/-- Prefix-aware execution step. -/
inductive StepEval : Expr → State → Expr → State → Prop where
  | base {e s e' s'} (h : Step e s e' s') (hr : isRedex e = true) :
      StepEval e s e' s'
  | opL {a b s a' s'} (h : StepEval a s a' s') :
      StepEval (Expr.op a b) s (Expr.op a' b) s'
  | opR {a b s b' s'} (hv : IsVal a) (h : StepEval b s b' s') :
      StepEval (Expr.op a b) s (Expr.op a b') s'
  | letB {x a b s a' s'} (h : StepEval a s a' s') :
      StepEval (Expr.letE x a b) s (Expr.letE x a' b) s'
  | writeB {p e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.write p e) s (Expr.write p e') s'
  | seqL {a b s a' s'} (h : StepEval a s a' s') :
      StepEval (Expr.seq a b) s (Expr.seq a' b) s'
  | allocB {a e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.alloc a e) s (Expr.alloc a e') s'
  | regionB {r e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.region r e) s (Expr.region r e') s'
  | recoverB {e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.recover e) s (Expr.recover e') s'
  | callB {f a body s a' s'} (h : StepEval a s a' s') :
      StepEval (Expr.call f a body) s (Expr.call f a' body) s'
  | retB {e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.ret e) s (Expr.ret e') s'
  | spawnB {f e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.spawn f e) s (Expr.spawn f e') s'
  | atomicB {p e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.atomic p e) s (Expr.atomic p e') s'
  | unsafeB {e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.unsafeE e) s (Expr.unsafeE e') s'
  | derefB {e s e' s'} (h : StepEval e s e' s') :
      StepEval (Expr.derefRaw e) s (Expr.derefRaw e') s'
  | abortCtx {C k s} (hnot : C ≠ Ctx.hole) :
      StepEval (plug C (Expr.abort k)) s (Expr.abort k) s

/-- `StepEval` is a refinement of the raw `Step`. -/
theorem StepEval.toStep {e s e' s'} (h : StepEval e s e' s') : Step e s e' s' := by
  induction h with
  | base h hr => exact h
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
  | abortCtx hnot => exact Step.abortCtx hnot

theorem stepEval_decreases {e s e' s'} (h : StepEval e s e' s') :
    Mlt (M e' s') (M e s) :=
  step_decreases (StepEval.toStep h)

end LSys
