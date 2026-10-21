/-
  LSys/StepBridge.lean

  Aligning the runtime configuration `ConfE` with the configuration-level
  evaluation `EvalConf`.

  `MatchV c env heap` relates the `EvalConf` environment to `c.env` as a
  **sub-environment**: runtime `let`/`borrow` steps may add fresh bindings
  (never remove them without a matching `moveVar`), so the expression-level
  environment may have fewer bindings.  The cell heap is interpreted as a value
  heap (`place = [l]`, value = `cell.val`).

  The runtime `letVar`/`borrowVar` steps require the bound variable to be fresh
  (`c.env x = none`); this is exactly what keeps `MatchV` stable without
  updating the `EvalConf` environment.

  `not_match_step_naive` records the remaining obstruction for the raw
  `Step → EffHStepEvalC` bridge: `Step.varV` may produce an arbitrary value,
  while `EffHStepEvalC.varV` reads the value from `c.env`.
-/

import LSys.EvalConf
import LSys.Preservation

namespace LSys

set_option linter.unusedVariables false

/-- Interpret the cell heap of `ConfE` as an `EvalConf` value heap:
    location `l` is the static place `[l]`. -/
def evalHeapOfConf (c : ConfE) : EvalHeap :=
  fun p =>
    match p with
    | [l] => (c.heap l).map Cell.val
    | _ => none

/-- The `EvalConf` induced by a runtime configuration, an expression and a
    borrow-frame state. -/
def evalConfOf (c : ConfE) (e : Expr) (s : State) : EvalConf :=
  ⟨e, c.env, evalHeapOfConf c, s⟩

/-- `evalHeapOfConf` only depends on the heap, not on `flight`/`btab`. -/
theorem evalHeapOfConf_push (c : ConfE) (b : Bid) :
    evalHeapOfConf { c with flight := b :: c.flight } = evalHeapOfConf c := rfl

/-- Value-level alignment between `ConfE` and `EvalConf`: the expression
    environment is a sub-environment of the runtime environment. -/
structure MatchV (c : ConfE) (env : EvalEnv) (heap : EvalHeap) : Prop where
  env_sub : ∀ x v, env x = some v → c.env x = some v
  heap_eq : heap = evalHeapOfConf c

theorem MatchV.evalConfOf (c : ConfE) (e : Expr) (s : State) :
    MatchV c (evalConfOf c e s).env (evalConfOf c e s).heap :=
  ⟨fun _ _ h => h, rfl⟩

theorem MatchV.letVar {c : ConfE} {env : EvalEnv} {heap : EvalHeap}
    {x : Var} {v : RVal} (hm : MatchV c env heap) (hfresh : c.env x = none) :
    MatchV (letVar c x v) env heap := by
  constructor
  · intro y w hy
    cases Nat.decEq y x with
    | isTrue hxy =>
        cases hxy
        have hc : c.env x = some w := hm.env_sub x w hy
        rw [hfresh] at hc
        cases hc
    | isFalse hxy =>
        have hlf : (LSys.letVar c x v).env = setEnv c.env x v := rfl
        rw [hlf, setEnv_other hxy]
        exact hm.env_sub y w hy
  · exact hm.heap_eq

theorem MatchV.moveVar {c : ConfE} {env : EvalEnv} {heap : EvalHeap}
    {x : Var} {v : RVal} (hm : MatchV c env heap) :
    MatchV (moveVar c x v) (removeEnv env x) heap := by
  constructor
  · intro y w hy
    cases Nat.decEq y x with
    | isTrue hxy =>
        cases hxy
        rw [removeEnv_same] at hy
        cases hy
    | isFalse hxy =>
        have hlf : (LSys.moveVar c x v).env = removeEnv c.env x := rfl
        rw [hlf, removeEnv_other hxy]
        rw [removeEnv_other hxy] at hy
        exact hm.env_sub y w hy
  · exact hm.heap_eq

