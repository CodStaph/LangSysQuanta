/-
  LSys/Effect.lean

  Static effects and the region-safety invariant, placed before `Adequacy`
  so `WT.region` can use them.
-/

import LSys.State
import LSys.StepEval

namespace LSys

 /-- Tagged variable place: `[0, x]` (length 2), disjoint from heap places
    `[l]` (length 1). -/
def varPlace (x : Var) : Place := 0 :: [x]

def NoEscape (σ : Sigma) (R : Rgn) : Prop :=
  ∀ br, br ∈ σ.lam → br.rgn = R → False

def rgnOf (σ : Sigma) (p : Place) : Rgn :=
  match lookupPlace σ.gamma p with
  | some g => g.rgn
  | none => 0

/-- Record holders for a (tagged) variable place. -/
def bindHolders (σ : Sigma) (x : Var) (A : List Bid) : Sigma :=
  { σ with holders := (varPlace x, A) :: σ.holders }

def addBorrow (σ : Sigma) (b : Bid) (p : Place) (m : Mode) : Sigma :=
  { σ with
    lam := { bid := b, place := p, mode := m, rgn := rgnOf σ p } :: σ.lam }

/-- Deterministic fresh bid: one past the maximum bid currently in `Λ`. -/
def maxBid : List Borrow → Bid
  | [] => 0
  | br :: rest => Nat.max br.bid (maxBid rest)

def freshBid (σ : Sigma) : Bid := maxBid σ.lam + 1

def clearPlace (σ : Sigma) (p : Place) : Sigma :=
  { σ with holders := σ.holders.filter (fun qb => !(overlap qb.1 p)) }

def setHolders (σ : Sigma) (p : Place) (A : List Bid) : Sigma :=
  { σ with holders := (p, A) :: σ.holders }

namespace Effect

set_option linter.unusedVariables false

/-- Structural static effect (no `WT` premises; the coherent variant is
    `LSys.Coherent.Eff`). -/
