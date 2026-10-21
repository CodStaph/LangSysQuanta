/-
  LSys/WTKH.lean

  Route A: **outcome-typed, value-dependent, handle-aware typing**.

  `WTKH env heap e σ o` relates the expression `e`, entered in static state
  `σ`, to an *outcome*:

    `Outcome.ok σ' A`  — `e` returns normally in `σ'` with live handles `A`;
    `Outcome.aborts σ` — `e` aborts in `σ` (no handles).

  Why outcomes (and not a single `σ' × A`): an abort in a *prefix* position
  makes the recorded normal outcome unreachable, so a normal-only typing is
  unsound for abort propagation (`op (abort k) b` can never return normally,
  yet a chaining rule would still assign `b`'s effect).  With outcomes:

  * `abort` has outcome `aborts σ`;
  * composites either *bind* (`op`/`let`/`seq`/`call`: an aborting prefix
    swallows the continuation) or *map* over the normal outcome
    (`write`/`recover`/`alloc`/`spawn`: the wrapper only happens on a normal
    return), and otherwise pass the outcome through (`region`, `ret`,
    `atomic`, `unsafe`, `borrow`);
  * the outcome is **deterministic** per expression, and it is *invariant
    under evaluation steps* (`WTKH.preserved`), which is what makes the abort
    rules of `EffHStepEvalCK` typable.

  `let` is value-dependent: the body is typed for **every** value `v` of the
  bound expression, under `setEnv env x (ofVal v)` and
  `bindHolders σ_a x (holdersOfV v)`; that premise is independent of the
  run-time value, so it survives a step in the bound expression, while the
  value step instantiates it.  `borrow` types the body under
  `setEnv env x (refH 0)` and `addBorrow σ 0 p mut`.
-/

import LSys.WTyH
import LSys.LetHandle
import LSys.LamEff

namespace LSys

set_option linter.unusedVariables false

/-- The result of evaluating an expression. -/
inductive Outcome where
  | ok (σ : Sigma) (A : List Bid)
  | aborts (σ : Sigma)
  deriving Repr, DecidableEq

namespace Outcome

/-- Drop the live handles of a normal outcome (used by `op`, whose value is a
    plain integer).  An abort is unchanged. -/
def drop : Outcome → Outcome
  | .ok σ _ => .ok σ []
  | .aborts σ => .aborts σ

/-- Map a state/handle transformation over a normal outcome; an abort passes
    through unchanged (the wrapper never runs). -/
def map (f : Sigma → List Bid → Sigma × List Bid) : Outcome → Outcome
  | .ok σ A => let p := f σ A; .ok p.1 p.2
  | .aborts σ => .aborts σ

theorem drop_ok (σ : Sigma) (A : List Bid) : drop (.ok σ A) = .ok σ [] := rfl
theorem drop_aborts (σ : Sigma) : drop (.aborts σ) = .aborts σ := rfl
theorem map_ok (f : Sigma → List Bid → Sigma × List Bid) (σ : Sigma) (A : List Bid) :
    map f (.ok σ A) = let p := f σ A; .ok p.1 p.2 := rfl
theorem map_aborts (f : Sigma → List Bid → Sigma × List Bid) (σ : Sigma) :
    map f (.aborts σ) = .aborts σ := rfl

end Outcome

/-- Outcome-typed, value-dependent, handle-aware typing. -/
inductive WTKH : EvalEnv → EvalHeap → Expr → Sigma → Outcome → Prop where
  | val {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {v : Val} :
      WTKH env heap (Expr.val v) σ (.ok σ (Effect.holdersOfV v))
  | var {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {x : Var} {v : RVal}
      (h : env x = some v) :
      WTKH env heap (Expr.var x) σ (.ok σ (holdersOfR v))
  | abort {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {k : Nat} :
      WTKH env heap (Expr.abort k) σ (.aborts σ)
  | opOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Expr} {σa : Sigma}
      {Aa : List Bid} {b : Expr} {Ob : Outcome}
      (ha : WTKH env heap a σ (.ok σa Aa)) (hb : WTKH env heap b σa Ob) :
      WTKH env heap (Expr.op a b) σ (Ob.map (fun σ' _ => (σ', [])))
  | opAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Expr} {σab : Sigma}
      {b : Expr} (ha : WTKH env heap a σ (.aborts σab)) :
      WTKH env heap (Expr.op a b) σ (.aborts σab)
  | letOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {x : Var} {a : Expr}
      {σa : Sigma} {Aa : List Bid} {b : Expr} {Ob : Outcome}
      (ha : WTKH env heap a σ (.ok σa Aa))
      (hb : ∀ v : Val,
        WTKH (setEnv env x (ofVal v)) heap b
          (bindHolders σa x (Effect.holdersOfV v)) Ob) :
      WTKH env heap (Expr.letE x a b) σ Ob
  | letAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {x : Var} {a : Expr}
      {σab : Sigma} {b : Expr} (ha : WTKH env heap a σ (.aborts σab)) :
      WTKH env heap (Expr.letE x a b) σ (.aborts σab)
  | move {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {v : RVal}
      (h : heap p = some v) :
      WTKH env heap (Expr.move p) σ (.ok (clearPlace σ p) (holdersOfR v))
  | read {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {v : RVal}
      (h : heap p = some v)
      (hm : modeOf σ p = some Mode.frozen ∨ modeOf σ p = some Mode.mut) :
      WTKH env heap (Expr.read p) σ
        (.ok (addBorrow σ (freshBid σ) p Mode.frozen) (holdersOfR v))
  | writeOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {e : Expr}
      {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ (.ok σ' A)) (hw : Writable σ' p) :
      WTKH env heap (Expr.write p e) σ (.ok (setHolders σ' p A) [])
  | writeAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {e : Expr}
      {σab : Sigma} (he : WTKH env heap e σ (.aborts σab)) :
      WTKH env heap (Expr.write p e) σ (.aborts σab)
  | seqOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Expr} {σa : Sigma}
      {Aa : List Bid} {b : Expr} {Ob : Outcome}
      (ha : WTKH env heap a σ (.ok σa Aa)) (hb : WTKH env heap b σa Ob) :
      WTKH env heap (Expr.seq a b) σ Ob
  | seqAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Expr} {σab : Sigma}
      {b : Expr} (ha : WTKH env heap a σ (.aborts σab)) :
      WTKH env heap (Expr.seq a b) σ (.aborts σab)
  | regionOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {R : Rgn} {e : Expr}
      {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ (.ok σ' A))
      (hsafe : RegionSafeLam σ R e) (hno : NoEscape σ' R) :
      WTKH env heap (Expr.region R e) σ (.ok σ' A)
  | regionAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {R : Rgn} {e : Expr}
      {σab : Sigma} (he : WTKH env heap e σ (.aborts σab))
      (hsafe : RegionSafeLam σ R e) :
      WTKH env heap (Expr.region R e) σ (.aborts σab)
  | allocOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Nat} {e : Expr}
      {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ (.ok σ' A)) (hcap : CAP_ALLOC_OK σ') :
      WTKH env heap (Expr.alloc a e) σ (.ok σ' [])
  | allocAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {a : Nat} {e : Expr}
      {σab : Sigma} (he : WTKH env heap e σ (.aborts σab)) :
      WTKH env heap (Expr.alloc a e) σ (.aborts σab)
  | freeze {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place}
      (hm : modeOf σ p = some Mode.uniq) (hl : live σ p = []) :
      WTKH env heap (Expr.freeze p) σ
        (.ok (addBorrow σ (freshBid σ) p Mode.frozen) [freshBid σ])
  | recoverOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {e : Expr}
      {σ' : Sigma} {A : List Bid} (he : WTKH env heap e σ (.ok σ' A)) :
      WTKH env heap (Expr.recover e) σ (.ok (ConsumeResult σ' A) [])
  | recoverAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {e : Expr}
      {σab : Sigma} (he : WTKH env heap e σ (.aborts σab)) :
      WTKH env heap (Expr.recover e) σ (.aborts σab)
  | borrow {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {x : Var}
      {e : Expr} {Ob : Outcome} (hm : modeOf σ p = some Mode.uniq)
      (he : WTKH (setEnv env x (RVal.refH 0)) heap e
        (addBorrow σ 0 p Mode.mut) Ob) :
      WTKH env heap (Expr.borrow p x e) σ Ob
  | drop {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place}
      (hm : modeOf σ p = some Mode.uniq) :
      WTKH env heap (Expr.drop p) σ (.ok (clearPlace σ p) [])
  | callOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {f : Nat} {a : Expr}
      {σa : Sigma} {Aa : List Bid} {body : Expr} {Ob : Outcome}
      (ha : WTKH env heap a σ (.ok σa Aa)) (hcap : CAPS_OK σa f)
      (hb : WTKH env heap body σa Ob) :
      WTKH env heap (Expr.call f a body) σ Ob
  | callAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {f : Nat} {a : Expr}
      {σab : Sigma} {body : Expr} (ha : WTKH env heap a σ (.aborts σab)) :
      WTKH env heap (Expr.call f a body) σ (.aborts σab)
  | ret {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {e : Expr} {Oe : Outcome}
      (he : WTKH env heap e σ Oe) :
      WTKH env heap (Expr.ret e) σ Oe
  | spawnOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {f : Nat} {e : Expr}
      {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ (.ok σ' A)) (hcap : CAPS_OK σ' f) :
      WTKH env heap (Expr.spawn f e) σ (.ok σ' [])
  | spawnAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {f : Nat} {e : Expr}
      {σab : Sigma} (he : WTKH env heap e σ (.aborts σab)) :
      WTKH env heap (Expr.spawn f e) σ (.aborts σab)
  | atomicOk {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {e : Expr}
      {σ' : Sigma} {A : List Bid}
      (he : WTKH env heap e σ (.ok σ' A)) (hm : modeOf σ' p = some Mode.atom) :
      WTKH env heap (Expr.atomic p e) σ (.ok σ' A)
  | atomicAborts {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {p : Place} {e : Expr}
      {σab : Sigma} (he : WTKH env heap e σ (.aborts σab)) :
      WTKH env heap (Expr.atomic p e) σ (.aborts σab)
  | unsafeE {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {e : Expr} {Oe : Outcome}
      (he : WTKH env heap e σ Oe) :
      WTKH env heap (Expr.unsafeE e) σ Oe
  | deref {env : EvalEnv} {heap : EvalHeap} {σ : Sigma} {l : Loc} {v : RVal}
      (hp : heap (locPlace l) = some v) :
      WTKH env heap (Expr.derefRaw (Expr.val (Val.loc l))) σ
        (.ok σ (holdersOfR v))

/-! ## Inversion lemmas -/

/-- Inversion of the `let` rule: either the bound expression returns normally
    (and the body is typed for every value), or it aborts. -/
theorem WTKH.letE_inv {env : EvalEnv} {heap : EvalHeap} {σ : Sigma}
    {x : Var} {a b : Expr} {o : Outcome}
    (h : WTKH env heap (Expr.letE x a b) σ o) :
    (∃ (σa : Sigma) (Aa : List Bid) (Ob : Outcome),
        o = Ob ∧ WTKH env heap a σ (.ok σa Aa) ∧
          ∀ v : Val,
            WTKH (setEnv env x (ofVal v)) heap b
              (bindHolders σa x (Effect.holdersOfV v)) Ob) ∨
      (∃ σab : Sigma, o = .aborts σab ∧ WTKH env heap a σ (.aborts σab)) := by
  cases h with
  | letOk ha hb => exact Or.inl ⟨_, _, _, rfl, ha, hb⟩
  | letAborts ha => exact Or.inr ⟨_, rfl, ha⟩

/-- The **value step** `let x = val v in b`: the body is typed under the binding
    for the actual value `v`. -/
theorem WTKH.letV_inv {env : EvalEnv} {heap : EvalHeap} {σ : Sigma}
    {x : Var} {v : Val} {b : Expr} {o : Outcome}
    (h : WTKH env heap (Expr.letE x (Expr.val v) b) σ o) :
    ∃ Ob : Outcome,
      o = Ob ∧
        WTKH (setEnv env x (ofVal v)) heap b
          (bindHolders σ x (Effect.holdersOfV v)) Ob := by
  cases h with
  | letOk ha hb =>
      cases ha
      exact ⟨_, rfl, hb v⟩
  | letAborts ha => cases ha

/-- Inversion of the `borrow` rule. -/
theorem WTKH.borrow_inv {env : EvalEnv} {heap : EvalHeap} {σ : Sigma}
    {p : Place} {x : Var} {e : Expr} {o : Outcome}
    (h : WTKH env heap (Expr.borrow p x e) σ o) :
    modeOf σ p = some Mode.uniq ∧
      WTKH (setEnv env x (RVal.refH 0)) heap e (addBorrow σ 0 p Mode.mut) o := by
  cases h with
  | borrow hm he => exact ⟨hm, he⟩

end LSys
