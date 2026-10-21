/-
  LSys/EffHC.lean

  Configuration-relative effects **with handles**.

  `EffH`/`EffHStepEvalC` are syntax-level: they cannot know the handles of a
  value bound to a variable, so the fixed-output composition with `EffH` is
  false (`EffHCounterexample.not_effHStepEvalC_eff_compose`).

  `EffHC env heap e σ σ' A` resolves `var`/`move`/`read` from `env`/`heap`, so it
  *does* know the actual handles, and the fixed-output composition becomes
  provable (with `c.env`/`c.heap` as the environment):

    EffHStepEvalC σ c e c' σ' A →
    EffHC c.env c.heap c'.expr σ' σ'' B → EffHC c.env c.heap e σ σ'' B

  Fresh bids are deterministic (`freshBid` in `Effect.lean`), so `freeze`/`read`
  in the step relation and in `EffHC` agree.  `RegionSafeHC` is the handle-aware
  version of `RegionSafe`, and is preserved by configuration steps.
-/

import LSys.EvalConf

namespace LSys

set_option linter.unusedVariables false

/-- `holdersOfV (toVal v) = holdersOfR v` (both are stuck matches on `v`). -/
theorem holdersOfV_toVal (v : RVal) :
    Effect.holdersOfV (toVal v) = holdersOfR v := by
  cases v <;> rfl