inductive Eff : Sigma → Expr → Sigma → Prop where
  | val (σ : Sigma) (v : Val) : Eff σ (Expr.val v) σ
  | var (σ : Sigma) (x : Var) : Eff σ (Expr.var x) σ
  | abort (σ : Sigma) (k : Nat) : Eff σ (Expr.abort k) σ
  | op {σ a σ₁ b σ₂} (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ b σ₂) :
      Eff σ (Expr.op a b) σ₂
  | letE {σ x a σ₁ b σ₂} (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ b σ₂) :
      Eff σ (Expr.letE x a b) σ₂
  | move {σ p} : Eff σ (Expr.move p) (clearPlace σ p)
  | read {σ p b} : Eff σ (Expr.read p) (addBorrow σ b p Mode.frozen)
  | write {σ p e σ' A} (h : Eff σ e σ') :
      Eff σ (Expr.write p e) (setHolders σ' p A)
  | seq {σ a σ₁ b σ₂} (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ b σ₂) :
      Eff σ (Expr.seq a b) σ₂
  | region {σ R e σ'} (h : Eff σ e σ') : Eff σ (Expr.region R e) σ'
  | alloc {σ a e σ'} (h : Eff σ e σ') : Eff σ (Expr.alloc a e) σ'
  | freeze {σ p b} : Eff σ (Expr.freeze p) (addBorrow σ b p Mode.frozen)
  | recoverCtx {σ e σ'} (h : Eff σ e σ') : Eff σ (Expr.recover e) σ'
  | recoverCtxConsume {σ e σ'} (h : Eff σ e σ') (b : Bid) :
      Eff σ (Expr.recover e) (ConsumeResult σ' [b])
  | borrow {σ p x e σ'} (h : Eff (addBorrow σ 0 p Mode.mut) e σ') :
      Eff σ (Expr.borrow p x e) σ'
  | drop {σ p} : Eff σ (Expr.drop p) (clearPlace σ p)
  | call {σ f a σ₁ body σ₂} (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ body σ₂) :
      Eff σ (Expr.call f a body) σ₂
  | ret {σ e σ'} (h : Eff σ e σ') : Eff σ (Expr.ret e) σ'
  | spawn {σ f e σ'} (h : Eff σ e σ') : Eff σ (Expr.spawn f e) σ'
  | atomic {σ p e σ'} (h : Eff σ e σ') : Eff σ (Expr.atomic p e) σ'
  | unsafeE {σ e σ'} (h : Eff σ e σ') : Eff σ (Expr.unsafeE e) σ'
  | deref {σ e σ'} (h : Eff σ e σ') : Eff σ (Expr.derefRaw e) σ'


def holdersOfV : Val → List Bid
  | Val.valH b => [b]
  | Val.refH b => [b]
  | _ => []

/-- Handle-carrying static effect: the last component is the set of result
    handles (`A`, analogous to the old `WT` output). -/
inductive EffH : Sigma → Expr → Sigma → List Bid → Prop where
  | val (σ : Sigma) (v : Val) : EffH σ (Expr.val v) σ (holdersOfV v)
  | var (σ : Sigma) (x : Var) : EffH σ (Expr.var x) σ []
  | abort (σ : Sigma) (k : Nat) : EffH σ (Expr.abort k) σ []
  | op {σ a σ₁ A₁ b σ₂ A₂}
      (h₁ : EffH σ a σ₁ A₁) (h₂ : EffH σ₁ b σ₂ A₂) :
      EffH σ (Expr.op a b) σ₂ A₂
  | letE {σ x a σ₁ A₁ b σ₂ A₂}
      (h₁ : EffH σ a σ₁ A₁) (h₂ : EffH σ₁ b σ₂ A₂) :
      EffH σ (Expr.letE x a b) σ₂ A₂
  | move {σ p} : EffH σ (Expr.move p) (clearPlace σ p) []
  | read {σ p b} : EffH σ (Expr.read p) (addBorrow σ b p Mode.frozen) [b]
  | write {σ p e σ' A} (h : EffH σ e σ' A) :
      EffH σ (Expr.write p e) (setHolders σ' p A) []
  | seq {σ a σ₁ A₁ b σ₂ A₂}
      (h₁ : EffH σ a σ₁ A₁) (h₂ : EffH σ₁ b σ₂ A₂) :
      EffH σ (Expr.seq a b) σ₂ A₂
  | region {σ R e σ' A} (h : EffH σ e σ' A) :
      EffH σ (Expr.region R e) σ' A
  | alloc {σ a e σ' A} (h : EffH σ e σ' A) :
      EffH σ (Expr.alloc a e) σ' []
  | freeze {σ p b} :
      EffH σ (Expr.freeze p) (addBorrow σ b p Mode.frozen) [b]
  | recover {σ b} :
      EffH σ (Expr.recover (Expr.val (Val.valH b))) (ConsumeResult σ [b]) []
  | recoverAny {σ v} (hnot : ∀ b, v ≠ Val.valH b) :
      EffH σ (Expr.recover (Expr.val v)) σ []
  | recoverCtx {σ e σ' A} (h : EffH σ e σ' A) :
      EffH σ (Expr.recover e) (ConsumeResult σ' A) []
  | borrow {σ p x e σ' A} (h : EffH (addBorrow σ 0 p Mode.mut) e σ' A) :
      EffH σ (Expr.borrow p x e) σ' A
  | drop {σ p} : EffH σ (Expr.drop p) (clearPlace σ p) []
  | call {σ f a σ₁ A₁ body σ₂ A₂}
      (h₁ : EffH σ a σ₁ A₁) (h₂ : EffH σ₁ body σ₂ A₂) :
      EffH σ (Expr.call f a body) σ₂ A₂
  | ret {σ e σ' A} (h : EffH σ e σ' A) : EffH σ (Expr.ret e) σ' A
  | spawn {σ f e σ' A} (h : EffH σ e σ' A) : EffH σ (Expr.spawn f e) σ' A
  | atomic {σ p e σ' A} (h : EffH σ e σ' A) : EffH σ (Expr.atomic p e) σ' A
  | unsafeE {σ e σ' A} (h : EffH σ e σ' A) : EffH σ (Expr.unsafeE e) σ' A
  | deref {σ e σ' A} (h : EffH σ e σ' A) : EffH σ (Expr.derefRaw e) σ' A

inductive EffStepEval : Sigma → Expr → Expr → Sigma → Prop where
  | val {σ : Sigma} {v : Val} : EffStepEval σ (Expr.val v) (Expr.val v) σ
  | var {σ : Sigma} {x : Var} {v : Val} :
      EffStepEval σ (Expr.var x) (Expr.val v) σ
  | abort {σ : Sigma} {k : Nat} : EffStepEval σ (Expr.abort k) (Expr.abort k) σ
  | op {σ : Sigma} {a b : Nat} :
      EffStepEval σ (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        (Expr.val (Val.nat (a + b))) σ
  | opAny {σ : Sigma} {v w : Val} :
      EffStepEval σ (Expr.op (Expr.val v) (Expr.val w)) (Expr.val (Val.nat 0)) σ
  | letV {σ : Sigma} {x : Var} {v : Val} {b : Expr} :
      EffStepEval σ (Expr.letE x (Expr.val v) b) b σ
  | seqV {σ : Sigma} {v : Val} {b : Expr} :
      EffStepEval σ (Expr.seq (Expr.val v) b) b σ
  | callV {σ : Sigma} {f : Nat} {v : Val} {body : Expr} :
      EffStepEval σ (Expr.call f (Expr.val v) body) body σ
  | freeze {σ : Sigma} {p : Place} {b : Bid} :
      EffStepEval σ (Expr.freeze p) (Expr.val (Val.valH b))
        (addBorrow σ b p Mode.frozen)
  | recover {σ : Sigma} {b : Bid} {l : Nat} :
      EffStepEval σ (Expr.recover (Expr.val (Val.valH b))) (Expr.val (Val.loc l))
        (ConsumeResult σ [b])
  | recoverAny {σ : Sigma} {v : Val} {l : Nat} :
      EffStepEval σ (Expr.recover (Expr.val v)) (Expr.val (Val.loc l)) σ
  | write {σ : Sigma} {p : Place} {v : Val} :
      EffStepEval σ (Expr.write p (Expr.val v)) (Expr.val Val.unit)
        (setHolders σ p (holdersOfV v))
  | alloc {σ : Sigma} {a : Nat} {v : Val} {l : Nat} :
      EffStepEval σ (Expr.alloc a (Expr.val v)) (Expr.val (Val.loc l)) σ
  | move {σ : Sigma} {p : Place} {v : Val} :
      EffStepEval σ (Expr.move p) (Expr.val v) (clearPlace σ p)
  | read {σ : Sigma} {p : Place} {b : Bid} {v : Val} :
      EffStepEval σ (Expr.read p) (Expr.val v) (addBorrow σ b p Mode.frozen)
  | drop {σ : Sigma} {p : Place} :
      EffStepEval σ (Expr.drop p) (Expr.val Val.unit) (clearPlace σ p)
  | regionV {σ : Sigma} {r : Rgn} {v : Val} :
      EffStepEval σ (Expr.region r (Expr.val v)) (Expr.val v) σ
  | retV {σ : Sigma} {v : Val} :
      EffStepEval σ (Expr.ret (Expr.val v)) (Expr.val v) σ
  | spawnV {σ : Sigma} {f : Nat} {v : Val} :
      EffStepEval σ (Expr.spawn f (Expr.val v)) (Expr.val Val.unit) σ
  | atomicV {σ : Sigma} {p : Place} {v : Val} :
      EffStepEval σ (Expr.atomic p (Expr.val v)) (Expr.val v) σ
  | unsafeV {σ : Sigma} {v : Val} :
      EffStepEval σ (Expr.unsafeE (Expr.val v)) (Expr.val v) σ
  | derefV {σ : Sigma} {l : Nat} {v : Val} :
      EffStepEval σ (Expr.derefRaw (Expr.val (Val.loc l))) (Expr.val v) σ
  | derefAny {σ : Sigma} {v : Val} :
      EffStepEval σ (Expr.derefRaw (Expr.val v)) (Expr.val (Val.nat 0)) σ
  | borrowEnter {σ : Sigma} {p : Place} {x : Var} {e : Expr} :
      EffStepEval σ (Expr.borrow p x e) e (addBorrow σ 0 p Mode.mut)
  | opL {σ : Sigma} {a b a' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ a a' σ₁) :
      EffStepEval σ (Expr.op a b) (Expr.op a' b) σ₁
  | opR {σ : Sigma} {a b b' : Expr} {σ₁ : Sigma}
      (hv : IsVal a) (h : EffStepEval σ b b' σ₁) :
      EffStepEval σ (Expr.op a b) (Expr.op a b') σ₁
  | letB {σ : Sigma} {x : Var} {a b a' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ a a' σ₁) :
      EffStepEval σ (Expr.letE x a b) (Expr.letE x a' b) σ₁
  | writeB {σ : Sigma} {p : Place} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.write p e) (Expr.write p e') σ₁
  | seqL {σ : Sigma} {a b a' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ a a' σ₁) :
      EffStepEval σ (Expr.seq a b) (Expr.seq a' b) σ₁
  | allocB {σ : Sigma} {a : Nat} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.alloc a e) (Expr.alloc a e') σ₁
  | regionB {σ : Sigma} {r : Rgn} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.region r e) (Expr.region r e') σ₁
  | recoverB {σ : Sigma} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.recover e) (Expr.recover e') σ₁
  | callB {σ : Sigma} {f : Nat} {a body a' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ a a' σ₁) :
      EffStepEval σ (Expr.call f a body) (Expr.call f a' body) σ₁
  | retB {σ : Sigma} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.ret e) (Expr.ret e') σ₁
  | spawnB {σ : Sigma} {f : Nat} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.spawn f e) (Expr.spawn f e') σ₁
  | atomicB {σ : Sigma} {p : Place} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.atomic p e) (Expr.atomic p e') σ₁
  | unsafeB {σ : Sigma} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.unsafeE e) (Expr.unsafeE e') σ₁
  | derefB {σ : Sigma} {e e' : Expr} {σ₁ : Sigma}
      (h : EffStepEval σ e e' σ₁) :
      EffStepEval σ (Expr.derefRaw e) (Expr.derefRaw e') σ₁

theorem isVal_eq {a : Expr} (h : IsVal a) : ∃ v, a = Expr.val v := by
  cases a with
  | val v => exact ⟨v, rfl⟩
  | _ => simp [IsVal] at h

/-- Step effect followed by residual effect equals the structural effect. -/
theorem effStepEval_eff_compose {σ σ' : Sigma} {e e' : Expr}
    (hstep : EffStepEval σ e e' σ') :
    ∀ σ'', Eff σ' e' σ'' → Eff σ e σ'' := by
  induction hstep with
  | val =>
      intro σ'' hres
      cases hres
      exact Eff.val _ _
  | var =>
      intro σ'' hres
      cases hres
      exact Eff.var _ _
  | abort =>
      intro σ'' hres
      cases hres
      exact Eff.abort _ _
  | op =>
      intro σ'' hres
      cases hres
      exact Eff.op (Eff.val _ _) (Eff.val _ _)
  | opAny =>
      intro σ'' hres
      cases hres
      exact Eff.op (Eff.val _ _) (Eff.val _ _)
  | letV =>
      intro σ'' hres
      exact Eff.letE (Eff.val _ _) hres
  | seqV =>
      intro σ'' hres
      exact Eff.seq (Eff.val _ _) hres
  | callV =>
      intro σ'' hres
      exact Eff.call (Eff.val _ _) hres
  | freeze =>
      intro σ'' hres
      cases hres
      exact Eff.freeze
  | recover =>
      intro σ'' hres
      cases hres
      exact Eff.recoverCtxConsume (Eff.val _ _) _
  | recoverAny =>
      intro σ'' hres
      cases hres
      exact Eff.recoverCtx (Eff.val _ _)
  | write =>
      intro σ'' hres
      cases hres
      exact Eff.write (A := holdersOfV _) (Eff.val _ _)
  | alloc =>
      intro σ'' hres
      cases hres
      exact Eff.alloc (Eff.val _ _)
  | move =>
      intro σ'' hres
      cases hres
      exact Eff.move
  | read =>
      intro σ'' hres
      cases hres
      exact Eff.read
  | drop =>
      intro σ'' hres
      cases hres
      exact Eff.drop
  | regionV =>
      intro σ'' hres
      cases hres
      exact Eff.region (Eff.val _ _)
  | retV =>
      intro σ'' hres
      cases hres
      exact Eff.ret (Eff.val _ _)
  | spawnV =>
      intro σ'' hres
      cases hres
      exact Eff.spawn (Eff.val _ _)
  | atomicV =>
      intro σ'' hres
      cases hres
      exact Eff.atomic (Eff.val _ _)
  | unsafeV =>
      intro σ'' hres
      cases hres
      exact Eff.unsafeE (Eff.val _ _)
  | derefV =>
      intro σ'' hres
      cases hres
      exact Eff.deref (Eff.val _ _)
  | derefAny =>
      intro σ'' hres
      cases hres
      exact Eff.deref (Eff.val _ _)
  | borrowEnter =>
      intro σ'' hres
      exact Eff.borrow hres
  | opL h ih =>
      intro σ'' hres
      cases hres with
      | op h1 h2 => exact Eff.op (ih _ h1) h2
  | opR hv h ih =>
      intro σ'' hres
      cases hres with
      | op h1 h2 =>
          cases isVal_eq hv with
          | intro v hv' =>
              cases hv'
              cases h1
              exact Eff.op (Eff.val _ _) (ih _ h2)
  | letB h ih =>
      intro σ'' hres
      cases hres with
      | letE h1 h2 => exact Eff.letE (ih _ h1) h2
  | writeB h ih =>
      intro σ'' hres
      cases hres with
      | write h1 => exact Eff.write (ih _ h1)
  | seqL h ih =>
      intro σ'' hres
      cases hres with
      | seq h1 h2 => exact Eff.seq (ih _ h1) h2
  | allocB h ih =>
      intro σ'' hres
      cases hres with
      | alloc h1 => exact Eff.alloc (ih _ h1)
  | regionB h ih =>
      intro σ'' hres
      cases hres with
      | region h1 => exact Eff.region (ih _ h1)
  | recoverB h ih =>
      intro σ'' hres
      cases hres with
      | recoverCtx h1 => exact Eff.recoverCtx (ih _ h1)
      | recoverCtxConsume h1 b => exact Eff.recoverCtxConsume (ih _ h1) b
  | callB h ih =>
      intro σ'' hres
      cases hres with
      | call h1 h2 => exact Eff.call (ih _ h1) h2
  | retB h ih =>
      intro σ'' hres
      cases hres with
      | ret h1 => exact Eff.ret (ih _ h1)
  | spawnB h ih =>
      intro σ'' hres
      cases hres with
      | spawn h1 => exact Eff.spawn (ih _ h1)
  | atomicB h ih =>
      intro σ'' hres
      cases hres with
      | atomic h1 => exact Eff.atomic (ih _ h1)
  | unsafeB h ih =>
      intro σ'' hres
      cases hres with
      | unsafeE h1 => exact Eff.unsafeE (ih _ h1)
  | derefB h ih =>
      intro σ'' hres
      cases hres with
      | deref h1 => exact Eff.deref (ih _ h1)


/-- Effect of the context **before** the hole (parameterized by the hole expression). -/

inductive EffPre : Ctx → Expr → Sigma → Sigma → Prop where
  | hole {e σ} : EffPre Ctx.hole e σ σ
  | opL {c b e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.opL c b) e σ σ₁
  | opR {a c e} (ha : Eff σ a σ₁) (hc : EffPre c e σ₁ σ₂) :
      EffPre (Ctx.opR a c) e σ σ₂
  | letB {x c b e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.letB x c b) e σ σ₁
  | writeB {p c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.writeB p c) e σ σ₁
  | seqL {c b e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.seqL c b) e σ σ₁
  | allocB {a c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.allocB a c) e σ σ₁
  | regionB {r c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.regionB r c) e σ σ₁
  | recoverB {c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.recoverB c) e σ σ₁
  | borrowB {p x c e} (hc : EffPre c e (addBorrow σ 0 p Mode.mut) σ₁) :
      EffPre (Ctx.borrowB p x c) e σ σ₁
  | callB {f c body e} (hc : EffPre c e σ σ₁) :
      EffPre (Ctx.callB f c body) e σ σ₁
  | retB {c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.retB c) e σ σ₁
  | spawnB {f c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.spawnB f c) e σ σ₁
  | atomicB {p c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.atomicB p c) e σ σ₁
  | unsafeB {c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.unsafeB c) e σ σ₁
  | derefB {c e} (hc : EffPre c e σ σ₁) : EffPre (Ctx.derefB c) e σ σ₁

/-- Effect of the context **after** the hole (parameterized by the hole expression). -/
inductive EffPost : Ctx → Expr → Sigma → Sigma → Prop where
  | hole {e σ} : EffPost Ctx.hole e σ σ
  | opL {c b e} (hc : EffPost c e σ σ₁) (hb : Eff σ₁ b σ₂) :
      EffPost (Ctx.opL c b) e σ σ₂
  | opR {a c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.opR a c) e σ σ₁
  | letB {x c b e} (hc : EffPost c e σ σ₁) (hb : Eff σ₁ b σ₂) :
      EffPost (Ctx.letB x c b) e σ σ₂
  | writeB {p c e A} (hc : EffPost c e σ σ₁) :
      EffPost (Ctx.writeB p c) e σ (setHolders σ₁ p A)
  | seqL {c b e} (hc : EffPost c e σ σ₁) (hb : Eff σ₁ b σ₂) :
      EffPost (Ctx.seqL c b) e σ σ₂
  | allocB {a c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.allocB a c) e σ σ₁
  | regionB {r c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.regionB r c) e σ σ₁
  | recoverB {c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.recoverB c) e σ σ₁
  | recoverBConsume {c e b} (hc : EffPost c e σ σ₁) :
      EffPost (Ctx.recoverB c) e σ (ConsumeResult σ₁ [b])
  | borrowB {p x c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.borrowB p x c) e σ σ₁
  | callB {f c body e} (hc : EffPost c e σ σ₁) (hb : Eff σ₁ body σ₂) :
      EffPost (Ctx.callB f c body) e σ σ₂
  | retB {c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.retB c) e σ σ₁
  | spawnB {f c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.spawnB f c) e σ σ₁
  | atomicB {p c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.atomicB p c) e σ σ₁
  | unsafeB {c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.unsafeB c) e σ σ₁
  | derefB {c e} (hc : EffPost c e σ σ₁) : EffPost (Ctx.derefB c) e σ σ₁

/-- Decomposition of the full effect of a plugged expression into the effect
    before the hole, the hole's effect, and the effect after the hole. -/
theorem eff_plug_decomp {σ : Sigma} {C : Ctx} {e : Expr} {σ' : Sigma}
    (h : Eff σ (plug C e) σ') :
    ∃ σ_h σ_a, EffPre C e σ σ_h ∧ Eff σ_h e σ_a ∧ EffPost C e σ_a σ' := by
  induction C generalizing σ σ' e with
  | hole => exact ⟨σ, σ', EffPre.hole, h, EffPost.hole⟩
  | opL c b =>
      rename_i ih
      cases h with
      | op h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.opL hpre, heff, EffPost.opL hpost h2⟩
  | opR a c =>
      rename_i ih
      cases h with
      | op h1 h2 =>
          cases ih h2 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.opR h1 hpre, heff, EffPost.opR hpost⟩
  | letB x c b =>
      rename_i ih
      cases h with
      | letE h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.letB hpre, heff, EffPost.letB hpost h2⟩
  | writeB p c =>
      rename_i ih
      cases h with
      | write h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.writeB hpre, heff, EffPost.writeB hpost⟩
  | seqL c b =>
      rename_i ih
      cases h with
      | seq h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.seqL hpre, heff, EffPost.seqL hpost h2⟩
  | allocB a c =>
      rename_i ih
      cases h with
      | alloc h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.allocB hpre, heff, EffPost.allocB hpost⟩
  | regionB r c =>
      rename_i ih
      cases h with
      | region h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.regionB hpre, heff, EffPost.regionB hpost⟩
  | recoverB c =>
      rename_i ih
      cases h with
      | recoverCtx h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.recoverB hpre, heff,
                            EffPost.recoverB hpost⟩
      | recoverCtxConsume h1 b =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.recoverB hpre, heff,
                            EffPost.recoverBConsume hpost⟩
  | borrowB p x c =>
      rename_i ih
      cases h with
      | borrow h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.borrowB hpre, heff, EffPost.borrowB hpost⟩
  | callB f c body =>
      rename_i ih
      cases h with
      | call h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.callB hpre, heff, EffPost.callB hpost h2⟩
  | retB c =>
      rename_i ih
      cases h with
      | ret h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.retB hpre, heff, EffPost.retB hpost⟩
  | spawnB f c =>
      rename_i ih
      cases h with
      | spawn h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.spawnB hpre, heff, EffPost.spawnB hpost⟩
  | atomicB p c =>
      rename_i ih
      cases h with
      | atomic h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.atomicB hpre, heff, EffPost.atomicB hpost⟩
  | unsafeB c =>
      rename_i ih
      cases h with
      | unsafeE h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.unsafeB hpre, heff, EffPost.unsafeB hpost⟩
  | derefB c =>
      rename_i ih
      cases h with
      | deref h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro hpre rest =>
                      cases rest with
                      | intro heff hpost =>
                          exact ⟨σ_h, σ_a, EffPre.derefB hpre, heff, EffPost.derefB hpost⟩
/-- Composition inverse of `eff_plug_decomp`. -/
theorem eff_plug_compose {σ σ_h σ_a σ' : Sigma} {C : Ctx} {e : Expr}
    (hpre : EffPre C e σ σ_h) (heff : Eff σ_h e σ_a) (hpost : EffPost C e σ_a σ') :
    Eff σ (plug C e) σ' := by
  induction C generalizing σ σ_h σ_a σ' with
  | hole =>
      cases hpre
      cases hpost
      exact heff
  | opL c b =>
      rename_i ih
      cases hpre with
      | opL hpre_c=>
          cases hpost with
          | opL hpost_c hb=>
              exact Eff.op (ih hpre_c heff hpost_c) hb
  | opR a c =>
      rename_i ih
      cases hpre with
      | opR ha hpre_c =>
          cases hpost with
          | opR hpost_c=>
              exact Eff.op ha (ih hpre_c heff hpost_c)
  | letB x c b =>
      rename_i ih
      cases hpre with
      | letB hpre_c=>
          cases hpost with
          | letB hpost_c hb=>
              exact Eff.letE (ih hpre_c heff hpost_c) hb
  | writeB p c =>
      rename_i ih
      cases hpre with
      | writeB hpre_c=>
          cases hpost with
          | writeB hpost_c=>
              exact Eff.write (ih hpre_c heff hpost_c)
  | seqL c b =>
      rename_i ih
      cases hpre with
      | seqL hpre_c=>
          cases hpost with
          | seqL hpost_c hb=>
              exact Eff.seq (ih hpre_c heff hpost_c) hb
  | allocB a c =>
      rename_i ih
      cases hpre with
      | allocB hpre_c=>
          cases hpost with
          | allocB hpost_c=>
              exact Eff.alloc (ih hpre_c heff hpost_c)
  | regionB r c =>
      rename_i ih
      cases hpre with
      | regionB hpre_c=>
          cases hpost with
          | regionB hpost_c=>
              exact Eff.region (ih hpre_c heff hpost_c)
  | recoverB c =>
      rename_i ih
      cases hpre with
      | recoverB hpre_c =>
          cases hpost with
          | recoverB hpost_c =>
              exact Eff.recoverCtx (ih hpre_c heff hpost_c)
          | recoverBConsume hpost_c =>
              exact Eff.recoverCtxConsume (ih hpre_c heff hpost_c) _
  | borrowB p x c =>
      rename_i ih
      cases hpre with
      | borrowB hpre_c=>
          cases hpost with
          | borrowB hpost_c=>
              exact Eff.borrow (ih hpre_c heff hpost_c)
  | callB f c body =>
      rename_i ih
      cases hpre with
      | callB hpre_c=>
          cases hpost with
          | callB hpost_c hb=>
              exact Eff.call (ih hpre_c heff hpost_c) hb
  | retB c =>
      rename_i ih
      cases hpre with
      | retB hpre_c=>
          cases hpost with
          | retB hpost_c=>
              exact Eff.ret (ih hpre_c heff hpost_c)
  | spawnB f c =>
      rename_i ih
      cases hpre with
      | spawnB hpre_c=>
          cases hpost with
          | spawnB hpost_c=>
              exact Eff.spawn (ih hpre_c heff hpost_c)
  | atomicB p c =>
      rename_i ih
      cases hpre with
      | atomicB hpre_c=>
          cases hpost with
          | atomicB hpost_c=>
              exact Eff.atomic (ih hpre_c heff hpost_c)
  | unsafeB c =>
      rename_i ih
      cases hpre with
      | unsafeB hpre_c=>
          cases hpost with
          | unsafeB hpost_c=>
              exact Eff.unsafeE (ih hpre_c heff hpost_c)
  | derefB c =>
      rename_i ih
      cases hpre with
      | derefB hpre_c=>
          cases hpost with
          | derefB hpost_c=>
              exact Eff.deref (ih hpre_c heff hpost_c)

/-- Context step effect: prefix, hole step, suffix. -/
inductive EffStepCtx : Sigma → Ctx → Expr → Expr → Sigma → Prop where
  | step {σ σ_h σ_a σ' : Sigma} {C : Ctx} {e e' : Expr}
      (hpre : EffPre C e σ σ_h)
      (hstep : EffStepEval σ_h e e' σ_a)
      (hpost : EffPost C e' σ_a σ') :
      EffStepCtx σ C e e' σ'

theorem effStepCtx_decomp {σ σ' : Sigma} {C : Ctx} {e e' : Expr}
    (h : EffStepCtx σ C e e' σ') :
    ∃ σ_h σ_a, EffPre C e σ σ_h ∧ EffStepEval σ_h e e' σ_a ∧ EffPost C e' σ_a σ' := by
  cases h with
  | step hpre hstep hpost => exact ⟨_, _, hpre, hstep, hpost⟩


/-- `EffPost` does not inspect the hole expression; only its parameter changes. -/
theorem effPost_congr {C : Ctx} {e e' : Expr} {σ σ' : Sigma}
    (h : EffPost C e' σ σ') : EffPost C e σ σ' := by
  induction h with
  | hole => exact EffPost.hole
  | opL hc hb =>
      rename_i ih
      exact EffPost.opL ih hb
  | opR hc =>
      rename_i ih
      exact EffPost.opR ih
  | letB hc hb =>
      rename_i ih
      exact EffPost.letB ih hb
  | writeB hc =>
      rename_i ih
      exact EffPost.writeB ih
  | seqL hc hb =>
      rename_i ih
      exact EffPost.seqL ih hb
  | allocB hc =>
      rename_i ih
      exact EffPost.allocB ih
  | regionB hc =>
      rename_i ih
      exact EffPost.regionB ih
  | recoverB hc =>
      rename_i ih
      exact EffPost.recoverB ih
  | recoverBConsume hc =>
      rename_i ih
      exact EffPost.recoverBConsume ih
  | borrowB hc =>
      rename_i ih
      exact EffPost.borrowB ih
  | callB hc hb =>
      rename_i ih
      exact EffPost.callB ih hb
  | retB hc =>
      rename_i ih
      exact EffPost.retB ih
  | spawnB hc =>
      rename_i ih
      exact EffPost.spawnB ih
  | atomicB hc =>
      rename_i ih
      exact EffPost.atomicB ih
  | unsafeB hc =>
      rename_i ih
      exact EffPost.unsafeB ih
  | derefB hc =>
      rename_i ih
      exact EffPost.derefB ih

def RegionSafe (σ : Sigma) (R : Rgn) (e : Expr) : Prop :=
  ∀ σ', Eff σ e σ' → NoEscape σ' R

theorem regionSafe_val {σ R v} (hno : NoEscape σ R) :
    RegionSafe σ R (Expr.val v) := by
  intro σ' heff
  cases heff
  exact hno

theorem regionSafe_var {σ R x} (hno : NoEscape σ R) :
    RegionSafe σ R (Expr.var x) := by
  intro σ' heff
  cases heff
  exact hno

theorem regionSafe_abort {σ R k} (hno : NoEscape σ R) :
    RegionSafe σ R (Expr.abort k) := by
  intro σ' heff
  cases heff
  exact hno

theorem regionSafe_freeze {σ R p} (hno : NoEscape σ R)
    (hr : rgnOf σ p ≠ R) : RegionSafe σ R (Expr.freeze p) := by
  intro σ' heff
  cases heff
  intro br hmem hrg
  cases hmem with
  | head => exact hr hrg
  | tail _ htail => exact hno br htail hrg

theorem regionSafe_seq {σ R a b}
    (_ha : RegionSafe σ R a)
    (hb : ∀ σ₁, Eff σ a σ₁ → RegionSafe σ₁ R b) :
    RegionSafe σ R (Expr.seq a b) := by
  intro σ' heff
  cases heff with
  | seq h1 h2 =>
      exact (hb _ h1) σ' h2


/-- Region safety of a context around a hole expression. -/
def CtxSafe (σ : Sigma) (R : Rgn) (C : Ctx) (e : Expr) : Prop :=
  ∀ σ_f,
    (∃ σ_h σ_a,
      EffPre C e σ σ_h ∧ Eff σ_h e σ_a ∧ EffPost C e σ_a σ_f) →
    NoEscape σ_f R

theorem regionSafe_to_ctxSafe {σ : Sigma} {R : Rgn} {C : Ctx} {e : Expr}
    (hsafe : RegionSafe σ R (plug C e)) : CtxSafe σ R C e := by
  intro σ_f h
  cases h with
  | intro σ_h rest =>
      cases rest with
      | intro σ_a rest =>
          cases rest with
          | intro hpre rest =>
              cases rest with
              | intro heff hpost =>
                  exact hsafe σ_f (eff_plug_compose hpre heff hpost)


/-- Hole-relative region-safety preservation: prefix, hole step, residual
    effect, and suffix. -/
theorem regionSafe_ctx_hole {σ : Sigma} {R : Rgn} {C : Ctx} {e e' : Expr}
    {σ_h σ_a σ_b σ_f : Sigma}
    (hctx : CtxSafe σ R C e)
    (hpre : EffPre C e σ σ_h)
    (hstep : EffStepEval σ_h e e' σ_a)
    (heff : Eff σ_a e' σ_b)
    (hpost : EffPost C e' σ_b σ_f) :
    NoEscape σ_f R := by
  have hEff : Eff σ_h e σ_b := effStepEval_eff_compose hstep σ_b heff
  have hPost : EffPost C e σ_b σ_f := effPost_congr hpost
  exact hctx σ_f ⟨σ_h, σ_b, hpre, hEff, hPost⟩

/-- `regionSafe_step` in hole-relative form. -/
theorem regionSafe_step {σ : Sigma} {R : Rgn} {C : Ctx} {e e' : Expr}
    {σ_h σ_a σ_b σ_f : Sigma}
    (hsafe : RegionSafe σ R (plug C e))
    (hpre : EffPre C e σ σ_h)
    (hstep : EffStepEval σ_h e e' σ_a)
    (heff : Eff σ_a e' σ_b)
    (hpost : EffPost C e' σ_b σ_f) :
    NoEscape σ_f R :=
  regionSafe_ctx_hole (regionSafe_to_ctxSafe hsafe) hpre hstep heff hpost

end Effect
end LSys
