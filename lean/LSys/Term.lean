/-!
  LSys/Term.lean

  Machine-checked core of `t4-proof.md` §3.12 (L-Term).

  Scope:
  * `Expr` is the F0 core syntax (single-argument calls; places are atoms).
  * `State` tracks pending `Borrow` frames (the `r` component of `M`).
  * `Step` is the small-step relation for the redex rules, the block
    congruence rules, abort propagation, and borrow enter/exit.
  * `w` / `r` / `M = (w, r)`, `L-Term` (one step strictly decreases `M`),
    and `L-Term*` (one or more steps strictly decrease `M`).

  Not in this file: the static semantics, `Match`, `ConsumeResult`, and the
  L-Adequacy bridge (S9/S11/S14).  Those remain the paper obligations; see
  `lean/README.md` for the exact boundary.
-/

namespace LSys

abbrev Path := List Nat

/-! ## Values and expressions -/

inductive Val where
  | unit
  | nat (n : Nat)
  | loc (l : Nat)
  | valH (b : Nat)
  | refH (b : Nat)
  deriving Repr, DecidableEq

inductive Expr where
  | val (v : Val)
  | var (x : Nat)
  | op (a b : Expr)
  | letE (x : Nat) (a b : Expr)
  | move (p : Path)
  | read (p : Path)
  | write (p : Path) (e : Expr)
  | seq (a b : Expr)
  | region (r : Nat) (e : Expr)
  | alloc (a : Nat) (e : Expr)
  | freeze (p : Path)
  | recover (e : Expr)
  | borrow (p : Path) (x : Nat) (e : Expr)
  | drop (p : Path)
  | call (f : Nat) (arg body : Expr)
  | ret (e : Expr)
  | spawn (f : Nat) (e : Expr)
  | atomic (p : Path) (e : Expr)
  | unsafeE (e : Expr)
  | derefRaw (e : Expr)
  | abort (k : Nat)
  deriving Repr, DecidableEq

/-! ## Configuration: pending `Borrow` frames -/

structure State where
  borrow : Nat
  deriving Repr, DecidableEq

/-! ## Evaluation contexts -/

inductive Ctx where
  | hole
  | opL (c : Ctx) (b : Expr)
  | opR (a : Expr) (c : Ctx)
  | letB (x : Nat) (c : Ctx) (b : Expr)
  | writeB (p : Path) (c : Ctx)
  | seqL (c : Ctx) (b : Expr)
  | allocB (a : Nat) (c : Ctx)
  | regionB (r : Nat) (c : Ctx)
  | recoverB (c : Ctx)
  | borrowB (p : Path) (x : Nat) (c : Ctx)
  | callB (f : Nat) (c : Ctx) (body : Expr)
  | retB (c : Ctx)
  | spawnB (f : Nat) (c : Ctx)
  | atomicB (p : Path) (c : Ctx)
  | unsafeB (c : Ctx)
  | derefB (c : Ctx)
  deriving Repr, DecidableEq

def plug : Ctx → Expr → Expr
  | Ctx.hole, e => e
  | Ctx.opL c b, e => Expr.op (plug c e) b
  | Ctx.opR a c, e => Expr.op a (plug c e)
  | Ctx.letB x c b, e => Expr.letE x (plug c e) b
  | Ctx.writeB p c, e => Expr.write p (plug c e)
  | Ctx.seqL c b, e => Expr.seq (plug c e) b
  | Ctx.allocB a c, e => Expr.alloc a (plug c e)
  | Ctx.regionB r c, e => Expr.region r (plug c e)
  | Ctx.recoverB c, e => Expr.recover (plug c e)
  | Ctx.borrowB p x c, e => Expr.borrow p x (plug c e)
  | Ctx.callB f c body, e => Expr.call f (plug c e) body
  | Ctx.retB c, e => Expr.ret (plug c e)
  | Ctx.spawnB f c, e => Expr.spawn f (plug c e)
  | Ctx.atomicB p c, e => Expr.atomic p (plug c e)
  | Ctx.unsafeB c, e => Expr.unsafeE (plug c e)
  | Ctx.derefB c, e => Expr.derefRaw (plug c e)

