/-
  LSys/TypedStep.lean

  T4a foundation (step 4): a premise-carrying step relation.

  `LSys.Term.Step` is the total F0 redex relation.  `StepP` refines it with
  the static conditions that the corresponding dynamic rule needs, obtained
  from `WT` by `LSys.Adequacy`:

  * `freeze`  : `mode = uniq` and no live aliases;
  * `recover` : the handle targets a place with empty `Aliases*`;
  * `move`    : `mode = uniq`;
  * `write`   : `Writable`;
  * `alloc`   : `CAP_ALLOC_OK`.

  `progressP` therefore uses `WT` (via `redexOK_of_WT`) instead of the stronger
  `progress_any` result.  `StepP` is still a projection of `Step`, so the
  L-Term/L-Block results continue to apply.
-/

import LSys.Block

namespace LSys

def RedexOK (σ : Sigma) : Expr → Prop
  | Expr.freeze p => modeOf σ p = some Mode.uniq ∧ live σ p = []
  | Expr.move p => modeOf σ p = some Mode.uniq
  | Expr.write p _ => Writable σ p
  | Expr.alloc _ _ => CAP_ALLOC_OK σ
  | _ => True

theorem redexOK_of_WT {σ : Sigma} {e : Expr} (h : WT σ e) : RedexOK σ e := by
  cases e with
  | val v => trivial
  | freeze p => exact adequacy_freeze h
  | move p => exact adequacy_move h
  | write p e => exact adequacy_write h
  | alloc a e => exact adequacy_alloc h
  | recover e => trivial
  | var x => trivial
  | op a b => trivial
  | letE x a b => trivial
  | read p => trivial
  | seq a b => trivial
  | region r e => trivial
  | borrow p x e => trivial
  | drop p => trivial
  | call f a b => trivial
  | ret e => trivial
  | spawn f e => trivial
  | atomic p e => trivial
  | unsafeE e => trivial
  | derefRaw e => trivial
  | abort k => trivial

/-- Premise-carrying step: a `Step` whose redex satisfies `RedexOK`. -/
def StepP (σ : Sigma) (e : Expr) (s : State) (e' : Expr) (s' : State) : Prop :=
  Step e s e' s' ∧ RedexOK σ e

theorem stepP_to_step {σ e s e' s'} (h : StepP σ e s e' s') : Step e s e' s' :=
  h.1

/-- **L-Progress with static premises**: `WT` supplies `RedexOK`, and the
    underlying total relation supplies the step. -/
theorem progressP {σ : Sigma} {e : Expr}
    (hwt : WT σ e) (s : State) (h : ¬ FINAL e s) :
    ∃ e' s', StepP σ e s e' s' := by
  cases progress_any e s h with
  | intro e' hstep =>
      cases hstep with
      | intro s' hs =>
          exact ⟨e', s', hs, redexOK_of_WT hwt⟩

/-- Closure of the premise-carrying relation. -/
inductive StepPStar (σ : Sigma) : Expr → State → Expr → State → Prop where
  | refl (e s) : StepPStar σ e s e s
  | step {e s e' s'} (h : StepP σ e s e' s') :
      StepPStar σ e' s' e'' s'' → StepPStar σ e s e'' s''

theorem stepP_decreases {σ e s e' s'} (h : StepP σ e s e' s') :
    Mlt (M e' s') (M e s) :=
  step_decreases h.1

theorem stepPStar_decreases {σ e s e' s'} (h : StepPStar σ e s e' s') :
    M e' s' = M e s ∨ Mlt (M e' s') (M e s) := by
  induction h with
  | refl => exact Or.inl rfl
  | step hs _ ih =>
      cases ih with
      | inl heq => exact Or.inr (heq ▸ stepP_decreases hs)
      | inr hlt => exact Or.inr (Mlt_trans hlt (stepP_decreases hs))

/-- `StepP` preserves `WT`.  This is proved in `LSys/WTPreservation.lean`
    (`wtPreserved`); the hypothesis is kept here so the conditional API and the
    unconditional corollaries can coexist. -/
def WTPreserved (σ : Sigma) : Prop :=
  ∀ {e s e' s'}, WT σ e → StepP σ e s e' s' → WT σ e' 

theorem terminatesP {σ : Sigma} (hpres : WTPreserved σ) :
    ∀ (e : Expr) (s : State), WT σ e →
      ∃ f s', StepPStar σ e s f s' ∧ FINAL f s' := by
  intro e s hwt
  let C : Expr × State → Prop := fun p =>
    ∃ f sf, StepPStar σ p.1 p.2 f sf ∧ FINAL f sf
  have hmain : ∀ p : Expr × State, WT σ p.1 → C p := by
    intro p
    exact mrel_wf.induction
      (C := fun p : Expr × State => WT σ p.1 → C p)
      p (fun p ih => by
      intro hwt
      cases p with
      | mk e s =>
                  cases hfb : finalB e s with
                  | true =>
                      have hf : FINAL e s := (finalB_iff e s).1 hfb
                      exact ⟨e, s, StepPStar.refl e s, hf⟩
                  | false =>
                    have hf : ¬ FINAL e s := by
                      intro hfin
                      have ht : finalB e s = true := (finalB_iff e s).2 hfin
                      rw [hfb] at ht
                      exact Bool.noConfusion ht
                    cases progressP hwt s hf with
                    | intro e' h2 =>
                        cases h2 with
                        | intro s' hstep =>
                            have hlt : Mrel (e', s') (e, s) := stepP_decreases hstep
                            have hwt' : WT σ e' := hpres hwt hstep
                            cases ih (e', s') hlt hwt' with
                                    | intro f h4 =>
                                        cases h4 with
                                        | intro sf h5 =>
                                            cases h5 with
                                            | intro hstar hfin =>
                                                exact ⟨f, sf, StepPStar.step hstep hstar, hfin⟩)
  exact hmain (e, s) hwt

def UBP (σ : Sigma) (e : Expr) (s : State) : Prop :=
  ¬ (∃ e' s', StepP σ e s e' s') ∧ ¬ FINAL e s

/-- **L-NoStuck for the premise-carrying relation**. -/
theorem l_no_stuckP {σ : Sigma} {e : Expr}
    (hwt : WT σ e) (s : State) : ¬ UBP σ e s := by
  intro h
  cases h with
  | intro hstep hfinal => exact hstep (progressP hwt s hfinal)

end LSys