theorem MatchV.borrowVar {c : ConfE} {env : EvalEnv} {heap : EvalHeap}
    {l : Loc} {x : Var} {b : Bid} (hm : MatchV c env heap)
    (hfresh : c.env x = none) :
    MatchV (borrowVar c l x b) env heap := by
  constructor
  · intro y w hy
    cases Nat.decEq y x with
    | isTrue hxy =>
        cases hxy
        have hc : c.env x = some w := hm.env_sub x w hy
        rw [hfresh] at hc
        cases hc
    | isFalse hxy =>
        have hlf : (LSys.borrowVar c l x b).env = setEnv c.env x (RVal.refH b) := rfl
        rw [hlf, setEnv_other hxy]
        exact hm.env_sub y w hy
  · exact hm.heap_eq

/-- Value alignment is preserved by runtime steps (fresh `let`/`borrow`
    bindings do not change the expression environment; the heap component is
    recomputed from the new heap). -/
theorem MatchV.rstep {c c' : ConfE} {env : EvalEnv} {heap : EvalHeap}
    (hm : MatchV c env heap) (h : RStepE c c') :
    ∃ env' heap', MatchV c' env' heap' := by
  cases h with
  | refl => exact ⟨env, heap, hm⟩
  | letVar hfresh =>
      exact ⟨env, heap, hm.letVar hfresh⟩
  | moveVar =>
      exact ⟨removeEnv env _, heap, hm.moveVar⟩
  | borrowVar hfresh =>
      exact ⟨env, heap, hm.borrowVar hfresh⟩
  | borrowPush =>
      exact ⟨env, heap,
        ⟨hm.env_sub, by rw [evalHeapOfConf_push]; exact hm.heap_eq⟩⟩
  | borrowPop =>
      exact ⟨env, heap,
        ⟨hm.env_sub, by rw [← evalHeapOfConf_push]; exact hm.heap_eq⟩⟩
  | heap hconf =>
      exact ⟨env, evalHeapOfConf (liftConf c _), ⟨hm.env_sub, rfl⟩⟩

/-- Inversion of the only step rule for `var`. -/
theorem EffHStepEvalC.var_inv {σ : Sigma} {c c' : EvalConf} {x : Var}
    {σ' : Sigma} {A : List Bid}
    (h : EffHStepEvalC σ c (Expr.var x) c' σ' A) :
    ∃ v, c.env x = some v ∧ c' = withExpr c (Expr.val (toVal v)) := by
  cases h with
  | varV hv => exact ⟨_, hv, rfl⟩

/-- **Naive `match_step` is false**: the raw `var` step may return a value that
    differs from the environment, while `EffHStepEvalC.varV` reads `c.env`. -/
theorem not_match_step_naive :
    ∃ (c : EvalConf) (w : Val) (σ : Sigma),
      Step (Expr.var 0) (State.mk 0) (Expr.val w) (State.mk 0) ∧
      c.env 0 = some (RVal.nat 5) ∧
      ¬ ∃ (c' : EvalConf) (σ' : Sigma) (A' : List Bid),
          EffHStepEvalC σ c (Expr.var 0) c' σ' A' ∧
          c'.expr = Expr.val w := by
  let env0 : EvalEnv := fun x => if x = 0 then some (RVal.nat 5) else none
  let c0 : EvalConf := ⟨Expr.var 0, env0, fun _ => none, State.mk 0⟩
  refine ⟨c0, Val.nat 6, ⟨[], [], [], [], Caps.mk true []⟩, ?_, ?_, ?_⟩
  · exact Step.varV
  · dsimp only [c0, env0]
    exact if_pos rfl
  · intro h
    cases h with
    | intro c' h =>
        cases h with
        | intro σ' h =>
            cases h with
            | intro A' h =>
                cases h with
                | intro hstep hexpr =>
                    cases EffHStepEvalC.var_inv hstep with
                    | intro v hrest =>
                        cases hrest with
                        | intro hv hc' =>
                            have henv : c0.env 0 = some (RVal.nat 5) := by
                              dsimp only [c0, env0]
                              exact if_pos rfl
                            rw [henv] at hv
                            cases hv
                            cases hc'
                            cases hexpr

end LSys
