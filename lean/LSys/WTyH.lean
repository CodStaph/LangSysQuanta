/-
  LSys/WTyH.lean

  Handle-aware, state-threaded typing (`WTyH`).

  `WTK`/`WT` are handle-free, so their side conditions are checked at the
  input state and their `write` rule has a free handle set.  `WTyH` fixes both
  problems:

  * every rule carries the expression's actual result handles `A`;
  * side conditions are checked at the state where the corresponding dynamic
    step fires (`Writable`/`CAP_ALLOC_OK`/`CAPS_OK`/`modeOf` at the output of
    the operand, `freeze`/`read`/`borrow`/`move`/`drop` at the input);
  * `freeze`/`read` use the deterministic `freshBid`;
  * `write` stores exactly the operand's handles, and `recover` consumes them;
  * `region` checks `RegionSafeHC`, so the post `NoEscape` follows.

  The main result is preservation under `EffHStepEvalC`:

    WTyH c.env c.heap e σ σ₁ A →
    EffHStepEvalC σ c e c' σ' A' →
    WTyH c'.env c'.heap c'.expr σ' σ₁ A

  `derefRaw` is deliberately absent: its result handles come from the runtime
  heap, which the current `EvalConf` (a `Place`-indexed heap) cannot resolve
  for a `loc`.  It needs an explicit loc→heap link (tracked in `MEMORY.md`).
-/

import LSys.Adequacy
import LSys.EffHC

namespace LSys

set_option linter.unusedVariables false

