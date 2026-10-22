/-
  LSys/Stack.lean

  T4d of `spec/semantics.md` (the T4 table): the runtime model for
  **UB-13 (stack overflow)** and for the `W-LS-STACK` depth budget.

  Four layers:

  1. **Depth accounting** — `StackConf = (depth, budget)`, `Fits`,
     `push`/`pop`, and the UB-13 event `StackEvent … UBCode.stack`.  Two
     oracles: `fits_or_overflow` (the check is total) and
     `no_overflow_within` (`depth ≤ budget` rules the event out).

  2. **Guarded runs** — `StackStar` records only entries/exits that passed the
     budget check; a run from a fitting start stays fitting
     (`StackStar.fits`), hence UB-13 is unreachable (`no_overflow_reachable`,
     the T4d analogue of `Runtime.no_uninit_reachable`).

  3. **The core** — `StackStepCK` annotates every `EffHStepEvalCK` step with
     its frame action: `push` for the `callV` redex, `pop` for the `retV`
     redex, `neutral` for everything else **including abort propagation**
     (LSys aborts without unwinding, see `00 §6.6` — so an abort does not pop
     the frame).  Each step preserves the budget (`StackStepCK.fits`) and the
     outcome-typed typing (`StackStepCK.wt`, via `WTKH.preserved`).

  4. **Dossier B numbers** — the static `#[recursion(bound = N)]` check
     `bound * frame < stack` implies the runtime frame budget fits
     (`static_bound_fits`); `bound = 8` fits an 8 KiB stack with 128-byte
     frames, `bound = 64` does not (`bound64_rejected`), matching
     `dossiers/recursion/`.

  Axiom discipline: no `by_cases`/`Classical`; every case split goes through
  `Nat.lt_or_ge`.
-/

import LSys.UBCode
import LSys.WTKHPreservation

namespace LSys

set_option linter.unusedVariables false

/-! ## 1. Depth accounting -/

/-- Stack accounting attached to a core configuration.

    * `depth`  — number of live frames (the entry frame of `main` counts as 1);
    * `budget` — maximum allowed depth (`agent` depth budget, or the `kernel`
      static bound from `#[stack]`/`#[recursion(bound)]`). -/
structure StackConf where
  depth : Nat
  budget : Nat

/-- The depth budget is respected. -/
abbrev Fits (s : StackConf) : Prop := s.depth ≤ s.budget

/-- Entering a frame (`callV`). -/
def push (s : StackConf) : StackConf := { s with depth := s.depth + 1 }

/-- Leaving a frame (`retV`). -/
def pop (s : StackConf) : StackConf := { s with depth := s.depth - 1 }

/-- Budget selection by profile: `kernel` uses the static stack bound
    (`H-LS-29`), `agent` uses its runtime depth budget (`W-LS-STACK`). -/
def profileBudget : Bool → Nat → Nat → Nat
  | true, static, _ => static      -- true = kernel
  | false, _, depth => depth       -- false = agent

theorem kernel_budget_is_static (static depth : Nat) :
    profileBudget true static depth = static := rfl

theorem agent_budget_is_depth (static depth : Nat) :
    profileBudget false static depth = depth := rfl

/-! ### The UB-13 event -/

/-- Runtime events for the stack: exceeding the budget is UB-13. -/
inductive StackEvent (s : StackConf) : UBCode → Prop where
  | overflow (h : s.budget < s.depth) : StackEvent s UBCode.stack

theorem stackEvent_outside {s : StackConf} {k : UBCode} (h : StackEvent s k) :
    OutsideF0 k := by
  cases h
  simp [OutsideF0]

/-! ### Budget-preserving operations -/

theorem fits_push {s : StackConf} (h : s.depth < s.budget) : Fits (push s) :=
  Nat.succ_le_of_lt h

theorem fits_pop {s : StackConf} (h : Fits s) : Fits (pop s) :=
  Nat.le_trans (Nat.sub_le s.depth 1) h

theorem push_depth (s : StackConf) : (push s).depth = s.depth + 1 := rfl

theorem pop_depth (s : StackConf) : (pop s).depth = s.depth - 1 := rfl

/-! ### Oracles: the budget check is total -/

/-- Either the depth fits the budget, or stepping one frame deeper is UB-13. -/
theorem fits_or_overflow (s : StackConf) : Fits s ∨ StackEvent s UBCode.stack := by
  cases Nat.lt_or_ge s.depth (s.budget + 1) with
  | inl h => exact Or.inl (Nat.le_of_lt_succ h)
  | inr h => exact Or.inr (StackEvent.overflow (Nat.lt_of_succ_le h))

