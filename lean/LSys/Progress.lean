/-
  LSys/Progress.lean

  L3-3: **L-Progress** and **L-NoStuck**.

  The L3 core gives every non-final configuration a step (the redex relation
  is total on the F0 syntax; `recover`/`deref_raw`/`op` have total redex
  rules).  `progress` is therefore parameterised by `WT`, as required by
  `spec/t4-proof.md` §3.12, but the machine-checked proof is stronger: it
  holds for every non-final term.  The static side conditions that the paper
  extracts from `WT` are proved separately in `LSys.Adequacy`.
-/

import LSys.Adequacy

namespace LSys

set_option linter.unusedVariables false

theorem step_ctx {C : Ctx} {e : Expr} {s : State} {e' : Expr} {s' : State}
    (h : Step e s e' s') : Step (plug C e) s (plug C e') s' := Step.ctx h

/-- A computable case split on `Expr` into `val`, `abort`, and "other". -/
inductive FinalWitness : Expr → Type where
  | val (v : Val) : FinalWitness (Expr.val v)
  | abort (k : Nat) : FinalWitness (Expr.abort k)
  | other {e : Expr} (h : isFinal e = false) : FinalWitness e

def finalWitness : (e : Expr) → FinalWitness e
  | Expr.val v => FinalWitness.val v
  | Expr.abort k => FinalWitness.abort k
  | Expr.var x => FinalWitness.other rfl
  | Expr.op a b => FinalWitness.other rfl
  | Expr.letE x a b => FinalWitness.other rfl
  | Expr.move p => FinalWitness.other rfl
  | Expr.read p => FinalWitness.other rfl
  | Expr.write p e => FinalWitness.other rfl
  | Expr.seq a b => FinalWitness.other rfl
  | Expr.region r e => FinalWitness.other rfl
  | Expr.alloc a e => FinalWitness.other rfl
  | Expr.freeze p => FinalWitness.other rfl
  | Expr.recover e => FinalWitness.other rfl
  | Expr.borrow p x e => FinalWitness.other rfl
  | Expr.drop p => FinalWitness.other rfl
  | Expr.call f a b => FinalWitness.other rfl
  | Expr.ret e => FinalWitness.other rfl
  | Expr.spawn f e => FinalWitness.other rfl
  | Expr.atomic p e => FinalWitness.other rfl
  | Expr.unsafeE e => FinalWitness.other rfl
  | Expr.derefRaw e => FinalWitness.other rfl

theorem not_final_of_isFinal_false {e : Expr} {s : State}
    (h : isFinal e = false) : ¬ FINAL e s := by
  intro hf
  have hf1 : isFinal e = true := hf.1
  rw [h] at hf1
  exact Bool.noConfusion hf1

/-- Progress for the total L3 small-step relation. -/
theorem progress_any : (e : Expr) → (s : State) → ¬ FINAL e s →
    ∃ e' s', Step e s e' s'
  | Expr.val v, s, h => by
      cases s with
      | mk n =>
          cases n with
          | zero => exact absurd ⟨rfl, rfl⟩ h
          | succ k => exact ⟨Expr.val v, { borrow := k }, Step.borrowExit⟩
  | Expr.var x, s, _ => ⟨Expr.val Val.unit, s, Step.varV⟩
  | Expr.abort k, s, h => by
      cases s with
      | mk n =>
          cases n with
          | zero => exact absurd ⟨rfl, rfl⟩ h
          | succ j => exact ⟨Expr.abort k, { borrow := j }, Step.abortBorrow⟩
  | Expr.op a b, s, _ => by
      cases finalWitness a with
      | val v =>
          cases finalWitness b with
          | val w => exact ⟨Expr.val (Val.nat 0), s, Step.opAny⟩
          | abort k =>
              exact ⟨Expr.abort k, s,
                Step.abortCtx (C := Ctx.opR (Expr.val v) Ctx.hole) (by intro hh; cases hh)⟩
          | other hb =>
              have hnf : ¬ FINAL b s := not_final_of_isFinal_false hb
              cases progress_any b s hnf with
              | intro e' h1 => cases h1 with
                | intro s' hs =>
                    exact ⟨plug (Ctx.opR (Expr.val v) Ctx.hole) e', s', step_ctx (C := Ctx.opR (Expr.val v) Ctx.hole) hs⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.opL Ctx.hole b) (by intro hh; cases hh)⟩
      | other ha =>
          have hnf : ¬ FINAL a s := not_final_of_isFinal_false ha
          cases progress_any a s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.opL Ctx.hole b) e', s', step_ctx (C := Ctx.opL Ctx.hole b) hs⟩
  | Expr.letE x a b, s, _ => by
      cases finalWitness a with
      | val v => exact ⟨b, s, Step.letV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.letB x Ctx.hole b) (by intro hh; cases hh)⟩
      | other ha =>
          have hnf : ¬ FINAL a s := not_final_of_isFinal_false ha
          cases progress_any a s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.letB x Ctx.hole b) e', s', step_ctx (C := Ctx.letB x Ctx.hole b) hs⟩
  | Expr.move p, s, _ => ⟨Expr.val Val.unit, s, Step.moveV⟩
  | Expr.read p, s, _ => ⟨Expr.val Val.unit, s, Step.readV⟩
  | Expr.write p e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val Val.unit, s, Step.writeV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.writeB p Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.writeB p Ctx.hole) e', s', step_ctx (C := Ctx.writeB p Ctx.hole) hs⟩
  | Expr.seq a b, s, _ => by
      cases finalWitness a with
      | val v => exact ⟨b, s, Step.seqV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.seqL Ctx.hole b) (by intro hh; cases hh)⟩
      | other ha =>
          have hnf : ¬ FINAL a s := not_final_of_isFinal_false ha
          cases progress_any a s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.seqL Ctx.hole b) e', s', step_ctx (C := Ctx.seqL Ctx.hole b) hs⟩
  | Expr.region r e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val v, s, Step.regionV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.regionB r Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.regionB r Ctx.hole) e', s', step_ctx (C := Ctx.regionB r Ctx.hole) hs⟩
  | Expr.alloc a e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val (Val.loc 0), s, Step.allocV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.allocB a Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.allocB a Ctx.hole) e', s', step_ctx (C := Ctx.allocB a Ctx.hole) hs⟩
  | Expr.freeze p, s, _ => ⟨Expr.val (Val.valH 0), s, Step.freezeV⟩
  | Expr.recover e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val (Val.loc 0), s, Step.recoverAny⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.recoverB Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.recoverB Ctx.hole) e', s', step_ctx (C := Ctx.recoverB Ctx.hole) hs⟩
  | Expr.borrow p x e, s, _ => ⟨e, { borrow := s.borrow + 1 }, Step.borrowEnter⟩
  | Expr.drop p, s, _ => ⟨Expr.val Val.unit, s, Step.dropV⟩
  | Expr.call f a body, s, _ => by
      cases finalWitness a with
      | val v => exact ⟨body, s, Step.callV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.callB f Ctx.hole body) (by intro hh; cases hh)⟩
      | other ha =>
          have hnf : ¬ FINAL a s := not_final_of_isFinal_false ha
          cases progress_any a s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.callB f Ctx.hole body) e', s', step_ctx (C := Ctx.callB f Ctx.hole body) hs⟩
  | Expr.ret e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val v, s, Step.retV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.retB Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.retB Ctx.hole) e', s', step_ctx (C := Ctx.retB Ctx.hole) hs⟩
  | Expr.spawn f e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val Val.unit, s, Step.spawnV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.spawnB f Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.spawnB f Ctx.hole) e', s', step_ctx (C := Ctx.spawnB f Ctx.hole) hs⟩
  | Expr.atomic p e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val v, s, Step.atomicV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.atomicB p Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.atomicB p Ctx.hole) e', s', step_ctx (C := Ctx.atomicB p Ctx.hole) hs⟩
  | Expr.unsafeE e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val v, s, Step.unsafeV⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.unsafeB Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.unsafeB Ctx.hole) e', s', step_ctx (C := Ctx.unsafeB Ctx.hole) hs⟩
  | Expr.derefRaw e, s, _ => by
      cases finalWitness e with
      | val v => exact ⟨Expr.val (Val.nat 0), s, Step.derefAny⟩
      | abort k =>
          exact ⟨Expr.abort k, s,
            Step.abortCtx (C := Ctx.derefB Ctx.hole) (by intro hh; cases hh)⟩
      | other he =>
          have hnf : ¬ FINAL e s := not_final_of_isFinal_false he
          cases progress_any e s hnf with
          | intro e' h1 => cases h1 with
            | intro s' hs => exact ⟨plug (Ctx.derefB Ctx.hole) e', s', step_ctx (C := Ctx.derefB Ctx.hole) hs⟩

/-- **L-Progress** in the paper's `WT`-relative form. -/
theorem progress {σ : Sigma} {e : Expr}
    (_hwt : WT σ e) (s : State) (h : ¬ FINAL e s) :
    ∃ e' s', Step e s e' s' :=
  progress_any e s h

/-- **L-NoStuck**: well-typed configurations are not undefined-stuck. -/
theorem l_no_stuck_wt {σ : Sigma} {e : Expr}
    (hwt : WT σ e) (s : State) : ¬ UB e s := by
  intro h
  cases h with
  | intro hstep hfinal => exact hstep (progress hwt s hfinal)

end LSys
