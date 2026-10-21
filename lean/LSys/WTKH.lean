/-
  LSys/WTKH.lean

  Route A, first slice: **value-dependent (`WTKH`) typing for `let`/`borrow`**.

  The first-order `WTyH.letE` types the body under the *same* environment and
  state, so a `let`-bound variable (and its handle holders) cannot be used in
  the body.  `WTKH` instead carries the binding into the body:

  * `letE` types the body, for **every** possible value `v` of the bound
    expression, under

        setEnv env x (ofVal v)
        bindHolders σ₁ x (holdersOfV v)

    where `σ₁` is the state after the bound expression.  The `∀ v` premise is
    independent of the value produced at run time, so it survives a step in
    the bound expression (`letE_ctx`), while the value step instantiates it at
    the actual value (`letV_inv`).

  * `borrow` types the body under `setEnv env x (refH 0)` (the canonical
    borrow bid) and `addBorrow σ 0 p mut`; `borrow_inv` exposes this.

  The remaining rules are the binding-free rules of `WTyH`.
-/

import LSys.WTyH
import LSys.LetHandle
import LSys.LamEff

namespace LSys

set_option linter.unusedVariables false

/-- Value-dependent, handle-aware typing. -/
inductive WTKH : EvalEnv → EvalHeap → Expr → Sigma → Sigma → List Bid → Prop where
  | val {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {v : Val} :
      WTKH env heap (Expr.val v) σ σ (Effect.holdersOfV v)
  | var {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {x : Var} {v : RVal} (h : env x = some v) :
      WTKH env heap (Expr.var x) σ σ (holdersOfR v)
  | abort {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {k : Nat} : WTKH env heap (Expr.abort k) σ σ []
  | op {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Expr} {σ₁ : Sigma} {A : List Bid} {b : Expr}
      {σ₂ : Sigma} {B : List Bid}
      (ha : WTKH env heap a σ σ₁ A) (hb : WTKH env heap b σ₁ σ₂ B) :
      WTKH env heap (Expr.op a b) σ σ₂ []
  | letE {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {x : Var} {a : Expr} {σ₁ : Sigma} {A : List Bid}
      {b : Expr} {σ₂ : Sigma} {B : List Bid}
      (ha : WTKH env heap a σ σ₁ A)
      (hb : ∀ v : Val,
        WTKH (setEnv env x (ofVal v)) heap b
          (bindHolders σ₁ x (Effect.holdersOfV v)) σ₂ B) :
      WTKH env heap (Expr.letE x a b) σ σ₂ B
  | move {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {v : RVal} (h : heap p = some v) :
      WTKH env heap (Expr.move p) σ (clearPlace σ p) (holdersOfR v)
  | read {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {v : RVal} (h : heap p = some v)
      (hm : modeOf σ p = some Mode.frozen ∨ modeOf σ p = some Mode.mut) :
      WTKH env heap (Expr.read p) σ
        (addBorrow σ (freshBid σ) p Mode.frozen) (holdersOfR v)
  | write {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A) (hw : Writable σ' p) :
      WTKH env heap (Expr.write p e) σ (setHolders σ' p A) []
  | seq {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Expr} {σ₁ : Sigma} {A : List Bid} {b : Expr}
      {σ₂ : Sigma} {B : List Bid}
      (ha : WTKH env heap a σ σ₁ A) (hb : WTKH env heap b σ₁ σ₂ B) :
      WTKH env heap (Expr.seq a b) σ σ₂ B
  | region {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {R : Rgn} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A)
      (hsafe : RegionSafeLam σ R e)
      (hno : NoEscape σ' R) :
      WTKH env heap (Expr.region R e) σ σ' A
  | alloc {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Nat} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A) (hcap : CAP_ALLOC_OK σ') :
      WTKH env heap (Expr.alloc a e) σ σ' []
  | freeze {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} (hm : modeOf σ p = some Mode.uniq)
      (hl : live σ p = []) :
      WTKH env heap (Expr.freeze p) σ
        (addBorrow σ (freshBid σ) p Mode.frozen) [freshBid σ]
  | recover {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A) :
      WTKH env heap (Expr.recover e) σ (ConsumeResult σ' A) []
  | borrow {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {x : Var} {e : Expr} {σ' : Sigma}
      {A : List Bid} (hm : modeOf σ p = some Mode.uniq)
      (he : WTKH (setEnv env x (RVal.refH 0)) heap e
        (addBorrow σ 0 p Mode.mut) σ' A) :
      WTKH env heap (Expr.borrow p x e) σ σ' A
  | drop {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} (hm : modeOf σ p = some Mode.uniq) :
      WTKH env heap (Expr.drop p) σ (clearPlace σ p) []
  | call {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {f : Nat} {a : Expr} {σ₁ : Sigma} {A : List Bid}
      {body : Expr} {σ₂ : Sigma} {B : List Bid}
      (ha : WTKH env heap a σ σ₁ A) (hcap : CAPS_OK σ₁ f)
      (hb : WTKH env heap body σ₁ σ₂ B) :
      WTKH env heap (Expr.call f a body) σ σ₂ B
  | ret {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A) : WTKH env heap (Expr.ret e) σ σ' A
  | spawn {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {f : Nat} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A) (hcap : CAPS_OK σ' f) :
      WTKH env heap (Expr.spawn f e) σ σ' []
  | atomic {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A) (hm : modeOf σ' p = some Mode.atom) :
      WTKH env heap (Expr.atomic p e) σ σ' A
  | unsafeE {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {e : Expr} {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ σ' A) : WTKH env heap (Expr.unsafeE e) σ σ' A
  | deref {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {l : Loc} {v : RVal}
      (hp : heap (locPlace l) = some v) :
      WTKH env heap (Expr.derefRaw (Expr.val (Val.loc l))) σ σ (holdersOfR v)

/-- Inversion of the `let` rule: the body is typed under the binding for
    **every** value. -/
theorem WTKH.letE_inv {env : EvalEnv} {heap : EvalHeap} {σ σ₁ : Sigma}
    {x : Var} {a b : Expr} {A : List Bid}
    (h : WTKH env heap (Expr.letE x a b) σ σ₁ A) :
    ∃ (σ_a : Sigma) (A_a : List Bid),
      WTKH env heap a σ σ_a A_a ∧
      (∀ v : Val,
        WTKH (setEnv env x (ofVal v)) heap b
          (bindHolders σ_a x (Effect.holdersOfV v)) σ₁ A) := by
  cases h with
  | letE ha hb => exact ⟨_, _, ha, hb⟩

/-- The **value step** `let x = val v in b → b`: the body is typed under the
    binding for the actual value `v`, with the static holders updated by
    `bindHolders`. -/
theorem WTKH.letV_inv {env : EvalEnv} {heap : EvalHeap} {σ σ₁ : Sigma}
    {x : Var} {v : Val} {b : Expr} {A : List Bid}
    (h : WTKH env heap (Expr.letE x (Expr.val v) b) σ σ₁ A) :
    WTKH (setEnv env x (ofVal v)) heap b
      (bindHolders σ x (Effect.holdersOfV v)) σ₁ A := by
  cases h with
  | letE ha hb =>
      cases ha
      exact hb v

/-- The **context step** `let x = a in b → let x = a' in b`: the body premise
    is unchanged because it is parameterized by the value. -/
theorem WTKH.letE_ctx {env : EvalEnv} {heap : EvalHeap} {σ σ₁ : Sigma}
    {x : Var} {a b : Expr} {A : List Bid} {σ_a : Sigma} {A_a : List Bid}
    (ha : WTKH env heap a σ σ_a A_a)
    (hb : ∀ v : Val,
      WTKH (setEnv env x (ofVal v)) heap b
        (bindHolders σ_a x (Effect.holdersOfV v)) σ₁ A)
    {σ' : Sigma} {A_a' : List Bid}
    (ha' : WTKH env heap a' σ' σ_a A_a') :
    WTKH env heap (Expr.letE x a' b) σ' σ₁ A :=
  WTKH.letE ha' hb

/-- Inversion of the `borrow` rule: the body sees `x` bound to the canonical
    borrow handle and the borrow state. -/
theorem WTKH.borrow_inv {env : EvalEnv} {heap : EvalHeap} {σ σ₁ : Sigma}
    {p : Place} {x : Var} {e : Expr} {A : List Bid}
    (h : WTKH env heap (Expr.borrow p x e) σ σ₁ A) :
    modeOf σ p = some Mode.uniq ∧
    WTKH (setEnv env x (RVal.refH 0)) heap e (addBorrow σ 0 p Mode.mut) σ₁ A := by
  cases h with
  | borrow hm he => exact ⟨hm, he⟩

end LSys