/-- Consequently a fitting configuration cannot raise UB-13. -/
theorem no_overflow_within {s : StackConf} (h : Fits s) :
    ¬ StackEvent s UBCode.stack := by
  intro he
  cases he with
  | overflow hb => exact Nat.not_le_of_gt hb h

theorem fits_of_not_overflow {s : StackConf} (h : ¬ StackEvent s UBCode.stack) :
    Fits s := by
  cases fits_or_overflow s with
  | inl hf => exact hf
  | inr he => exact absurd he h

/-! ## 2. Guarded runs -/

/-- Runs whose entries/exits all passed the budget check. -/
inductive StackStar : StackConf → StackConf → Prop where
  | refl (s : StackConf) : StackStar s s
  | enter {s s' : StackConf} (h : s.depth < s.budget) (rest : StackStar (push s) s') :
      StackStar s s'
  | exit {s s' : StackConf} (h : 0 < s.depth) (rest : StackStar (pop s) s') :
      StackStar s s'

theorem StackStar.fits {s s' : StackConf} (h : StackStar s s') :
    Fits s → Fits s' := by
  induction h with
  | refl => exact fun h0 => h0
  | enter hroom rest ih => exact fun h0 => ih (fits_push hroom)
  | exit hpos rest ih => exact fun h0 => ih (fits_pop h0)

/-- **T4d / UB-13 is unreachable**: no configuration reached by a guarded run
    from a fitting start can overflow. -/
theorem no_overflow_reachable {s s' : StackConf} (h : StackStar s s')
    (h0 : Fits s) : ¬ StackEvent s' UBCode.stack :=
  no_overflow_within (StackStar.fits h h0)

/-! ### Concrete recursion bounds (dossier B) -/

/-- `n` live frames under a budget of `b` frames. -/
abbrev nest (n b : Nat) : StackConf := { depth := n, budget := b }

theorem bounded_recursion_fits {n b : Nat} (h : n ≤ b) : Fits (nest n b) := h

theorem recursion_overflow {n b : Nat} (h : b < n) :
    StackEvent (nest n b) UBCode.stack :=
  StackEvent.overflow h

/-- The first depth that overflows a budget of `b` frames. -/
theorem overflow_at_succ (b : Nat) : StackEvent (nest (b + 1) b) UBCode.stack :=
  StackEvent.overflow (Nat.lt_succ_self b)

/-! ### Static `#[recursion(bound)]` check vs. the runtime budget -/

/-- Frames that fit in `stackBytes` at `frameBytes` per frame. -/
abbrev frameBudget (stackBytes frameBytes : Nat) : Nat := stackBytes / frameBytes

/-- The static check of `tools/checker-spike` (`E-LS-STACK`): a recursion bound
    is accepted only when it stays strictly inside the static stack budget. -/
abbrev staticBoundOk (bound stackBytes frameBytes : Nat) : Prop :=
  bound * frameBytes < stackBytes

theorem bound8_ok : staticBoundOk 8 8192 128 := by decide

theorem bound64_rejected : ¬ staticBoundOk 64 8192 128 := by decide

/-- `bound * f < stack` implies `bound ≤ stack / f`: if `stack / f + 1 ≤ bound`,
    then `(stack / f + 1) * f ≤ bound * f < stack`, while the division
    algorithm gives `(stack / f) * f + stack % f = stack` and
    `stack % f < f` — a contradiction. -/
