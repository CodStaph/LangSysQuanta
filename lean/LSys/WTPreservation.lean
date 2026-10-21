/-
  LSys/WTPreservation.lean

  Proof of `WTPreserved` for the state-independent `WT`.

  The static judgement is input-only (`WT σ e`), so preservation is stated as
  `WT σ e → Step e s e' s' → WT σ e'`.  The key context lemmas are
  `wt_of_plug` (extract the hole) and `wt_plug_of` (rebuild the context after
  replacing the hole with a well-typed expression).
-/

import LSys.TypedStep
import LSys.Preservation

namespace LSys

set_option linter.unusedVariables false

/-! ## Context lemmas -/

theorem wt_of_plug {σ : Sigma} {C : Ctx} {e : Expr}
    (h : WT σ (plug C e)) : WT σ e := by
  induction C generalizing e with
  | hole => exact h
  | opL c b ih =>
      cases h with
      | op h1 h2 => exact ih h1
  | opR a c ih =>
      cases h with
      | op h1 h2 => exact ih h2
  | letB x c b ih =>
      cases h with
      | letE h1 h2 => exact ih h1
  | writeB p c ih =>
      cases h with
      | write hm h1 => exact ih h1
  | seqL c b ih =>
      cases h with
      | seq h1 h2 => exact ih h1
  | allocB a c ih =>
      cases h with
      | alloc hcap h1 => exact ih h1
  | regionB r c ih =>
      cases h with
      | region h1 hno => exact ih h1
  | recoverB c ih =>
      cases h with
      | recover h1 => exact ih h1
  | borrowB p x c ih =>
      cases h with
      | borrow hm h1 => exact ih h1
  | callB f c body ih =>
      cases h with
      | call hf h1 h2 => exact ih h1
  | retB c ih =>
      cases h with
      | ret h1 => exact ih h1
  | spawnB f c ih =>
      cases h with
      | spawn hf h1 => exact ih h1
  | atomicB p c ih =>
      cases h with
      | atomic hm h1 => exact ih h1
  | unsafeB c ih =>
      cases h with
      | unsafeE h1 => exact ih h1
  | derefB c ih =>
      cases h with
      | deref h1 => exact ih h1

theorem wt_plug_of {σ : Sigma} {C : Ctx} {e e' : Expr}
    (h : WT σ (plug C e)) (he : WT σ e') : WT σ (plug C e') := by
  induction C generalizing e e' with
  | hole => exact he
  | opL c b ih =>
      cases h with
      | op h1 h2 => exact WT.op (ih h1 he) h2
  | opR a c ih =>
      cases h with
      | op h1 h2 => exact WT.op h1 (ih h2 he)
  | letB x c b ih =>
      cases h with
      | letE h1 h2 => exact WT.letE (ih h1 he) h2
  | writeB p c ih =>
      cases h with
      | write hm h1 => exact WT.write hm (ih h1 he)
  | seqL c b ih =>
      cases h with
      | seq h1 h2 => exact WT.seq (ih h1 he) h2
  | allocB a c ih =>
      cases h with
      | alloc hcap h1 => exact WT.alloc hcap (ih h1 he)
  | regionB r c ih =>
      cases h with
      | region h1 hno => exact WT.region (ih h1 he) hno
  | recoverB c ih =>
      cases h with
      | recover h1 => exact WT.recover (ih h1 he)
  | borrowB p x c ih =>
      cases h with
      | borrow hm h1 => exact WT.borrow hm (ih h1 he)
  | callB f c body ih =>
      cases h with
      | call hf h1 h2 => exact WT.call hf (ih h1 he) h2
  | retB c ih =>
      cases h with
      | ret h1 => exact WT.ret (ih h1 he)
  | spawnB f c ih =>
      cases h with
      | spawn hf h1 => exact WT.spawn hf (ih h1 he)
  | atomicB p c ih =>
      cases h with
      | atomic hm h1 => exact WT.atomic hm (ih h1 he)
  | unsafeB c ih =>
      cases h with
      | unsafeE h1 => exact WT.unsafeE (ih h1 he)
  | derefB c ih =>
      cases h with
      | deref h1 => exact WT.deref (ih h1 he)

/-! ## Preservation of the raw step -/

theorem wt_preserved_step :
    ∀ {σ : Sigma} {e : Expr} {s : State} {e' : Expr} {s' : State},
      WT σ e → Step e s e' s' → WT σ e' := by
  intro σ e s e' s' hwt hstep
  induction hstep generalizing σ with
  | ctx h ih =>
      exact wt_plug_of hwt (ih (wt_of_plug hwt))
  | abortCtx h => exact WT.abort _
  | op => exact WT.val _
  | varV => exact WT.val _
  | opAny => exact WT.val _
  | letV =>
      cases hwt with
      | letE h1 h2 => exact h2
  | moveV => exact WT.val _
  | readV => exact WT.val _
  | writeV => exact WT.val _
  | seqV =>
      cases hwt with
      | seq h1 h2 => exact h2
  | regionV => exact WT.val _
  | allocV => exact WT.val _
  | freezeV => exact WT.val _
  | recoverV => exact WT.val _
  | recoverAny => exact WT.val _
  | dropV => exact WT.val _
  | callV =>
      cases hwt with
      | call hf h1 h2 => exact h2
  | retV => exact WT.val _
  | spawnV => exact WT.val _
  | atomicV => exact WT.val _
  | unsafeV => exact WT.val _
  | derefV => exact WT.val _
  | derefAny => exact WT.val _
  | borrowEnter =>
      cases hwt with
      | borrow hm h1 => exact h1
  | borrowExit => exact WT.val _
  | abortBorrow => exact WT.abort _

/-- **`WTPreserved`**: the premise-carrying relation preserves `WT`. -/
theorem wtPreserved (σ : Sigma) : WTPreserved σ := by
  intro e s e' s' hwt hstep
  exact wt_preserved_step hwt hstep.1

/-- Unconditional termination of `StepP` for well-typed terms. -/
theorem terminatesP_uncond {σ : Sigma} {e : Expr} {s : State}
    (hwt : WT σ e) :
    ∃ f sf, StepPStar σ e s f sf ∧ FINAL f sf :=
  terminatesP (wtPreserved σ) e s hwt

theorem t4a_safeP_final {σ : Sigma} {e : Expr} {s : State}
    (hwt : WT σ e) :
    (¬ UBP σ e s) ∧ (∃ f sf, StepPStar σ e s f sf ∧ FINAL f sf) :=
  ⟨l_no_stuckP hwt s, terminatesP_uncond hwt⟩

end LSys