/-! ## The measure `M = (w, r)` -/

def w : Expr → Nat
  | Expr.val _ => 0
  | Expr.var _ => 1
  | Expr.op a b => 1 + w a + w b
  | Expr.letE _ a b => 1 + w a + w b
  | Expr.move _ => 1
  | Expr.read _ => 1
  | Expr.write _ e => 1 + w e
  | Expr.seq a b => 1 + w a + w b
  | Expr.region _ e => 1 + w e
  | Expr.alloc _ e => 1 + w e
  | Expr.freeze _ => 1
  | Expr.recover e => 1 + w e
  | Expr.borrow _ _ e => 1 + w e
  | Expr.drop _ => 1
  | Expr.call _ a b => 1 + w a + w b
  | Expr.ret e => 1 + w e
  | Expr.spawn _ e => 1 + w e
  | Expr.atomic _ e => 1 + w e
  | Expr.unsafeE e => 1 + w e
  | Expr.derefRaw e => 1 + w e
  | Expr.abort _ => 0

def r (s : State) : Nat := s.borrow

def M (e : Expr) (s : State) : Nat × Nat := (w e, r s)

/-- Lexicographic order on `M`. -/
def Mlt (a b : Nat × Nat) : Prop :=
  a.1 < b.1 ∨ (a.1 = b.1 ∧ a.2 < b.2)

theorem Mlt_trans {a b c : Nat × Nat} (hab : Mlt a b) (hbc : Mlt b c) : Mlt a c := by
  cases hab with
  | inl h1 =>
      cases hbc with
      | inl h3 => exact Or.inl (Nat.lt_trans h1 h3)
      | inr h => exact Or.inl (h.1 ▸ h1)
  | inr h =>
      cases hbc with
      | inl h3 => exact Or.inl (h.1 ▸ h3)
      | inr h' => exact Or.inr ⟨h.1.trans h'.1, Nat.lt_trans h.2 h'.2⟩

/-! ## Arithmetic helpers (Lean core has no `omega`) -/

theorem lt_one_add (a : Nat) : a < 1 + a := by
  rw [Nat.add_comm]
  exact Nat.lt_succ_self a

theorem zero_lt_one_add (a : Nat) : 0 < 1 + a := by
  rw [Nat.add_comm]
  exact Nat.succ_pos a

theorem zero_lt_one_add_add (a b : Nat) : 0 < 1 + a + b :=
  Nat.lt_of_lt_of_le (zero_lt_one_add a) (Nat.le_add_right (1 + a) b)

/-! ## Helper lemmas for contexts -/

