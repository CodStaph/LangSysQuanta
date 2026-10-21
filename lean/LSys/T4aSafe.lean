/-
  LSys/T4aSafe.lean

  T4a foundation (step 6): the `Safe(P)` package and its assembly theorem.

  `Safe` combines the two global conclusions used by the paper:
  * no configuration is undefined-stuck (`¬ UB`);
  * every run reaches a final configuration (L-Block).

  `RuntimeSafe` packages the runtime T1/T3 conclusions for a well-formed
  heap/borrow configuration.
-/

import LSys.Block
import LSys.TypedStep
import LSys.Runtime
import LSys.Holders
import LSys.Path
import LSys.Unified

namespace LSys

structure Safe (e : Expr) (s : State) : Prop where
  no_ub : ¬ UB e s
  terminates : ∃ f s', StepStar e s f s' ∧ FINAL f s'

/-- **T4a `Safe(P)` assembly** for the F0 core. -/
theorem t4a_safe {σ : Sigma} {e : Expr}
    (hwt : WT σ e) (s : State) : Safe e s := by
  constructor
  · exact l_no_stuck_wt hwt s
  · exact terminates e s

structure SafeP (σ : Sigma) (e : Expr) (s : State) : Prop where
  no_stuck : ¬ UBP σ e s
  terminates : ∃ f s', StepStar e s f s' ∧ FINAL f s'

/-- `Safe` with the premise-carrying relation and `WT`-derived `RedexOK`. -/
theorem t4a_safeP {σ : Sigma} {e : Expr}
    (hwt : WT σ e) (s : State) : SafeP σ e s := by
  constructor
  · exact l_no_stuckP hwt s
  · exact terminates e s

/-- `SafeP` with termination supplied by `terminatesP`, conditional on the
    remaining `WT`-preservation lemma. -/
theorem t4a_safeP_wt {σ : Sigma} (hpres : WTPreserved σ)
    {e : Expr} (hwt : WT σ e) (s : State) :
    (¬ UBP σ e s) ∧ (∃ f sf, StepPStar σ e s f sf ∧ FINAL f sf) := by
  constructor
  · exact l_no_stuckP hwt s
  · exact terminatesP hpres e s hwt

structure RuntimeSafe (c : Conf) : Prop where
  wf : WF c
  no_dangling : ∀ q cell l, c.heap q = some cell → cell.val = RVal.loc l →
    ∃ target, c.heap l = some target ∧ target.live = true

theorem runtime_safe {c : Conf} (hwf : WF c) : RuntimeSafe c := by
  constructor
  · exact hwf
  · intro q cell l hq hval
    exact t1_no_dangling hwf hq hval

structure RecoverSafe (c : Conf) (l : Loc) : Prop where
  cleared : bidsAtTarget l (recoverConf c l).btab = []
  unique_mode : cellMode (recoverConf c l) l = some Mode.uniq

theorem recover_safe {c : Conf} {l : Loc}
    (hm : cellMode c l = some Mode.frozen)
    (hclear : ∀ e, e ∈ c.btab → e.target = l → e.bid ∈ c.flight) :
    RecoverSafe c l := by
  constructor
  · exact (t3_recover_unique hm hclear).1
  · exact (t3_recover_unique hm hclear).2

/-- Unified runtime safety: one configuration, full `H ⇔ B`, dynamic consume. -/
def SafeU (c : ConfE) : Prop :=
  WFU c ∧ (∀ A o, HoldOccurs (ConsumeResultU c A) o ↔ HoldOccurs c o ∧ o.bid ∉ A)

theorem unified_safe {c : ConfE} (hwf : WFU c) : SafeU c := by
  constructor
  · exact hwf
  · intro A o
    exact consumeU_exact A c o

end LSys
