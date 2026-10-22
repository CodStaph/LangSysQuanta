/-
  LSys/T4a.lean

  L3-5: assembly of **T4a** (machine-checked form).

  The L3 core models the F0 fragment.  `t4a` combines

  * L-NoStuck (`l_no_stuck_wt`) — no configuration is undefined-stuck;
  * L-Block (`terminates`) — every run reaches a final configuration;
  * the F0 UB mapping — all F0 events are defined behaviours
    (bounds/overflow/div-zero/eval-order/drop-use).  The remaining ten classes
    (UB-2/3/4/5/8/9/10/11/13/15) are `OutsideF0`; UB-2/3/4 additionally have
    runtime *events* in `Runtime.lean` (`REvent`), the others are the
    responsibility of T4b–T4e (`semantics.md` §T4).  `UBCode.ub_partition`
    proves the 15-code coverage.

  Like the paper statement, `t4a` is relative to the static judgement `WT`
  and the capability preconditions carried by its rules
  (`CAP_ALLOC_OK`, `CAPS_OK`); there is no extra axiom.
-/

import LSys.Block
import LSys.UBCode

namespace LSys

/-- Events observable in the F0 core.  The other ten codes are `OutsideF0`
    (`UBCode.lean`); UB-2/3/4 have runtime events in `Runtime.REvent`. -/
inductive F0Event (e : Expr) (s : State) : UBCode → Prop where
  | bounds {k : Nat} (h : e = Expr.abort k) : F0Event e s UBCode.bounds
  | divZero {k : Nat} (h : e = Expr.abort k) : F0Event e s UBCode.divZero
  | overflow {n : Nat} (h : e = Expr.val (Val.nat n)) : F0Event e s UBCode.overflow
  | evalOrder : F0Event e s UBCode.evalOrder
  | dropUse {k : Nat} (h : e = Expr.abort k) : F0Event e s UBCode.dropUse

theorem f0_event_not_outside {e : Expr} {s : State} {c : UBCode}
    (h : F0Event e s c) : ¬ OutsideF0 c := by
  cases h <;> simp [OutsideF0]

/-- Every F0 event is a defined behaviour. -/
theorem f0_events_defined {e : Expr} {s : State} {c : UBCode}
    (h : F0Event e s c) : DefinedBehavior c = true := by
  cases h <;> rfl

/-- **T4a (machine-checked, F0)**: if `e` is well typed in `Σ`,
    then it is not undefined-stuck, every run terminates in a final
    configuration, and every emitted F0 event is a defined behaviour. -/
theorem t4a {σ : Sigma} {e : Expr}
    (hwt : WT σ e) (s : State) :
    ¬ UB e s ∧
      (∃ f s', StepStar e s f s' ∧ FINAL f s') ∧
      (∀ c, F0Event e s c → DefinedBehavior c = true) := by
  have hnostuck : ¬ UB e s := l_no_stuck_wt hwt s
  have hterm : ∃ f s', StepStar e s f s' ∧ FINAL f s' := terminates e s
  refine ⟨hnostuck, hterm, ?_⟩
  intro c hc
  exact f0_events_defined hc

end LSys
