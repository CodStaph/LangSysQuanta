/-
  LSys/StepC.lean

  **Value-consistent raw steps** and their bridge to `EffHStepEvalCK` (§8.3
  step 7).

  The raw `Step` relation is syntax-level: `varV`, `readV`, `moveV` and
  `derefV` invent an *arbitrary* value, which is why the naive bridge

    `Step e e' → ∃ c' σ' A', EffHStepEvalCK σ c e c' σ' A' ∧ c'.expr = e'`

  is false (`StepBridge.not_match_step_naive`: a raw `var x` step can produce
  any value, while a configuration step must read `c.env x`).  `StepC` keeps
  only the steps that are **consistent with the configuration**:

  * `varV`/`readV`/`moveV` take their value from `c.env`/`c.heap`;
  * `derefV` follows the `locPlace` link (`heap [l]`); `derefAny` is restricted
    to non-location values;
  * `letV`/`borrowEnter` require the bound variable to be fresh;
  * `recoverAny` requires the value to carry no handle;
  * congruence contexts exclude `borrowB`: the body of a `borrow` is entered by
    the `borrowEnter` redex, not by a congruence step.

  Then `StepC.toCK` realises every `StepC` step as an `EffHStepEvalCK` step
  producing the same expression, and `StepC.toStep` shows every `StepC` step is
  a raw `Step`.  `Step.borrowExit`/`Step.abortBorrow` only touch the borrow
  frame; they are bridged directly by `borrowExit_bridge`/`abortBorrow_bridge`.
-/

import LSys.EffHCK

namespace LSys

set_option linter.unusedVariables false