/-- Configuration-relative handle-carrying effect. -/
inductive EffHC (env : EvalEnv) (heap : EvalHeap) : Expr → Sigma → Sigma → List Bid → Prop where
  | val {σ : Sigma} {v : Val} :
      EffHC env heap (Expr.val v) σ σ (Effect.holdersOfV v)
  | var {σ : Sigma} {x : Var} {v : RVal} (h : env x = some v) :
      EffHC env heap (Expr.var x) σ σ (holdersOfR v)
  | abort {σ : Sigma} {k : Nat} : EffHC env heap (Expr.abort k) σ σ []
  | op {σ : Sigma} {a : Expr} {σ₁ : Sigma} {A : List Bid} {b : Expr}
      {σ₂ : Sigma} {B : List Bid}
      (h₁ : EffHC env heap a σ σ₁ A) (h₂ : EffHC env heap b σ₁ σ₂ B) :
      EffHC env heap (Expr.op a b) σ σ₂ []
  | letE {σ : Sigma} {x : Var} {a : Expr} {σ₁ : Sigma} {A : List Bid}
      {b : Expr} {σ₂ : Sigma} {B : List Bid}
      (h₁ : EffHC env heap a σ σ₁ A) (h₂ : EffHC env heap b σ₁ σ₂ B) :
      EffHC env heap (Expr.letE x a b) σ σ₂ B
  | move {σ : Sigma} {p : Place} {v : RVal} (h : heap p = some v) :
      EffHC env heap (Expr.move p) σ (clearPlace σ p) (holdersOfR v)
  | read {σ : Sigma} {p : Place} {v : RVal} (h : heap p = some v) :
      EffHC env heap (Expr.read p) σ (addBorrow σ (freshBid σ) p Mode.frozen)
        (holdersOfR v)
  | write {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) :
      EffHC env heap (Expr.write p e) σ (setHolders σ' p A) []
  | seq {σ : Sigma} {a : Expr} {σ₁ : Sigma} {A : List Bid} {b : Expr}
      {σ₂ : Sigma} {B : List Bid}
      (h₁ : EffHC env heap a σ σ₁ A) (h₂ : EffHC env heap b σ₁ σ₂ B) :
      EffHC env heap (Expr.seq a b) σ σ₂ B
  | region {σ : Sigma} {R : Rgn} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) : EffHC env heap (Expr.region R e) σ σ' A
  | alloc {σ : Sigma} {a : Nat} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) : EffHC env heap (Expr.alloc a e) σ σ' []
  | freeze {σ : Sigma} {p : Place} :
      EffHC env heap (Expr.freeze p) σ (addBorrow σ (freshBid σ) p Mode.frozen)
        [freshBid σ]
  | recover {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) :
      EffHC env heap (Expr.recover e) σ (ConsumeResult σ' A) []
  | borrow {σ : Sigma} {p : Place} {x : Var} {e : Expr} {σ' : Sigma}
      {A : List Bid} (h : EffHC env heap e (addBorrow σ 0 p Mode.mut) σ' A) :
      EffHC env heap (Expr.borrow p x e) σ σ' A
  | drop {σ : Sigma} {p : Place} :
      EffHC env heap (Expr.drop p) σ (clearPlace σ p) []
  | call {σ : Sigma} {f : Nat} {a : Expr} {σ₁ : Sigma} {A : List Bid}
      {body : Expr} {σ₂ : Sigma} {B : List Bid}
      (h₁ : EffHC env heap a σ σ₁ A) (h₂ : EffHC env heap body σ₁ σ₂ B) :
      EffHC env heap (Expr.call f a body) σ σ₂ B
  | ret {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) : EffHC env heap (Expr.ret e) σ σ' A
  | spawn {σ : Sigma} {f : Nat} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) : EffHC env heap (Expr.spawn f e) σ σ' []
  | atomic {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) : EffHC env heap (Expr.atomic p e) σ σ' A
  | unsafeE {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : EffHC env heap e σ σ' A) : EffHC env heap (Expr.unsafeE e) σ σ' A
  | deref {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid} {B : List Bid}
      (h : EffHC env heap e σ σ' A) : EffHC env heap (Expr.derefRaw e) σ σ' B

/-- Step effect followed by the residual configuration-relative effect. -/
theorem effHStepEvalC_effHC_compose :
    ∀ {σ σ' : Sigma} {c c' : EvalConf} {e : Expr} {A : List Bid},
      EffHStepEvalC σ c e c' σ' A →
      ∀ (σ'' : Sigma) (B : List Bid),
        EffHC c.env c.heap c'.expr σ' σ'' B →
        EffHC c.env c.heap e σ σ'' B := by
  intro σ σ' c c' e A hstep
  induction hstep with
  | varV h =>
      intro σ'' B hres
      cases hres
      rw [holdersOfV_toVal]
      exact EffHC.var h
  | moveV h =>
      intro σ'' B hres
      cases hres
      rw [holdersOfV_toVal]
      exact EffHC.move h
  | readV h =>
      intro σ'' B hres
      cases hres
      rw [holdersOfV_toVal]
      exact EffHC.read h
  | val =>
      intro σ'' B hres
      cases hres
      exact EffHC.val
  | abort =>
      intro σ'' B hres
      cases hres
      exact EffHC.abort
  | op =>
      intro σ'' B hres
      cases hres
      exact EffHC.op (EffHC.val) (EffHC.val)
  | opAny =>
      intro σ'' B hres
      cases hres
      exact EffHC.op (EffHC.val) (EffHC.val)
  | letV =>
      intro σ'' B hres
      exact EffHC.letE (EffHC.val) hres
  | seqV =>
      intro σ'' B hres
      exact EffHC.seq (EffHC.val) hres
  | callV =>
      intro σ'' B hres
      exact EffHC.call (EffHC.val) hres
  | freeze =>
      intro σ'' B hres
      cases hres
      exact EffHC.freeze
  | recover =>
      intro σ'' B hres
      cases hres
      exact EffHC.recover (EffHC.val)
  | recoverAny hV =>
      intro σ'' B hres
      cases hres
      exact EffHC.recover (hV ▸ EffHC.val)
  | write =>
      intro σ'' B hres
      cases hres
      exact EffHC.write (EffHC.val)
  | alloc =>
      intro σ'' B hres
      cases hres
      exact EffHC.alloc (EffHC.val)
  | drop =>
      intro σ'' B hres
      cases hres
      exact EffHC.drop
  | regionV =>
      intro σ'' B hres
      cases hres
      exact EffHC.region (EffHC.val)
  | retV =>
      intro σ'' B hres
      cases hres
      exact EffHC.ret (EffHC.val)
  | spawnV =>
      intro σ'' B hres
      cases hres
      exact EffHC.spawn (EffHC.val)
  | atomicV =>
      intro σ'' B hres
      cases hres
      exact EffHC.atomic (EffHC.val)
  | unsafeV =>
      intro σ'' B hres
      cases hres
      exact EffHC.unsafeE (EffHC.val)
  | derefV =>
      intro σ'' B hres
      cases hres
      exact EffHC.deref (EffHC.val)
  | derefAny =>
      intro σ'' B hres
      cases hres
      exact EffHC.deref (EffHC.val)
  | borrowEnter =>
      intro σ'' B hres
      exact EffHC.borrow hres
  | borrowExit =>
      intro σ'' B hres
      cases hres
      exact EffHC.val
  | abortBorrow =>
      intro σ'' B hres
      cases hres
      exact EffHC.abort
  | opL h ih =>
      intro σ'' B hres
      cases hres with
      | op h1 h2 => exact EffHC.op (ih _ _ h1) h2
  | opR hv h ih =>
      intro σ'' B hres
      cases hres with
      | op h1 h2 =>
          cases Effect.isVal_eq hv with
          | intro v hv' =>
              cases hv'
              cases h1
              exact EffHC.op (EffHC.val) (ih _ _ h2)
  | letB h ih =>
      intro σ'' B hres
      cases hres with
      | letE h1 h2 => exact EffHC.letE (ih _ _ h1) h2
  | writeB h ih =>
      intro σ'' B hres
      cases hres with
      | write h1 => exact EffHC.write (ih _ _ h1)
  | seqL h ih =>
      intro σ'' B hres
      cases hres with
      | seq h1 h2 => exact EffHC.seq (ih _ _ h1) h2
  | allocB h ih =>
      intro σ'' B hres
      cases hres with
      | alloc h1 => exact EffHC.alloc (ih _ _ h1)
  | regionB h ih =>
      intro σ'' B hres
      cases hres with
      | region h1 => exact EffHC.region (ih _ _ h1)
  | recoverB h ih =>
      intro σ'' B hres
      cases hres with
      | recover h1 => exact EffHC.recover (ih _ _ h1)
  | callB h ih =>
      intro σ'' B hres
      cases hres with
      | call h1 h2 => exact EffHC.call (ih _ _ h1) h2
  | retB h ih =>
      intro σ'' B hres
      cases hres with
      | ret h1 => exact EffHC.ret (ih _ _ h1)
  | spawnB h ih =>
      intro σ'' B hres
      cases hres with
      | spawn h1 => exact EffHC.spawn (ih _ _ h1)
  | atomicB h ih =>
      intro σ'' B hres
      cases hres with
      | atomic h1 => exact EffHC.atomic (ih _ _ h1)
  | unsafeB h ih =>
      intro σ'' B hres
      cases hres with
      | unsafeE h1 => exact EffHC.unsafeE (ih _ _ h1)
  | derefB h ih =>
      intro σ'' B hres
      cases hres with
      | deref h1 => exact EffHC.deref (ih _ _ h1)

/-- Every step preserves `env`/`heap` (only `expr`/`state` change). -/
theorem EffHStepEvalC.env_heap {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
    {A : List Bid} (h : EffHStepEvalC σ c e c' σ' A) :
    c'.env = c.env ∧ c'.heap = c.heap := by
  induction h with
  | varV _ => exact ⟨rfl, rfl⟩
  | moveV _ => exact ⟨rfl, rfl⟩
  | readV _ => exact ⟨rfl, rfl⟩
  | val => exact ⟨rfl, rfl⟩
  | abort => exact ⟨rfl, rfl⟩
  | op => exact ⟨rfl, rfl⟩
  | opAny => exact ⟨rfl, rfl⟩
  | letV => exact ⟨rfl, rfl⟩
  | seqV => exact ⟨rfl, rfl⟩
  | callV => exact ⟨rfl, rfl⟩
  | freeze => exact ⟨rfl, rfl⟩
  | recover => exact ⟨rfl, rfl⟩
  | recoverAny _ => exact ⟨rfl, rfl⟩
  | write => exact ⟨rfl, rfl⟩
  | alloc => exact ⟨rfl, rfl⟩
  | drop => exact ⟨rfl, rfl⟩
  | regionV => exact ⟨rfl, rfl⟩
  | retV => exact ⟨rfl, rfl⟩
  | spawnV => exact ⟨rfl, rfl⟩
  | atomicV => exact ⟨rfl, rfl⟩
  | unsafeV => exact ⟨rfl, rfl⟩
  | derefV => exact ⟨rfl, rfl⟩
  | derefAny => exact ⟨rfl, rfl⟩
  | borrowEnter => exact ⟨rfl, rfl⟩
  | borrowExit => exact ⟨rfl, rfl⟩
  | abortBorrow => exact ⟨rfl, rfl⟩
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

/-- `EffHC` only depends on `env`/`heap`. -/
theorem EffHC.env_heap_congr {env₁ env₂ : EvalEnv} {heap₁ heap₂ : EvalHeap}
    {e : Expr} {σ σ' : Sigma} {A : List Bid}
    (he : env₁ = env₂) (hh : heap₁ = heap₂)
    (h : EffHC env₁ heap₁ e σ σ' A) : EffHC env₂ heap₂ e σ σ' A := by
  cases he
  cases hh
  exact h

/-- Handle-aware region safety relative to a configuration. -/
def RegionSafeHC (env : EvalEnv) (heap : EvalHeap)
    (σ : Sigma) (R : Rgn) (e : Expr) : Prop :=
  ∀ (σ' : Sigma) (A : List Bid), EffHC env heap e σ σ' A → NoEscape σ' R

/-- `RegionSafeHC` only depends on `env`/`heap`. -/
theorem RegionSafeHC.env_heap_congr {env₁ env₂ : EvalEnv} {heap₁ heap₂ : EvalHeap}
    {σ : Sigma} {R : Rgn} {e : Expr}
    (he : env₁ = env₂) (hh : heap₁ = heap₂)
    (h : RegionSafeHC env₁ heap₁ σ R e) : RegionSafeHC env₂ heap₂ σ R e := by
  intro σ' A hres
  exact h σ' A (EffHC.env_heap_congr he.symm hh.symm hres)


/-- `RegionSafeHC` is preserved by a configuration step. -/
theorem regionSafeHC_step {env : EvalEnv} {heap : EvalHeap}
    {σ σ' : Sigma} {R : Rgn} {e : Expr} {A : List Bid}
    {c c' : EvalConf}
    (hsafe : RegionSafeHC env heap σ R e)
    (hstep : EffHStepEvalC σ c e c' σ' A)
    (henv : c.env = env) (hheap : c.heap = heap) :
    RegionSafeHC env heap σ' R c'.expr := by
  intro σ'' B hres
  have hres2 : EffHC c.env c.heap c'.expr σ' σ'' B :=
    EffHC.env_heap_congr henv.symm hheap.symm hres
  have hcomp : EffHC c.env c.heap e σ σ'' B :=
    effHStepEvalC_effHC_compose hstep σ'' B hres2
  exact hsafe σ'' B (EffHC.env_heap_congr henv hheap hcomp)

end LSys