/-- Handle-aware, state-threaded typing. -/
inductive WTyH (env : EvalEnv) (heap : EvalHeap) :
    Expr → Sigma → Sigma → List Bid → Prop where
  | val {σ : Sigma} {v : Val} :
      WTyH env heap (Expr.val v) σ σ (Effect.holdersOfV v)
  | var {σ : Sigma} {x : Var} {v : RVal} (h : env x = some v) :
      WTyH env heap (Expr.var x) σ σ (holdersOfR v)
  | abort {σ : Sigma} {k : Nat} : WTyH env heap (Expr.abort k) σ σ []
  | op {σ : Sigma} {a : Expr} {σ₁ : Sigma} {A : List Bid} {b : Expr}
      {σ₂ : Sigma} {B : List Bid}
      (ha : WTyH env heap a σ σ₁ A) (hb : WTyH env heap b σ₁ σ₂ B) :
      WTyH env heap (Expr.op a b) σ σ₂ []
  | letE {σ : Sigma} {x : Var} {a : Expr} {σ₁ : Sigma} {A : List Bid}
      {b : Expr} {σ₂ : Sigma} {B : List Bid}
      (ha : WTyH env heap a σ σ₁ A) (hb : WTyH env heap b σ₁ σ₂ B) :
      WTyH env heap (Expr.letE x a b) σ σ₂ B
  | move {σ : Sigma} {p : Place} {v : RVal} (h : heap p = some v) :
      WTyH env heap (Expr.move p) σ (clearPlace σ p) (holdersOfR v)
  | read {σ : Sigma} {p : Place} {v : RVal} (h : heap p = some v)
      (hm : modeOf σ p = some Mode.frozen ∨ modeOf σ p = some Mode.mut) :
      WTyH env heap (Expr.read p) σ
        (addBorrow σ (freshBid σ) p Mode.frozen) (holdersOfR v)
  | write {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A) (hw : Writable σ' p) :
      WTyH env heap (Expr.write p e) σ (setHolders σ' p A) []
  | seq {σ : Sigma} {a : Expr} {σ₁ : Sigma} {A : List Bid} {b : Expr}
      {σ₂ : Sigma} {B : List Bid}
      (ha : WTyH env heap a σ σ₁ A) (hb : WTyH env heap b σ₁ σ₂ B) :
      WTyH env heap (Expr.seq a b) σ σ₂ B
  | region {σ : Sigma} {R : Rgn} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A)
      (hsafe : RegionSafeHC env heap σ R e) (hno : NoEscape σ' R) :
      WTyH env heap (Expr.region R e) σ σ' A
  | alloc {σ : Sigma} {a : Nat} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A) (hcap : CAP_ALLOC_OK σ') :
      WTyH env heap (Expr.alloc a e) σ σ' []
  | freeze {σ : Sigma} {p : Place} (hm : modeOf σ p = some Mode.uniq)
      (hl : live σ p = []) :
      WTyH env heap (Expr.freeze p) σ
        (addBorrow σ (freshBid σ) p Mode.frozen) [freshBid σ]
  | recover {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A) :
      WTyH env heap (Expr.recover e) σ (ConsumeResult σ' A) []
  | borrow {σ : Sigma} {p : Place} {x : Var} {e : Expr} {σ' : Sigma}
      {A : List Bid} (hm : modeOf σ p = some Mode.uniq)
      (he : WTyH env heap e (addBorrow σ 0 p Mode.mut) σ' A) :
      WTyH env heap (Expr.borrow p x e) σ σ' A
  | drop {σ : Sigma} {p : Place} (hm : modeOf σ p = some Mode.uniq) :
      WTyH env heap (Expr.drop p) σ (clearPlace σ p) []
  | call {σ : Sigma} {f : Nat} {a : Expr} {σ₁ : Sigma} {A : List Bid}
      {body : Expr} {σ₂ : Sigma} {B : List Bid}
      (ha : WTyH env heap a σ σ₁ A) (hcap : CAPS_OK σ₁ f)
      (hb : WTyH env heap body σ₁ σ₂ B) :
      WTyH env heap (Expr.call f a body) σ σ₂ B
  | ret {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A) : WTyH env heap (Expr.ret e) σ σ' A
  | spawn {σ : Sigma} {f : Nat} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A) (hcap : CAPS_OK σ' f) :
      WTyH env heap (Expr.spawn f e) σ σ' []
  | atomic {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A) (hm : modeOf σ' p = some Mode.atom) :
      WTyH env heap (Expr.atomic p e) σ σ' A
  | unsafeE {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTyH env heap e σ σ' A) : WTyH env heap (Expr.unsafeE e) σ σ' A

/-- `WTyH` only depends on `env`/`heap`. -/
theorem WTyH.env_heap_congr {env₁ env₂ : EvalEnv} {heap₁ heap₂ : EvalHeap}
    {e : Expr} {σ σ₁ : Sigma} {A : List Bid}
    (he : env₁ = env₂) (hh : heap₁ = heap₂)
    (h : WTyH env₁ heap₁ e σ σ₁ A) : WTyH env₂ heap₂ e σ σ₁ A := by
  cases he
  cases hh
  exact h

/-- `WTyH` refines the configuration-relative effect `EffHC`. -/
theorem WTyH.toEffHC {env : EvalEnv} {heap : EvalHeap} {e : Expr}
    {σ σ' : Sigma} {A : List Bid} (h : WTyH env heap e σ σ' A) :
    EffHC env heap e σ σ' A := by
  induction h with
  | val => exact EffHC.val
  | var h => exact EffHC.var h
  | abort => exact EffHC.abort
  | op ha hb iha ihb => exact EffHC.op iha ihb
  | letE ha hb iha ihb => exact EffHC.letE iha ihb
  | move h => exact EffHC.move h
  | read h hm => exact EffHC.read h
  | write he hw ihe => exact EffHC.write ihe
  | seq ha hb iha ihb => exact EffHC.seq iha ihb
  | region he hsafe hno ihe => exact EffHC.region ihe
  | alloc he hcap ihe => exact EffHC.alloc ihe
  | freeze hm hl => exact EffHC.freeze
  | recover he ihe => exact EffHC.recover ihe
  | borrow hm he ihe => exact EffHC.borrow ihe
  | drop hm => exact EffHC.drop
  | call ha hcap hb iha ihb => exact EffHC.call iha ihb
  | ret he ihe => exact EffHC.ret ihe
  | spawn he hcap ihe => exact EffHC.spawn ihe
  | atomic he hm ihe => exact EffHC.atomic ihe
  | unsafeE he ihe => exact EffHC.unsafeE ihe


/-- `WTyH` is preserved by a configuration step: the residual has the same
    final state and handles as the original expression. -/
def WTyHSafe (e : Expr) : Prop :=
  ∀ {env : EvalEnv} {heap : EvalHeap} {σ σ₁ : Sigma} {A : List Bid},
    WTyH env heap e σ σ₁ A →
    ∀ {c c' : EvalConf} {σ' : Sigma} {A' : List Bid},
      EffHStepEvalC σ c e c' σ' A' →
      c.env = env → c.heap = heap →
      WTyH c'.env c'.heap c'.expr σ' σ₁ A

theorem WTyH.preserved : ∀ e : Expr, WTyHSafe e := by
  intro e
  induction e with
  | val v =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hstep with
      | val =>
          cases hwt
          exact WTyH.val
      | borrowExit =>
          cases hwt
          exact WTyH.val
  | var x =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hstep with
      | varV hx =>
          cases hwt with
          | var hx' =>
              rw [hc] at hx
              rw [hx] at hx'
              cases hx'
              exact holdersOfV_toVal _ ▸ WTyH.val
  | abort k =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hstep with
      | abort =>
          cases hwt
          exact WTyH.abort
      | abortBorrow =>
          cases hwt
          exact WTyH.abort
  | op a b iha ihb =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | op ha hb =>
          cases hstep with
          | op =>
              cases ha
              cases hb
              exact WTyH.val
          | opAny =>
              cases ha
              cases hb
              exact WTyH.val
          | opL hstepA =>
              exact WTyH.op (hc ▸ hh ▸ iha ha hstepA hc hh) hb
          | opR hv hstepB =>
              cases Effect.isVal_eq hv with
              | intro v hv' =>
                  cases hv'
                  cases ha
                  exact WTyH.op (WTyH.val) (hc ▸ hh ▸ ihb hb hstepB hc hh)
  | letE x a b iha ihb =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | letE ha hb =>
          cases hstep with
          | letV =>
              cases ha
              exact hb
          | letB hstepA =>
              exact WTyH.letE (hc ▸ hh ▸ iha ha hstepA hc hh) hb
  | move p =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hstep with
      | moveV hstepH =>
          cases hwt with
          | move h' =>
              rw [hh] at hstepH
              rw [hstepH] at h'
              cases h'
              exact holdersOfV_toVal _ ▸ WTyH.val
  | read p =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hstep with
      | readV hstepH =>
          cases hwt with
          | read h' hm =>
              rw [hh] at hstepH
              rw [hstepH] at h'
              cases h'
              exact holdersOfV_toVal _ ▸ WTyH.val
  | write p e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | write he hw =>
          cases hstep with
          | write =>
              cases he
              exact WTyH.val
          | writeB hstepE =>
              exact WTyH.write (hc ▸ hh ▸ ihe he hstepE hc hh) hw
  | seq a b iha ihb =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | seq ha hb =>
          cases hstep with
          | seqV =>
              cases ha
              exact hb
          | seqL hstepA =>
              exact WTyH.seq (hc ▸ hh ▸ iha ha hstepA hc hh) hb
  | region r e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | region he hsafe hno =>
          cases hstep with
          | regionV =>
              cases he
              exact WTyH.val
          | regionB hstepE =>
              exact WTyH.region (hc ▸ hh ▸ ihe he hstepE hc hh)
                (regionSafeHC_step hsafe hstepE hc hh) hno
  | alloc a e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | alloc he hcap =>
          cases hstep with
          | alloc =>
              cases he
              exact WTyH.val
          | allocB hstepE =>
              exact WTyH.alloc (hc ▸ hh ▸ ihe he hstepE hc hh) hcap
  | freeze p =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hstep
      cases hwt
      exact WTyH.val
  | recover e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | recover he =>
          cases hstep with
          | recover =>
              cases he
              exact WTyH.val
          | recoverAny hV =>
              cases he
              rw [hV]
              exact WTyH.val
          | recoverB hstepE =>
              exact WTyH.recover (hc ▸ hh ▸ ihe he hstepE hc hh)
  | borrow p x e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | borrow hm he =>
          cases hstep with
          | borrowEnter => exact he
  | drop p =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hstep
      cases hwt
      exact WTyH.val
  | call f a body iha ihb =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | call ha hcap hb =>
          cases hstep with
          | callV =>
              cases ha
              exact hb
          | callB hstepA =>
              exact WTyH.call (hc ▸ hh ▸ iha ha hstepA hc hh) hcap hb
  | ret e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | ret he =>
          cases hstep with
          | retV =>
              cases he
              exact WTyH.val
          | retB hstepE =>
              exact WTyH.ret (hc ▸ hh ▸ ihe he hstepE hc hh)
  | spawn f e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | spawn he hcap =>
          cases hstep with
          | spawnV =>
              cases he
              exact WTyH.val
          | spawnB hstepE =>
              exact WTyH.spawn (hc ▸ hh ▸ ihe he hstepE hc hh) hcap
  | atomic p e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | atomic he hm =>
          cases hstep with
          | atomicV =>
              cases he
              exact WTyH.val
          | atomicB hstepE =>
              exact WTyH.atomic (hc ▸ hh ▸ ihe he hstepE hc hh) hm
  | unsafeE e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      rw [(EffHStepEvalC.env_heap hstep).1, hc,
          (EffHStepEvalC.env_heap hstep).2, hh]
      cases hwt with
      | unsafeE he =>
          cases hstep with
          | unsafeV =>
              cases he
              exact WTyH.val
          | unsafeB hstepE =>
              exact WTyH.unsafeE (hc ▸ hh ▸ ihe he hstepE hc hh)
  | derefRaw e0 ihe =>
      intro env heap σ σ₁ A hwt c c' σ' A' hstep hc hh
      cases hwt

end LSys