/-- The witness of a configuration step: a resulting configuration (its `expr`
    field pinned to the raw step's result), the static state and the handles. -/
def CKStepOut (σ : Sigma) (c : EvalConf) (e e' : Expr) : Prop :=
  ∃ (c' : EvalConf) (σ' : Sigma) (A' : List Bid),
    EffHStepEvalCK σ { c with expr := e } e c' σ' A' ∧ c'.expr = e'

/-- Value-consistent raw steps relative to the configuration `c`. -/
inductive StepC (c : EvalConf) : Expr → Expr → Prop where
  -- value projection
  | varV {x : Var} {v : RVal} (h : c.env x = some v) :
      StepC c (Expr.var x) (Expr.val (toVal v))
  | readV {p : Place} {v : RVal} (h : c.heap p = some v) :
      StepC c (Expr.read p) (Expr.val (toVal v))
  | moveV {p : Place} {v : RVal} (h : c.heap p = some v) :
      StepC c (Expr.move p) (Expr.val (toVal v))
  | derefV {l : Loc} {v : RVal} (h : c.heap (locPlace l) = some v) :
      StepC c (Expr.derefRaw (Expr.val (Val.loc l))) (Expr.val (toVal v))
  | derefAny {v : Val} (hv : ∀ l : Loc, v ≠ Val.loc l) :
      StepC c (Expr.derefRaw (Expr.val v)) (Expr.val (Val.nat 0))
  -- deterministic redexes
  | op {a b : Nat} :
      StepC c (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        (Expr.val (Val.nat (a + b)))
  | opAny {v w : Val} :
      StepC c (Expr.op (Expr.val v) (Expr.val w)) (Expr.val (Val.nat 0))
  | letV {x : Var} {v : Val} {e : Expr} (hfresh : c.env x = none) :
      StepC c (Expr.letE x (Expr.val v) e) e
  | writeV {p : Place} {v : Val} :
      StepC c (Expr.write p (Expr.val v)) (Expr.val Val.unit)
  | seqV {v : Val} {e : Expr} : StepC c (Expr.seq (Expr.val v) e) e
  | regionV {r : Rgn} {v : Val} :
      StepC c (Expr.region r (Expr.val v)) (Expr.val v)
  | allocV {a : Nat} {v : Val} {l : Loc} :
      StepC c (Expr.alloc a (Expr.val v)) (Expr.val (Val.loc l))
  | recoverV {b : Bid} {l : Loc} :
      StepC c (Expr.recover (Expr.val (Val.valH b))) (Expr.val (Val.loc l))
  | recoverAny {v : Val} (hV : Effect.holdersOfV v = []) :
      StepC c (Expr.recover (Expr.val v)) (Expr.val (Val.loc 0))
  | dropV {p : Place} : StepC c (Expr.drop p) (Expr.val Val.unit)
  | callV {f : Nat} {v : Val} {body : Expr} :
      StepC c (Expr.call f (Expr.val v) body) body
  | retV {v : Val} : StepC c (Expr.ret (Expr.val v)) (Expr.val v)
  | spawnV {f : Nat} {v : Val} :
      StepC c (Expr.spawn f (Expr.val v)) (Expr.val Val.unit)
  | atomicV {p : Place} {v : Val} :
      StepC c (Expr.atomic p (Expr.val v)) (Expr.val v)
  | unsafeV {v : Val} : StepC c (Expr.unsafeE (Expr.val v)) (Expr.val v)
  | borrowEnter {p : Place} {x : Var} {e : Expr} (hfresh : c.env x = none) :
      StepC c (Expr.borrow p x e) e
  -- congruence contexts (prefix-aware; `borrowB` excluded).  The "other side"
  -- of each context is an explicit argument so proofs can name it.
  | opL (b : Expr) {a a' : Expr} (h : StepC c a a') :
      StepC c (Expr.op a b) (Expr.op a' b)
  | opR (a : Expr) {b b' : Expr} (hv : IsVal a) (h : StepC c b b') :
      StepC c (Expr.op a b) (Expr.op a b')
  | letB (x : Var) (b : Expr) {a a' : Expr} (h : StepC c a a') :
      StepC c (Expr.letE x a b) (Expr.letE x a' b)
  | writeB (p : Place) {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.write p e) (Expr.write p e')
  | seqL (b : Expr) {a a' : Expr} (h : StepC c a a') :
      StepC c (Expr.seq a b) (Expr.seq a' b)
  | allocB (a : Nat) {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.alloc a e) (Expr.alloc a e')
  | regionB (r : Rgn) {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.region r e) (Expr.region r e')
  | recoverB {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.recover e) (Expr.recover e')
  | callB (f : Nat) (body : Expr) {a a' : Expr} (h : StepC c a a') :
      StepC c (Expr.call f a body) (Expr.call f a' body)
  | retB {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.ret e) (Expr.ret e')
  | spawnB (f : Nat) {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.spawn f e) (Expr.spawn f e')
  | atomicB (p : Place) {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.atomic p e) (Expr.atomic p e')
  | unsafeB {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.unsafeE e) (Expr.unsafeE e')
  | derefB {e e' : Expr} (h : StepC c e e') :
      StepC c (Expr.derefRaw e) (Expr.derefRaw e')
  -- abort propagation, matching `EffHStepEvalCK.abort*`
  | abortOpR (a : Expr) (k : Nat) (hv : IsVal a) :
      StepC c (Expr.op a (Expr.abort k)) (Expr.abort k)
  | abortAlloc (a : Nat) (k : Nat) :
      StepC c (Expr.alloc a (Expr.abort k)) (Expr.abort k)
  | abortRegion (r : Rgn) (k : Nat) :
      StepC c (Expr.region r (Expr.abort k)) (Expr.abort k)
  | abortRet (k : Nat) : StepC c (Expr.ret (Expr.abort k)) (Expr.abort k)
  | abortSpawn (f : Nat) (k : Nat) :
      StepC c (Expr.spawn f (Expr.abort k)) (Expr.abort k)
  | abortAtomic (p : Place) (k : Nat) :
      StepC c (Expr.atomic p (Expr.abort k)) (Expr.abort k)
  | abortUnsafe (k : Nat) :
      StepC c (Expr.unsafeE (Expr.abort k)) (Expr.abort k)
  | abortDeref (k : Nat) :
      StepC c (Expr.derefRaw (Expr.abort k)) (Expr.abort k)
  | abortOpL (b : Expr) (k : Nat) :
      StepC c (Expr.op (Expr.abort k) b) (Expr.abort k)
  | abortLetB (x : Var) (b : Expr) (k : Nat) :
      StepC c (Expr.letE x (Expr.abort k) b) (Expr.abort k)
  | abortSeqL (b : Expr) (k : Nat) :
      StepC c (Expr.seq (Expr.abort k) b) (Expr.abort k)
  | abortCallB (f : Nat) (body : Expr) (k : Nat) :
      StepC c (Expr.call f (Expr.abort k) body) (Expr.abort k)
  | abortWriteB (p : Place) (k : Nat) :
      StepC c (Expr.write p (Expr.abort k)) (Expr.abort k)
  | abortRecoverB (k : Nat) :
      StepC c (Expr.recover (Expr.abort k)) (Expr.abort k)

/-! ## Bridge: value-consistent raw step ⟹ configuration step -/

/-- Every value-consistent raw step is realised by an `EffHStepEvalCK` step
    that produces the same expression. -/
theorem StepC.toCK {c : EvalConf} {e e' : Expr} (h : StepC c e e') :
    ∀ {σ : Sigma}, CKStepOut σ c e e' := by
  induction h with
  | varV h => exact ⟨_, _, _, EffHStepEvalCK.varV h, rfl⟩
  | readV h => exact ⟨_, _, _, EffHStepEvalCK.readV h, rfl⟩
  | moveV h => exact ⟨_, _, _, EffHStepEvalCK.moveV h, rfl⟩
  | derefV h => exact ⟨_, _, _, EffHStepEvalCK.derefV h, rfl⟩
  | derefAny hv => exact ⟨_, _, _, EffHStepEvalCK.derefAny hv, rfl⟩
  | op => exact ⟨_, _, _, EffHStepEvalCK.op, rfl⟩
  | opAny => exact ⟨_, _, _, EffHStepEvalCK.opAny, rfl⟩
  | letV hfresh => exact ⟨_, _, _, EffHStepEvalCK.letV hfresh, rfl⟩
  | writeV => exact ⟨_, _, _, EffHStepEvalCK.write, rfl⟩
  | seqV => exact ⟨_, _, _, EffHStepEvalCK.seqV, rfl⟩
  | regionV => exact ⟨_, _, _, EffHStepEvalCK.regionV, rfl⟩
  | allocV => exact ⟨_, _, _, EffHStepEvalCK.alloc, rfl⟩
  | recoverV => exact ⟨_, _, _, EffHStepEvalCK.recover, rfl⟩
  | recoverAny hV => exact ⟨_, _, _, EffHStepEvalCK.recoverAny hV, rfl⟩
  | dropV => exact ⟨_, _, _, EffHStepEvalCK.drop, rfl⟩
  | callV => exact ⟨_, _, _, EffHStepEvalCK.callV, rfl⟩
  | retV => exact ⟨_, _, _, EffHStepEvalCK.retV, rfl⟩
  | spawnV => exact ⟨_, _, _, EffHStepEvalCK.spawnV, rfl⟩
  | atomicV => exact ⟨_, _, _, EffHStepEvalCK.atomicV, rfl⟩
  | unsafeV => exact ⟨_, _, _, EffHStepEvalCK.unsafeV, rfl⟩
  | borrowEnter hfresh => exact ⟨_, _, _, EffHStepEvalCK.borrowEnter hfresh, rfl⟩
  | abortOpR _ _ hv => exact ⟨_, _, _, EffHStepEvalCK.abortOpR hv, rfl⟩
  | abortAlloc _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortAlloc, rfl⟩
  | abortRegion _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortRegion, rfl⟩
  | abortRet _ => exact ⟨_, _, _, EffHStepEvalCK.abortRet, rfl⟩
  | abortSpawn _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortSpawn, rfl⟩
  | abortAtomic _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortAtomic, rfl⟩
  | abortUnsafe _ => exact ⟨_, _, _, EffHStepEvalCK.abortUnsafe, rfl⟩
  | abortDeref _ => exact ⟨_, _, _, EffHStepEvalCK.abortDeref, rfl⟩
  | abortOpL _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortOpL, rfl⟩
  | abortLetB _ _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortLetB, rfl⟩
  | abortSeqL _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortSeqL, rfl⟩
  | abortCallB _ _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortCallB, rfl⟩
  | abortWriteB _ _ => exact ⟨_, _, _, EffHStepEvalCK.abortWriteB, rfl⟩
  | abortRecoverB _ => exact ⟨_, _, _, EffHStepEvalCK.abortRecoverB, rfl⟩
  -- congruence contexts: step the sub-expression, then rebuild the context
  | opL _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.opL hstep, by rw [hexpr]⟩
  | opR _ hv h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.opR hv hstep, by rw [hexpr]⟩
  | letB _ _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.letB hstep, by rw [hexpr]⟩
  | writeB _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.writeB hstep, by rw [hexpr]⟩
  | seqL _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.seqL hstep, by rw [hexpr]⟩
  | allocB _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.allocB hstep, by rw [hexpr]⟩
  | regionB _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.regionB hstep, by rw [hexpr]⟩
  | recoverB h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.recoverB hstep, by rw [hexpr]⟩
  | callB _ _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.callB hstep, by rw [hexpr]⟩
  | retB h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.retB hstep, by rw [hexpr]⟩
  | spawnB _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.spawnB hstep, by rw [hexpr]⟩
  | atomicB _ h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.atomicB hstep, by rw [hexpr]⟩
  | unsafeB h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.unsafeB hstep, by rw [hexpr]⟩
  | derefB h ih =>
      intro σ
      match ih (σ := σ) with
      | ⟨c1, σ1, A1, hstep, hexpr⟩ =>
          exact ⟨_, σ1, A1, EffHStepEvalCK.derefB hstep, by rw [hexpr]⟩

/-! ## Bridge: value-consistent raw step ⟹ raw `Step` -/

/-- Every value-consistent raw step is a raw `Step`, evaluated from the
    configuration's borrow frame. -/
theorem StepC.toStep {c : EvalConf} {e e' : Expr} (h : StepC c e e') :
    ∃ s' : State, Step e c.state e' s' := by
  induction h with
  | varV _ => exact ⟨_, Step.varV⟩
  | readV _ => exact ⟨_, Step.readV⟩
  | moveV _ => exact ⟨_, Step.moveV⟩
  | derefV _ => exact ⟨_, Step.derefV⟩
  | derefAny _ => exact ⟨_, Step.derefAny⟩
  | op => exact ⟨_, Step.op⟩
  | opAny => exact ⟨_, Step.opAny⟩
  | letV _ => exact ⟨_, Step.letV⟩
  | writeV => exact ⟨_, Step.writeV⟩
  | seqV => exact ⟨_, Step.seqV⟩
  | regionV => exact ⟨_, Step.regionV⟩
  | allocV => exact ⟨_, Step.allocV⟩
  | recoverV => exact ⟨_, Step.recoverV⟩
  | recoverAny _ => exact ⟨_, Step.recoverAny⟩
  | dropV => exact ⟨_, Step.dropV⟩
  | callV => exact ⟨_, Step.callV⟩
  | retV => exact ⟨_, Step.retV⟩
  | spawnV => exact ⟨_, Step.spawnV⟩
  | atomicV => exact ⟨_, Step.atomicV⟩
  | unsafeV => exact ⟨_, Step.unsafeV⟩
  | borrowEnter _ => exact ⟨_, Step.borrowEnter⟩
  | abortOpR a k _ =>
      exact ⟨_, Step.abortCtx (C := Ctx.opR a Ctx.hole) (by intro h; cases h)⟩
  | abortAlloc a k =>
      exact ⟨_, Step.abortCtx (C := Ctx.allocB a Ctx.hole) (by intro h; cases h)⟩
  | abortRegion r k =>
      exact ⟨_, Step.abortCtx (C := Ctx.regionB r Ctx.hole) (by intro h; cases h)⟩
  | abortRet k =>
      exact ⟨_, Step.abortCtx (C := Ctx.retB Ctx.hole) (by intro h; cases h)⟩
  | abortSpawn f k =>
      exact ⟨_, Step.abortCtx (C := Ctx.spawnB f Ctx.hole) (by intro h; cases h)⟩
  | abortAtomic p k =>
      exact ⟨_, Step.abortCtx (C := Ctx.atomicB p Ctx.hole) (by intro h; cases h)⟩
  | abortUnsafe k =>
      exact ⟨_, Step.abortCtx (C := Ctx.unsafeB Ctx.hole) (by intro h; cases h)⟩
  | abortDeref k =>
      exact ⟨_, Step.abortCtx (C := Ctx.derefB Ctx.hole) (by intro h; cases h)⟩
  | abortOpL b k =>
      exact ⟨_, Step.abortCtx (C := Ctx.opL Ctx.hole b) (by intro h; cases h)⟩
  | abortLetB x b k =>
      exact ⟨_, Step.abortCtx (C := Ctx.letB x Ctx.hole b) (by intro h; cases h)⟩
  | abortSeqL b k =>
      exact ⟨_, Step.abortCtx (C := Ctx.seqL Ctx.hole b) (by intro h; cases h)⟩
  | abortCallB f body k =>
      exact ⟨_, Step.abortCtx (C := Ctx.callB f Ctx.hole body) (by intro h; cases h)⟩
  | abortWriteB p k =>
      exact ⟨_, Step.abortCtx (C := Ctx.writeB p Ctx.hole) (by intro h; cases h)⟩
  | abortRecoverB k =>
      exact ⟨_, Step.abortCtx (C := Ctx.recoverB Ctx.hole) (by intro h; cases h)⟩
  | opL b h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.opL Ctx.hole b) hs⟩
  | opR a _ h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.opR a Ctx.hole) hs⟩
  | letB x b h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.letB x Ctx.hole b) hs⟩
  | writeB p h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.writeB p Ctx.hole) hs⟩
  | seqL b h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.seqL Ctx.hole b) hs⟩
  | allocB a h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.allocB a Ctx.hole) hs⟩
  | regionB r h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.regionB r Ctx.hole) hs⟩
  | recoverB h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.recoverB Ctx.hole) hs⟩
  | callB f body h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.callB f Ctx.hole body) hs⟩
  | retB h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.retB Ctx.hole) hs⟩
  | spawnB f h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.spawnB f Ctx.hole) hs⟩
  | atomicB p h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.atomicB p Ctx.hole) hs⟩
  | unsafeB h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.unsafeB Ctx.hole) hs⟩
  | derefB h ih =>
      cases ih with
      | intro s' hs => exact ⟨s', Step.ctx (C := Ctx.derefB Ctx.hole) hs⟩

/-! ## Borrow-frame steps (bridged directly) -/

/-- `Step.borrowExit` is realised by `EffHStepEvalCK.borrowExit`. -/
theorem borrowExit_bridge {σ : Sigma} {c₀ : EvalConf} {v : Val} {n : Nat} :
    CKStepOut σ { c₀ with state := State.mk (n + 1) } (Expr.val v) (Expr.val v) :=
  ⟨_, σ, [], EffHStepEvalCK.borrowExit, rfl⟩

/-- `Step.abortBorrow` is realised by `EffHStepEvalCK.abortBorrow`. -/
theorem abortBorrow_bridge {σ : Sigma} {c₀ : EvalConf} {k : Nat} {n : Nat} :
    CKStepOut σ { c₀ with state := State.mk (n + 1) } (Expr.abort k) (Expr.abort k) :=
  ⟨_, σ, [], EffHStepEvalCK.abortBorrow, rfl⟩

/-- `Step.freezeV` invents an arbitrary handle; the value-consistent one is
    pinned by the static state (`freshBid σ`). -/
theorem freeze_bridge {σ : Sigma} {c₀ : EvalConf} {p : Place} :
    CKStepOut σ c₀ (Expr.freeze p) (Expr.val (Val.valH (freshBid σ))) :=
  ⟨_, _, _, EffHStepEvalCK.freeze, rfl⟩

end LSys