theorem w_plug_eq : ∀ (C : Ctx) {e e' : Expr}, w e' = w e → w (plug C e') = w (plug C e)
  | Ctx.hole, _, _, h => h
  | Ctx.opL c b, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.opR a c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.letB x c b, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.writeB p c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.seqL c b, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.allocB a c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.regionB r c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.recoverB c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.borrowB p x c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.callB f c body, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.retB c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.spawnB f c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.atomicB p c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.unsafeB c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]
  | Ctx.derefB c, e, e', h => by
      have ih := w_plug_eq c h
      simp [plug, w, ih]

theorem w_plug_mono : ∀ (C : Ctx) {e e' : Expr}, w e' < w e → w (plug C e') < w (plug C e)
  | Ctx.hole, _, _, h => h
  | Ctx.opL c b, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_right (Nat.add_lt_add_left ih 1) (w b)
  | Ctx.opR a c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih (1 + w a)
  | Ctx.letB x c b, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_right (Nat.add_lt_add_left ih 1) (w b)
  | Ctx.writeB p c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.seqL c b, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_right (Nat.add_lt_add_left ih 1) (w b)
  | Ctx.allocB a c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.regionB r c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.recoverB c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.borrowB p x c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.callB f c body, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_right (Nat.add_lt_add_left ih 1) (w body)
  | Ctx.retB c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.spawnB f c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.atomicB p c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.unsafeB c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1
  | Ctx.derefB c, e, e', h => by
      have ih := w_plug_mono c h
      simp only [plug, w]
      exact Nat.add_lt_add_left ih 1

theorem w_plug_abort_pos : ∀ (C : Ctx) (k : Nat), C ≠ Ctx.hole → 0 < w (plug C (Expr.abort k))
  | Ctx.hole, _, h => by contradiction
  | Ctx.opL c b, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add_add (w (plug c (Expr.abort k))) (w b)
  | Ctx.opR a c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add_add (w a) (w (plug c (Expr.abort k)))
  | Ctx.letB x c b, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add_add (w (plug c (Expr.abort k))) (w b)
  | Ctx.writeB p c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.seqL c b, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add_add (w (plug c (Expr.abort k))) (w b)
  | Ctx.allocB a c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.regionB r c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.recoverB c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.borrowB p x c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.callB f c body, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add_add (w (plug c (Expr.abort k))) (w body)
  | Ctx.retB c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.spawnB f c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.atomicB p c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.unsafeB c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))
  | Ctx.derefB c, k, _ => by
      simp only [plug, w]
      exact zero_lt_one_add (w (plug c (Expr.abort k)))

/-! ## Small-step relation (redex rules + context + borrow frames + abort) -/

inductive Step : Expr → State → Expr → State → Prop where
  | ctx {C e e' s s'} (h : Step e s e' s') : Step (plug C e) s (plug C e') s'
  | abortCtx {C k s} (h : C ≠ Ctx.hole) : Step (plug C (Expr.abort k)) s (Expr.abort k) s
  | op {a b s} : Step (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b))) s
      (Expr.val (Val.nat (a + b))) s
  | varV {x v s} : Step (Expr.var x) s (Expr.val v) s
  | opAny {v w s} : Step (Expr.op (Expr.val v) (Expr.val w)) s
      (Expr.val (Val.nat 0)) s
  | letV {x v e s} : Step (Expr.letE x (Expr.val v) e) s e s
  | moveV {p v s} : Step (Expr.move p) s (Expr.val v) s
  | readV {p v s} : Step (Expr.read p) s (Expr.val v) s
  | writeV {p v s} : Step (Expr.write p (Expr.val v)) s (Expr.val Val.unit) s
  | seqV {v e s} : Step (Expr.seq (Expr.val v) e) s e s
  | regionV {r v s} : Step (Expr.region r (Expr.val v)) s (Expr.val v) s
  | allocV {a v l s} : Step (Expr.alloc a (Expr.val v)) s (Expr.val (Val.loc l)) s
  | freezeV {p b s} : Step (Expr.freeze p) s (Expr.val (Val.valH b)) s
  | recoverV {b l s} : Step (Expr.recover (Expr.val (Val.valH b))) s (Expr.val (Val.loc l)) s
  | dropV {p s} : Step (Expr.drop p) s (Expr.val Val.unit) s
  | callV {f v body s} : Step (Expr.call f (Expr.val v) body) s body s
  | retV {v s} : Step (Expr.ret (Expr.val v)) s (Expr.val v) s
  | spawnV {f v s} : Step (Expr.spawn f (Expr.val v)) s (Expr.val Val.unit) s
  | atomicV {p v s} : Step (Expr.atomic p (Expr.val v)) s (Expr.val v) s
  | unsafeV {v s} : Step (Expr.unsafeE (Expr.val v)) s (Expr.val v) s
  | derefV {l v s} : Step (Expr.derefRaw (Expr.val (Val.loc l))) s (Expr.val v) s
  | derefAny {v s} : Step (Expr.derefRaw (Expr.val v)) s (Expr.val (Val.nat 0)) s
  | recoverAny {v s} : Step (Expr.recover (Expr.val v)) s (Expr.val (Val.loc 0)) s
  | borrowEnter {p x e s} : Step (Expr.borrow p x e) s e { borrow := s.borrow + 1 }
  | borrowExit {v n} : Step (Expr.val v) { borrow := n + 1 } (Expr.val v) { borrow := n }
  | abortBorrow {k n} : Step (Expr.abort k) { borrow := n + 1 } (Expr.abort k) { borrow := n }

