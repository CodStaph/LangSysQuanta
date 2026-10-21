/-
  LSys/Preservation.lean

  Static effects, static/dynamic matching, and the combined preservation step.

  * `Eff σ e σ'` — the static state update of `e` (separate from `WT`, which is
    input-only).
  * `MatchU σ c s` — `Σ` matches the runtime configuration `c : ConfE` and the
    expression state `s : State`.
  * `StepPM` — the combined relation: `Match` + expression step + runtime step
    + `RedexOK` + `Eff`.

  This file defines the relations and their projections.  The preservation
  theorem itself is a separate obligation:

    `Preservation σ :=
       WT σ e → MatchU σ c s → StepPM σ c e s σ' c' e' s' →
         WT σ' e' ∧ MatchU σ' c' s'`
-/

import LSys.Unified
import LSys.Adequacy
import LSys.TypedStep

namespace LSys

set_option linter.unusedVariables false

/-! ## Static effect `Eff` -/

inductive Eff : Sigma → Expr → Sigma → Prop where
  | val (σ : Sigma) (v : Val) : Eff σ (Expr.val v) σ
  | var (σ : Sigma) (x : Var) : Eff σ (Expr.var x) σ
  | abort (σ : Sigma) (k : Nat) : Eff σ (Expr.abort k) σ
  | op {σ : Sigma} {a : Expr} {σ₁ : Sigma} {b : Expr} {σ₂ : Sigma}
      (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ b σ₂) :
      Eff σ (Expr.op a b) σ₂
  | letE {σ : Sigma} {x : Var} {a : Expr} {σ₁ : Sigma} {b : Expr} {σ₂ : Sigma}
      (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ b σ₂) :
      Eff σ (Expr.letE x a b) σ₂
  | move {σ : Sigma} {p : Place} :
      Eff σ (Expr.move p) (clearPlace σ p)
  | read {σ : Sigma} {p : Place} {b : Bid} :
      Eff σ (Expr.read p) (addBorrow σ b p Mode.frozen)
  | write {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma} {A : List Bid}
      (h : Eff σ e σ') :
      Eff σ (Expr.write p e) (setHolders σ' p A)
  | seq {σ : Sigma} {a : Expr} {σ₁ : Sigma} {b : Expr} {σ₂ : Sigma}
      (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ b σ₂) :
      Eff σ (Expr.seq a b) σ₂
  | region {σ : Sigma} {R : Rgn} {e : Expr} {σ' : Sigma}
      (h : Eff σ e σ') :
      Eff σ (Expr.region R e) σ'
  | alloc {σ : Sigma} {a : Nat} {e : Expr} {σ' : Sigma}
      (h : Eff σ e σ') :
      Eff σ (Expr.alloc a e) σ'
  | freeze {σ : Sigma} {p : Place} {b : Bid} :
      Eff σ (Expr.freeze p) (addBorrow σ b p Mode.frozen)
  | recover {σ : Sigma} {b : Bid} :
      Eff σ (Expr.recover (Expr.val (Val.valH b))) (ConsumeResult σ [b])
  | borrow {σ : Sigma} {p : Place} {x : Var} {e : Expr} {σ' : Sigma}
      (h : Eff (addBorrow σ 0 p Mode.mut) e σ') :
      Eff σ (Expr.borrow p x e) σ'
  | drop {σ : Sigma} {p : Place} :
      Eff σ (Expr.drop p) (clearPlace σ p)
  | call {σ : Sigma} {f : Nat} {a : Expr} {σ₁ : Sigma} {body : Expr} {σ₂ : Sigma}
      (h₁ : Eff σ a σ₁) (h₂ : Eff σ₁ body σ₂) :
      Eff σ (Expr.call f a body) σ₂
  | ret {σ : Sigma} {e : Expr} {σ' : Sigma}
      (h : Eff σ e σ') : Eff σ (Expr.ret e) σ'
  | spawn {σ : Sigma} {f : Nat} {e : Expr} {σ' : Sigma}
      (h : Eff σ e σ') : Eff σ (Expr.spawn f e) σ'
  | atomic {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma}
      (h : Eff σ e σ') : Eff σ (Expr.atomic p e) σ'
  | unsafeE {σ : Sigma} {e : Expr} {σ' : Sigma}
      (h : Eff σ e σ') : Eff σ (Expr.unsafeE e) σ'
  | deref {σ : Sigma} {e : Expr} {σ' : Sigma}
      (h : Eff σ e σ') : Eff σ (Expr.derefRaw e) σ'

/-! ## Static/dynamic matching -/

/-- Static holder set for a runtime occurrence position.  A heap `l` is the
    static place `[l]`; an environment variable `x` is `varPlace x = [0, x]`,
    which is disjoint from heap places (lengths 1 vs 2). -/
def holdsInSigma (σ : Sigma) (o : Occ) : Prop :=
  match o.pos with
  | HoldPos.heap l => IsHolder σ [l] o.bid
  | HoldPos.env x => IsHolder σ (varPlace x) o.bid

/-- `Σ` is matched by the runtime configuration `c` and state `s`. -/
structure MatchU (σ : Sigma) (c : ConfE) (s : State) : Prop where
  gamma_dom : ∀ x : Var,
    (lookupPlace σ.gamma (varPlace x)).isSome = (c.env x).isSome
  btab_sound : ∀ e, e ∈ c.btab →
    ∃ br, br ∈ σ.lam ∧ br.bid = e.bid ∧ br.place = [e.target] ∧ br.mode = e.mode
  btab_complete : ∀ br, br ∈ σ.lam →
    ∃ e, e ∈ c.btab ∧ e.bid = br.bid ∧ [e.target] = br.place ∧ e.mode = br.mode
  holders : ∀ o, HoldOccurs c o ↔ holdsInSigma σ o
  borrow : s.borrow = c.flight.length

/-- `MatchU` is preserved when a borrow frame is pushed (flight grows). -/
theorem MatchU.borrowPush {σ : Sigma} {c : ConfE} {s : State} {b : Bid}
    (hm : MatchU σ c s) :
    MatchU σ { c with flight := b :: c.flight }
      (State.mk (s.borrow + 1)) := by
  have hb : s.borrow + 1 = (b :: c.flight).length := by
    rw [hm.borrow, List.length_cons]
  exact ⟨hm.gamma_dom, hm.btab_sound, hm.btab_complete, hm.holders, hb⟩

/-- `MatchU` is preserved when a borrow frame is popped (flight shrinks). -/
theorem MatchU.borrowPop {σ : Sigma} {c : ConfE} {b : Bid} {n : Nat}
    (hm : MatchU σ { c with flight := b :: c.flight } (State.mk (n + 1))) :
    MatchU σ c (State.mk n) := by
  have hb : n = c.flight.length := by
    have h := hm.borrow
    rw [List.length_cons] at h
    exact Nat.succ.inj h
  exact ⟨hm.gamma_dom, hm.btab_sound, hm.btab_complete, hm.holders, hb⟩


/-- Subset-domain matching: every statically bound variable is runtime-bound.
    Runtime `let`/`borrow` may add fresh bindings, so domain *equality* is too
    strong; the subset direction is the soundness-critical one. -/
structure MatchUS (σ : Sigma) (c : ConfE) (s : State) : Prop where
  gamma_dom_sub : ∀ x,
    (lookupPlace σ.gamma (varPlace x)).isSome = true → (c.env x).isSome = true
  btab_sound : ∀ e, e ∈ c.btab →
    ∃ br, br ∈ σ.lam ∧ br.bid = e.bid ∧ br.place = [e.target] ∧ br.mode = e.mode
  btab_complete : ∀ br, br ∈ σ.lam →
    ∃ e, e ∈ c.btab ∧ e.bid = br.bid ∧ [e.target] = br.place ∧ e.mode = br.mode
  holders : ∀ o, HoldOccurs c o ↔ holdsInSigma σ o
  borrow : s.borrow = c.flight.length

theorem MatchU.toMatchUS {σ : Sigma} {c : ConfE} {s : State}
    (hm : MatchU σ c s) : MatchUS σ c s :=
  ⟨fun x hx => by rw [← hm.gamma_dom x]; exact hx,
    hm.btab_sound, hm.btab_complete, hm.holders, hm.borrow⟩

/-- `MatchUS` is preserved when a borrow frame is pushed. -/
theorem MatchUS.borrowPush {σ : Sigma} {c : ConfE} {s : State} {b : Bid}
    (hm : MatchUS σ c s) :
    MatchUS σ { c with flight := b :: c.flight } (State.mk (s.borrow + 1)) := by
  have hb : s.borrow + 1 = (b :: c.flight).length := by
    rw [hm.borrow, List.length_cons]
  exact ⟨hm.gamma_dom_sub, hm.btab_sound, hm.btab_complete, hm.holders, hb⟩

/-- `MatchUS` is preserved when a borrow frame is popped. -/
theorem MatchUS.borrowPop {σ : Sigma} {c : ConfE} {b : Bid} {n : Nat}
    (hm : MatchUS σ { c with flight := b :: c.flight } (State.mk (n + 1))) :
    MatchUS σ c (State.mk n) := by
  have hb : n = c.flight.length := by
    have h := hm.borrow
    rw [List.length_cons] at h
    exact Nat.succ.inj h
  exact ⟨hm.gamma_dom_sub, hm.btab_sound, hm.btab_complete, hm.holders, hb⟩

/-- Runtime `let` of a **non-handle** value preserves `MatchUS`: the runtime
    environment only grows (subset domain), the value has no holder
    occurrences, and `flight` is unchanged. -/
theorem MatchUS.letVar {σ : Sigma} {c : ConfE} {s : State} {x : Var}
    {v : RVal} (hm : MatchUS σ c s) (hfreshH : c.envHolds x = none)
    (hV : holdersOfVal v = []) :
    MatchUS σ (LSys.letVar c x v) s := by
  constructor
  · -- static domain ⊆ runtime domain: the runtime env only grows
    intro y hy
    cases Nat.decEq y x with
    | isTrue hxy =>
        cases hxy
        have : (LSys.letVar c x v).env x = some v := by
          dsimp only [LSys.letVar]
          rw [setEnv_same]
        rw [this]
        rfl
    | isFalse hxy =>
        have hlt : (LSys.letVar c x v).env y = c.env y := by
          dsimp only [LSys.letVar]
          rw [setEnv_other hxy]
        rw [hlt]
        exact hm.gamma_dom_sub y hy
  · exact hm.btab_sound
  · exact hm.btab_complete
  · -- holder occurrences: only the fresh `env x` entry changes, and it is empty
    intro o
    cases o with
    | mk pos bid =>
        cases pos with
        | heap l => exact hm.holders _
        | env y =>
            cases Nat.decEq y x with
            | isTrue hxy =>
                cases hxy
                have hlt : holdsAtPos (LSys.letVar c x v) (HoldPos.env x) = [] := by
                  simp [LSys.letVar, holdsAtPos, hV]
                have hlc : holdsAtPos c (HoldPos.env x) = [] := by
                  simp [holdsAtPos, hfreshH]
                constructor
                · intro hb
                  unfold HoldOccurs at hb
                  rw [hlt] at hb
                  cases hb
                · intro hb
                  have hc : HoldOccurs c (Occ.mk (HoldPos.env x) bid) :=
                    (hm.holders _).mpr hb
                  unfold HoldOccurs at hc
                  rw [hlc] at hc
                  cases hc
            | isFalse hxy =>
                have hlt : holdsAtPos (LSys.letVar c x v) (HoldPos.env y)
                    = holdsAtPos c (HoldPos.env y) := by
                  simp [LSys.letVar, holdsAtPos, hxy]
                unfold HoldOccurs
                rw [hlt]
                exact hm.holders (Occ.mk (HoldPos.env y) bid)
  · exact hm.borrow

/-- Project a unified configuration to the heap/btab/flight core. -/
def ConfE.toConf (c : ConfE) : Conf :=
  { heap := c.heap, btab := c.btab, flight := c.flight }

def liftConf (c : ConfE) (c' : Conf) : ConfE :=
  { c' with env := c.env, envHolds := c.envHolds }

/-- Runtime steps on the unified configuration: environment operations plus
    heap/borrow-table steps lifted through `ConfE.toConf`. -/
inductive RStepE : ConfE → ConfE → Prop where
  | refl : RStepE c c
  | letVar {c : ConfE} {x : Var} {v : RVal} (hfresh : c.env x = none) :
      RStepE c (letVar c x v)
  | moveVar {c : ConfE} {x : Var} {v : RVal} :
      RStepE c (moveVar c x v)
  | borrowVar {c : ConfE} {l : Loc} {x : Var} {b : Bid}
      (hfresh : c.env x = none) :
      RStepE c (borrowVar c l x b)
  | borrowPush {c : ConfE} {b : Bid} :
      RStepE c { c with flight := b :: c.flight }
  | borrowPop {c : ConfE} {b : Bid} :
      RStepE { c with flight := b :: c.flight } c
  | heap {c : ConfE} {c' : Conf} (h : RStep c.toConf c') :
      RStepE c (liftConf c c')

/-! ## Combined step -/

/-- Combined preservation step: matching configuration, expression step,
    runtime step, static redex condition, and static effect. -/
def StepPM (σ : Sigma) (c : ConfE) (e : Expr) (s : State)
    (σ' : Sigma) (c' : ConfE) (e' : Expr) (s' : State) : Prop :=
  MatchU σ c s ∧
  Step e s e' s' ∧
  RStepE c c' ∧
  RedexOK σ e ∧
  Eff σ e σ'

theorem stepPM_match {σ c e s σ' c' e' s'}
    (h : StepPM σ c e s σ' c' e' s') : MatchU σ c s :=
  h.1

theorem stepPM_expr {σ c e s σ' c' e' s'}
    (h : StepPM σ c e s σ' c' e' s') : Step e s e' s' :=
  h.2.1

theorem stepPM_runtime {σ c e s σ' c' e' s'}
    (h : StepPM σ c e s σ' c' e' s') : RStepE c c' :=
  h.2.2.1

theorem stepPM_redex {σ c e s σ' c' e' s'}
    (h : StepPM σ c e s σ' c' e' s') : RedexOK σ e :=
  h.2.2.2.1

theorem stepPM_eff {σ c e s σ' c' e' s'}
    (h : StepPM σ c e s σ' c' e' s') : Eff σ e σ' :=
  h.2.2.2.2

/-- Target preservation statement (not yet proved). -/
def Preservation (σ : Sigma) : Prop :=
  ∀ {e c s σ' c' e' s'},
    WT σ e →
    MatchU σ c s →
    StepPM σ c e s σ' c' e' s' →
    WT σ' e' ∧ MatchU σ' c' s'

end LSys