theorem le_div_of_mul_lt {bound stackBytes frameBytes : Nat}
    (hframe : 0 < frameBytes) (h : bound * frameBytes < stackBytes) :
    bound ≤ stackBytes / frameBytes := by
  cases Nat.lt_or_ge bound (stackBytes / frameBytes + 1) with
  | inl hlt => exact Nat.le_of_lt_succ hlt
  | inr hge =>
      have hmul : (stackBytes / frameBytes + 1) * frameBytes ≤ bound * frameBytes :=
        Nat.mul_le_mul_right frameBytes hge
      have hlt : (stackBytes / frameBytes + 1) * frameBytes < stackBytes :=
        Nat.lt_of_le_of_lt hmul h
      rw [Nat.succ_mul] at hlt
      have hdiv : frameBytes * (stackBytes / frameBytes) + stackBytes % frameBytes = stackBytes :=
        Nat.div_add_mod stackBytes frameBytes
      have hdiv' : stackBytes / frameBytes * frameBytes + stackBytes % frameBytes = stackBytes := by
        rw [Nat.mul_comm frameBytes (stackBytes / frameBytes)] at hdiv
        exact hdiv
      have hlt2 : stackBytes / frameBytes * frameBytes + frameBytes <
          stackBytes / frameBytes * frameBytes + stackBytes % frameBytes := by
        rw [hdiv']
        exact hlt
      have hfr : frameBytes ≤ stackBytes % frameBytes :=
        Nat.le_of_add_le_add_left (Nat.le_of_lt hlt2)
      exact absurd hfr (Nat.not_le_of_gt (Nat.mod_lt stackBytes hframe))

theorem static_bound_fits {bound stackBytes frameBytes : Nat}
    (hframe : 0 < frameBytes) (h : staticBoundOk bound stackBytes frameBytes) :
    Fits (nest bound (frameBudget stackBytes frameBytes)) :=
  le_div_of_mul_lt hframe h

/-- Dossier B, `accept_rec.ls`: `bound = 8` at 128 bytes fits an 8 KiB stack. -/
theorem dossier_bound8_fits : Fits (nest 8 (frameBudget 8192 128)) :=
  static_bound_fits (by decide) bound8_ok

/-- Dossier B, `reject.ls`: `bound = 64` is rejected by the static check. -/
theorem dossier_bound64_rejected : ¬ staticBoundOk 64 8192 128 :=
  bound64_rejected

/-! ## 3. The core: stack-annotated `EffHStepEvalCK` steps -/

/-- One core step together with the frame action it performs.

    The annotation is a *relation*: a step may be recorded as `neutral` even
    when it is a `callV`/`retV` redex, which is why the abstraction is sound
    (nothing is forced) and why `fits` holds for every annotation.

    * `push`   — the `callV` redex `call f (val v) body ⇒ body`, guarded by
                 `depth < budget`;
    * `pop`    — the `retV` redex `ret (val v) ⇒ val v`, guarded by
                 `0 < depth` (the entry frame is never left);
    * `neutral` — every other step, including the `callB`/`retB` congruence
                 steps and all 14 `abort*` rules (abort does not unwind). -/
inductive StackStepCK (s : StackConf) (σ : Sigma) (c : EvalConf) (e : Expr)
    (c' : EvalConf) (σ' : Sigma) (A : List Bid) : StackConf → Prop where
  | neutral (h : EffHStepEvalCK σ c e c' σ' A) :
      StackStepCK s σ c e c' σ' A s
  | push {f : Nat} {v : Val} {body : Expr}
      (h : EffHStepEvalCK σ c e c' σ' A)
      (he : e = Expr.call f (Expr.val v) body)
      (hc : c'.expr = body)
      (hroom : s.depth < s.budget) :
      StackStepCK s σ c e c' σ' A (push s)
  | pop {v : Val}
      (h : EffHStepEvalCK σ c e c' σ' A)
      (he : e = Expr.ret (Expr.val v))
      (hc : c'.expr = Expr.val v)
      (hpos : 0 < s.depth) :
      StackStepCK s σ c e c' σ' A (pop s)

/-- Forget the annotation: a stacked step is a core step. -/
theorem StackStepCK.toCK {s s' : StackConf} {σ σ' : Sigma} {c c' : EvalConf}
    {e : Expr} {A : List Bid} (h : StackStepCK s σ c e c' σ' A s') :
    EffHStepEvalCK σ c e c' σ' A := by
  cases h with
  | neutral h => exact h
  | push h _ _ _ => exact h
  | pop h _ _ _ => exact h

/-- Every stacked step keeps the depth inside the budget. -/
theorem StackStepCK.fits {s s' : StackConf} {σ σ' : Sigma} {c c' : EvalConf}
    {e : Expr} {A : List Bid} (h : StackStepCK s σ c e c' σ' A s') (h0 : Fits s) :
    Fits s' := by
  cases h with
  | neutral _ => exact h0
  | push _ _ _ hroom => exact fits_push hroom
  | pop _ _ _ hpos => exact fits_pop h0

/-- The depth of a stacked step is bounded by the depth before it. -/
theorem StackStepCK.depth_le {s s' : StackConf} {σ σ' : Sigma} {c c' : EvalConf}
    {e : Expr} {A : List Bid} (h : StackStepCK s σ c e c' σ' A s') :
    s'.depth ≤ s.depth + 1 := by
  cases h with
  | neutral _ => exact Nat.le_succ s.depth
  | push _ _ _ _ => exact Nat.le_refl (s.depth + 1)
  | pop _ _ _ _ => exact Nat.le_trans (Nat.sub_le s.depth 1) (Nat.le_succ s.depth)

/-- Typing is preserved across a stacked step: the annotation is orthogonal to
    the outcome-typed `WTKH` (the core step is what matters). -/
theorem StackStepCK.wt {s s' : StackConf} {σ σ' : Sigma} {c c' : EvalConf}
    {e : Expr} {A : List Bid} {o : Outcome}
    (hw : WTKH c.env c.heap e σ o)
    (h : StackStepCK s σ c e c' σ' A s') :
    WTKH c'.env c'.heap c'.expr σ' o :=
  WTKH.preserved hw h.toCK rfl rfl

/-! ### Multi-step runs over stacked configurations -/

/-- A stacked configuration: depth accounting + core configuration + the
    runtime state and the live handle set carried by the step relation. -/
structure Stacked where
  stack : StackConf
  conf : EvalConf
  state : Sigma
  handles : List Bid

/-- The entry configuration: one frame (`main`) under a budget. -/
def entry (budget : Nat) (c : EvalConf) (σ : Sigma) : Stacked :=
  { stack := { depth := 1, budget := budget }, conf := c, state := σ, handles := [] }

theorem entry_fits {budget : Nat} {c : EvalConf} {σ : Sigma} (h : 1 ≤ budget) :
    Fits (entry budget c σ).stack := h

/-- One stack-annotated core step of a stacked configuration. -/
inductive StackedStep : Stacked → Expr → Stacked → Prop where
  | step {s s' : StackConf} {σ σ' : Sigma} {c c' : EvalConf} {e : Expr}
      {A : List Bid} (h : StackStepCK s σ c e c' σ' A s') :
      StackedStep ⟨s, c, σ, A⟩ e ⟨s', c', σ', A⟩

theorem StackedStep.fits {st st' : Stacked} {e : Expr} (h : StackedStep st e st')
    (h0 : Fits st.stack) : Fits st'.stack := by
  cases h with
  | step hs => exact StackStepCK.fits hs h0

theorem StackedStep.depth_le {st st' : Stacked} {e : Expr}
    (h : StackedStep st e st') : st'.stack.depth ≤ st.stack.depth + 1 := by
  cases h with
  | step hs => exact StackStepCK.depth_le hs

theorem StackedStep.wt {st st' : Stacked} {e : Expr} {o : Outcome}
    (h : StackedStep st e st')
    (hw : WTKH st.conf.env st.conf.heap e st.state o) :
    WTKH st'.conf.env st'.conf.heap st'.conf.expr st'.state o := by
  cases h with
  | step hs => exact StackStepCK.wt hw hs

/-- Reflexive-transitive closure of stacked steps. -/
inductive StackedStar : Stacked → Stacked → Prop where
  | refl (st : Stacked) : StackedStar st st
  | step {st st' st'' : Stacked} {e : Expr}
      (h : StackedStep st e st') (rest : StackedStar st' st'') : StackedStar st st''

theorem StackedStar.fits {st st' : Stacked} (h : StackedStar st st')
    (h0 : Fits st.stack) : Fits st'.stack := by
  induction h with
  | refl => exact h0
  | step hstep rest ih => exact ih (hstep.fits h0)

/-- Project a stacked run onto the guarded depth run. -/
theorem StackedStar.toStack {st st' : Stacked} (h : StackedStar st st') :
    StackStar st.stack st'.stack := by
  induction h with
  | refl => exact StackStar.refl _
  | step hstep rest ih =>
      cases hstep with
      | step hs =>
          cases hs with
          | neutral _ => exact ih
          | push _ _ _ hroom => exact StackStar.enter hroom ih
          | pop _ _ _ hpos => exact StackStar.exit hpos ih

/-- **UB-13 is unreachable on budget**: from a configuration whose budget
    admits its depth, no reachable stacked configuration can raise the
    stack-overflow event.  This is the `W-LS-STACK` guarantee: the warning says
    the static bound is unknown; the runtime budget turns the overflow into a
    reported event instead of silent memory corruption. -/
theorem no_stack_overflow_reachable {st st' : Stacked} (h : StackedStar st st')
    (h0 : Fits st.stack) : ¬ StackEvent st'.stack UBCode.stack :=
  no_overflow_reachable h.toStack h0

end LSys