/-! ## L-Term: every step strictly decreases `M` -/

theorem step_decreases {e s e' s'} (h : Step e s e' s') : Mlt (M e' s') (M e s) := by
  induction h with
  | ctx h ih =>
      cases ih with
      | inl hw => exact Or.inl (w_plug_mono _ hw)
      | inr h => exact Or.inr ⟨w_plug_eq _ h.1, h.2⟩
  | abortCtx h =>
      exact Or.inl (w_plug_abort_pos _ _ h)
  | op =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | varV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | opAny =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | letV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl (lt_one_add _)
  | moveV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | readV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | writeV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | seqV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl (lt_one_add _)
  | regionV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | allocV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | freezeV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | recoverV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | dropV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | callV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl (lt_one_add _)
  | retV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | spawnV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | atomicV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | unsafeV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | derefV =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | derefAny =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | recoverAny =>
      simp only [M, w, Mlt, Nat.add_zero]
      exact Or.inl Nat.zero_lt_one
  | borrowEnter =>
      simp only [M, w, Mlt]
      exact Or.inl (lt_one_add _)
  | borrowExit =>
      simp only [M, r, w, Mlt]
      exact Or.inr ⟨trivial, Nat.lt_succ_self _⟩
  | abortBorrow =>
      simp only [M, r, w, Mlt]
      exact Or.inr ⟨trivial, Nat.lt_succ_self _⟩

/-! ## Multi-step closure -/

inductive StepStar : Expr → State → Expr → State → Prop where
  | refl (e s) : StepStar e s e s
  | step {e s e' s'} (h : Step e s e' s') : StepStar e' s' e'' s'' → StepStar e s e'' s''

theorem stepStar_le {e s e' s'} (h : StepStar e s e' s') :
    M e' s' = M e s ∨ Mlt (M e' s') (M e s) := by
  induction h with
  | refl => exact Or.inl rfl
  | step hstep _ ih =>
      cases ih with
      | inl heq =>
          exact Or.inr (heq ▸ step_decreases hstep)
      | inr hlt =>
          exact Or.inr (Mlt_trans hlt (step_decreases hstep))

theorem stepStar_decreases {e s e' s'} (h : StepStar e s e' s')
    (hne : M e' s' ≠ M e s) : Mlt (M e' s') (M e s) := by
  cases stepStar_le h with
  | inl heq => exact absurd heq hne
  | inr hlt => exact hlt

/-! ## Final states and stuckness (definitions used by L-NoStuck) -/

def isFinal : Expr → Bool
  | Expr.val _ => true
  | Expr.abort _ => true
  | _ => false

def FINAL (e : Expr) (s : State) : Prop := isFinal e = true ∧ s.borrow = 0

def UB (e : Expr) (s : State) : Prop :=
  ¬ (∃ e' s', Step e s e' s') ∧ ¬ FINAL e s

/-- L-NoStuck, relative to the paper's L-Progress premise. -/
theorem l_no_stuck
    (progress : ∀ e s, ¬ FINAL e s → ∃ e' s', Step e s e' s')
    (e : Expr) (s : State) : ¬ UB e s := by
  intro h
  cases h with
  | intro hstep hfinal => exact hstep (progress e s hfinal)

end LSys
