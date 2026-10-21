/-
  LSys/Block.lean

  L3-4: **L-Block** — every configuration reaches a final configuration.

  The proof combines L-Term (`step_decreases`) with L-Progress
  (`progress_any`) and well-founded induction on `M = (w, r)`.
-/

import LSys.Progress

namespace LSys

theorem mlt_iff_lex {a b : Nat × Nat} : Mlt a b ↔ Prod.Lex Nat.lt Nat.lt a b := by
  match a, b with
  | (a1, a2), (b1, b2) =>
      show (a1 < b1 ∨ (a1 = b1 ∧ a2 < b2)) ↔
        Prod.Lex Nat.lt Nat.lt (a1, a2) (b1, b2)
      constructor
      · intro h
        cases h with
        | inl h1 =>
            exact Prod.Lex.left (a₂ := b1) (b₁ := a2) (b₂ := b2) h1
        | inr h2 =>
            cases h2 with
            | intro heq hlt =>
                cases heq
                exact Prod.Lex.right (a := a1) (b₁ := a2) (b₂ := b2) hlt
      · intro h
        cases h with
        | left _ _ h1 => exact Or.inl h1
        | right _ h2 => exact Or.inr ⟨rfl, h2⟩

theorem mlt_wf : WellFounded Mlt :=
  Subrelation.wf (fun {_ _} h => mlt_iff_lex.1 h)
    (Prod.lex Nat.lt_wfRel Nat.lt_wfRel).wf

/-- The relation on configurations induced by `M = (w, r)`. -/
def Mrel (a b : Expr × State) : Prop := Mlt (M a.1 a.2) (M b.1 b.2)

theorem mrel_wf : WellFounded Mrel :=
  InvImage.wf (fun p : Expr × State => M p.1 p.2) mlt_wf

/-- Computable finality test, used to avoid classical case analysis. -/
def finalB (e : Expr) (s : State) : Bool := isFinal e && (s.borrow == 0)

theorem finalB_iff (e : Expr) (s : State) : finalB e s = true ↔ FINAL e s := by
  unfold finalB FINAL
  simp

/-- **L-Block**: every configuration terminates in a final configuration
    (`val` with no pending borrow frame, or `abort` with no pending frame). -/
theorem terminates : ∀ (e : Expr) (s : State),
    ∃ f s', StepStar e s f s' ∧ FINAL f s' := by
  intro e s
  let C : Expr × State → Prop := fun p =>
    ∃ f s', StepStar p.1 p.2 f s' ∧ FINAL f s'
  have hmain : ∀ p : Expr × State, C p := by
    intro p
    exact mrel_wf.induction p (fun p ih => by
      cases p with
      | mk e s =>
          cases hfb : finalB e s with
          | true =>
              have hf : FINAL e s := (finalB_iff e s).1 hfb
              exact ⟨e, s, StepStar.refl e s, hf⟩
          | false =>
            have hf : ¬ FINAL e s := by
              intro hfin
              have ht : finalB e s = true := (finalB_iff e s).2 hfin
              rw [hfb] at ht
              exact Bool.noConfusion ht
            cases progress_any e s hf with
            | intro e' h1 =>
                cases h1 with
                | intro s' hstep =>
                    have hlt : Mrel (e', s') (e, s) := step_decreases hstep
                    cases ih (e', s') hlt with
                    | intro f h2 =>
                        cases h2 with
                        | intro sf h3 =>
                            cases h3 with
                            | intro hstar hfin =>
                                exact ⟨f, sf, StepStar.step hstep hstar, hfin⟩)
  exact hmain (e, s)

end LSys
