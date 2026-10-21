/-
  LSys/LamEff.lean

  A **Λ-only** over-approximation of effects, used for region safety.

  `NoEscape` depends only on `Σ.lam`, and in fact only on the *region* of each
  borrow.  `LamEff` therefore tracks borrows up to their
  `(place, mode, region)` triple (`LamTriple`): bids are runtime identities and
  are erased by `LamSub`.

  Erasing bids is essential for the composition lemma
  (`LamEff.step_compose`): re-deriving a residual effect from a state with a
  larger `Λ` changes `freshBid`, so an exact bid-level inclusion is *false*,
  while the triple-level one is stable (`LamEff.mono`).

  * `let` is the sequential composition of its parts (the binding does not
    change `Λ`);
  * `recover` **never prunes**: pruning only *removes* entries from `Λ`
    (`lamSub_consumeResult`), so the unpruned rule is already the
    over-approximation.  (A separate `recoverConsume` constructor would make
    `LamEff` sensitive to holders/bids and would block `LamEff.mono`.)
  * `move`/`drop`/`write` do not change `Λ`.
-/

import LSys.Effect

namespace LSys

set_option linter.unusedVariables false

/-- A borrow triple: `(place, mode, region)`.  Bids are runtime identities and
    are deliberately erased; `NoEscape` only inspects the region. -/
abbrev LamTriple := Place × (Mode × Rgn)

def lamTriples (σ : Sigma) : List LamTriple :=
  σ.lam.map (fun br => (br.place, br.mode, br.rgn))

theorem mem_map_of {α β : Type} {f : α → β} {l : List α} {a : α} (h : a ∈ l) :
    f a ∈ l.map f := by
  induction l with
  | nil => cases h
  | cons x xs ih =>
      cases h with
      | head => exact List.Mem.head _
      | tail _ ht => exact List.Mem.tail _ (ih ht)

theorem mem_of_mem_map {α β : Type} {f : α → β} {l : List α} {b : β}
    (h : b ∈ l.map f) : ∃ a, a ∈ l ∧ f a = b := by
  induction l with
  | nil => cases h
  | cons x xs ih =>
      cases h with
      | head => exact ⟨x, List.Mem.head _, rfl⟩
      | tail _ ht =>
          cases ih ht with
          | intro a rest =>
              cases rest with
              | intro ha hf => exact ⟨a, List.Mem.tail _ ha, hf⟩

/-- `Λ` of `a` is contained in `Λ` of `b`, at triple granularity. -/
def LamSub (a b : Sigma) : Prop := ∀ t, t ∈ lamTriples a → t ∈ lamTriples b

theorem lamTriples_addBorrow (σ : Sigma) (b : Bid) (p : Place) (m : Mode) :
    lamTriples (addBorrow σ b p m) = (p, m, rgnOf σ p) :: lamTriples σ := rfl

theorem mem_lamTriples {σ : Sigma} {br : Borrow} (h : br ∈ σ.lam) :
    (br.place, br.mode, br.rgn) ∈ lamTriples σ := by
  unfold lamTriples
  exact mem_map_of (f := fun br => (br.place, br.mode, br.rgn)) h

theorem mem_of_mem_lamTriples {σ : Sigma} {t : LamTriple}
    (h : t ∈ lamTriples σ) : ∃ br, br ∈ σ.lam ∧ (br.place, br.mode, br.rgn) = t := by
  unfold lamTriples at h
  exact mem_of_mem_map h

theorem rgnOf_congr {a b : Sigma} (h : a.gamma = b.gamma) (p : Place) :
    rgnOf a p = rgnOf b p := by
  unfold rgnOf
  rw [h]

theorem LamSub.refl (a : Sigma) : LamSub a a := fun _ h => h

theorem LamSub.trans {a b c : Sigma} (h1 : LamSub a b) (h2 : LamSub b c) :
    LamSub a c := fun t h => h2 t (h1 t h)

/-- States that agree on `Λ` are `LamSub`-equivalent (e.g. `clearPlace`/
    `setHolders`, which only touch `holders`). -/
theorem LamSub.of_lam_eq {a b : Sigma} (h : a.lam = b.lam) : LamSub a b := by
  intro t ht
  unfold lamTriples at ht ⊢
  rw [h] at ht
  exact ht

/-- `σ` is contained in the state that only *adds* one borrow on top. -/
theorem LamSub.addBorrow_right (σ : Sigma) (b : Bid) (p : Place) (m : Mode) :
    LamSub σ (addBorrow σ b p m) := by
  intro t ht
  rw [lamTriples_addBorrow]
  exact List.Mem.tail _ ht

theorem LamSub.addBorrow {a b : Sigma} {p : Place} {m : Mode} {x y : Bid}
    (hγ : a.gamma = b.gamma) (hsub : LamSub a b) :
    LamSub (addBorrow a x p m) (addBorrow b y p m) := by
  intro t ht
  rw [lamTriples_addBorrow] at ht ⊢
  cases ht with
  | head =>
      rw [rgnOf_congr hγ p]
      exact List.Mem.head _
  | tail _ ht => exact List.Mem.tail _ (hsub t ht)

theorem noEscape_of_lamSub {a b : Sigma} {R : Rgn} (hsub : LamSub a b)
    (hno : NoEscape b R) : NoEscape a R := by
  intro br hmem hrg
  have ht : (br.place, br.mode, br.rgn) ∈ lamTriples a := mem_lamTriples hmem
  cases mem_of_mem_lamTriples (hsub _ ht) with
  | intro br' rest =>
      cases rest with
      | intro hmem' heq =>
          have hrg' : br'.rgn = R := by
            injection heq with _ h2
            injection h2 with _ h4
            exact h4.trans hrg
          exact hno br' hmem' hrg'

/-- Λ-only effect relation. -/
inductive LamEff : Expr → Sigma → Sigma → Prop where
  | val {σ : Sigma} {v : Val} : LamEff (Expr.val v) σ σ
  | var {σ : Sigma} {x : Var} : LamEff (Expr.var x) σ σ
  | abort {σ : Sigma} {k : Nat} : LamEff (Expr.abort k) σ σ
  | op {σ : Sigma} {a : Expr} {σ₁ : Sigma} {b : Expr} {σ₂ : Sigma}
      (ha : LamEff a σ σ₁) (hb : LamEff b σ₁ σ₂) :
      LamEff (Expr.op a b) σ σ₂
  | letE {σ : Sigma} {x : Var} {a : Expr} {σ₁ : Sigma} {b : Expr}
      {σ₂ : Sigma} (ha : LamEff a σ σ₁) (hb : LamEff b σ₁ σ₂) :
      LamEff (Expr.letE x a b) σ σ₂
  | move {σ : Sigma} {p : Place} : LamEff (Expr.move p) σ σ
  | read {σ : Sigma} {p : Place} :
      LamEff (Expr.read p) σ (addBorrow σ (freshBid σ) p Mode.frozen)
  | write {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.write p e) σ σ'
  | seq {σ : Sigma} {a : Expr} {σ₁ : Sigma} {b : Expr} {σ₂ : Sigma}
      (ha : LamEff a σ σ₁) (hb : LamEff b σ₁ σ₂) :
      LamEff (Expr.seq a b) σ σ₂
  | region {σ : Sigma} {R : Rgn} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.region R e) σ σ'
  | alloc {σ : Sigma} {a : Nat} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.alloc a e) σ σ'
  | freeze {σ : Sigma} {p : Place} :
      LamEff (Expr.freeze p) σ (addBorrow σ (freshBid σ) p Mode.frozen)
  | recoverCtx {σ : Sigma} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.recover e) σ σ'
  | borrow {σ : Sigma} {p : Place} {x : Var} {e : Expr} {σ' : Sigma}
      (h : LamEff e (addBorrow σ 0 p Mode.mut) σ') :
      LamEff (Expr.borrow p x e) σ σ'
  | drop {σ : Sigma} {p : Place} : LamEff (Expr.drop p) σ σ
  | call {σ : Sigma} {f : Nat} {a : Expr} {σ₁ : Sigma} {body : Expr}
      {σ₂ : Sigma} (ha : LamEff a σ σ₁) (hb : LamEff body σ₁ σ₂) :
      LamEff (Expr.call f a body) σ σ₂
  | ret {σ : Sigma} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.ret e) σ σ'
  | spawn {σ : Sigma} {f : Nat} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.spawn f e) σ σ'
  | atomic {σ : Sigma} {p : Place} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.atomic p e) σ σ'
  | unsafeE {σ : Sigma} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.unsafeE e) σ σ'
  | deref {σ : Sigma} {e : Expr} {σ' : Sigma}
      (h : LamEff e σ σ') : LamEff (Expr.derefRaw e) σ σ'

/-- Region safety over the Λ-only over-approximation. -/
def RegionSafeLam (σ : Sigma) (R : Rgn) (e : Expr) : Prop :=
  ∀ σ', LamEff e σ σ' → NoEscape σ' R

/-- `ConsumeResult` only *removes* borrows from `Λ`, so its `Λ` is contained in
    the unconsumed state's `Λ`. -/
theorem lamSub_consumeResult (σ : Sigma) (A : List Bid) :
    LamSub (ConsumeResult σ A) σ := by
  intro t ht
  cases mem_of_mem_lamTriples ht with
  | intro br rest =>
      cases rest with
      | intro hmem heq =>
          rw [← heq]
          exact mem_lamTriples (mem_consumeLam hmem)

/-- **Coarsening** (compatibility statement): `LamEff` already *is* the
    unpruned over-approximation, so every derivation is its own coarsening.
    Kept because §8.3/step 2 referred to it; pruning only removes entries
    (`lamSub_consumeResult`), so the `recover` rule can stay unpruned. -/
theorem LamEff.coarsen {e : Expr} {σ σ₁ : Sigma} (h : LamEff e σ σ₁) :
    ∃ σ₂, LamEff e σ σ₂ ∧ LamSub σ₁ σ₂ :=
  ⟨σ₁, h, LamSub.refl σ₁⟩

/-- `LamEff` never changes `Γ`. -/
theorem LamEff.gamma_eq {e : Expr} {σ σ' : Sigma} (h : LamEff e σ σ') :
    σ'.gamma = σ.gamma := by
  induction h with
  | val => rfl
  | var => rfl
  | abort => rfl
  | op _ _ ih_a ih_b => exact ih_b.trans ih_a
  | letE _ _ ih_a ih_b => exact ih_b.trans ih_a
  | move => rfl
  | read => rfl
  | write _ ih => exact ih
  | seq _ _ ih_a ih_b => exact ih_b.trans ih_a
  | region _ ih => exact ih
  | alloc _ ih => exact ih
  | freeze => rfl
  | recoverCtx _ ih => exact ih
  | borrow _ ih => exact ih
  | drop => rfl
  | call _ _ ih_a ih_b => exact ih_b.trans ih_a
  | ret _ ih => exact ih
  | spawn _ ih => exact ih
  | atomic _ ih => exact ih
  | unsafeE _ ih => exact ih
  | deref _ ih => exact ih

/-- `borrow` case of `LamEff.mono`, isolated so that the (implicit) place and
    variable of the `borrow` constructor can be named. -/
theorem LamEff.borrow_mono {e : Expr} {σ σ' τ : Sigma} {p : Place} {x : Var}
    (ih : ∀ {τ' : Sigma}, (addBorrow σ 0 p Mode.mut).gamma = τ'.gamma →
      LamSub (addBorrow σ 0 p Mode.mut) τ' →
        ∃ σ₂, LamEff e τ' σ₂ ∧ LamSub σ' σ₂)
    (hγ : σ.gamma = τ.gamma) (hsub : LamSub σ τ) :
    ∃ σ₂, LamEff (Expr.borrow p x e) τ σ₂ ∧ LamSub σ' σ₂ := by
  cases ih (τ' := addBorrow τ 0 p Mode.mut) hγ
    (LamSub.addBorrow hγ hsub) with
  | intro σ₂ rest =>
      cases rest with
      | intro he' hsub' =>
          exact ⟨σ₂, LamEff.borrow he', hsub'⟩

/-- The `borrow` case of `LamEff.le`: the borrow frame's own borrow is added on
    top of `σ`, so containment composes through it.  Isolated because the place
    is implicit in the `LamEff.borrow` constructor. -/
theorem lamSub_of_borrow_body {σ σ' : Sigma} {p : Place}
    (ih : LamSub (addBorrow σ 0 p Mode.mut) σ') : LamSub σ σ' :=
  LamSub.trans (LamSub.addBorrow_right σ 0 p Mode.mut) ih

/-- Every `LamEff` derivation only *adds* borrows to `Λ` (there is no pruning
    rule any more), so the output contains the input. -/
theorem LamEff.le {e : Expr} {σ σ' : Sigma} (h : LamEff e σ σ') : LamSub σ σ' := by
  induction h with
  | val => exact LamSub.refl _
  | var => exact LamSub.refl _
  | abort => exact LamSub.refl _
  | op _ _ ih_a ih_b => exact ih_a.trans ih_b
  | letE _ _ ih_a ih_b => exact ih_a.trans ih_b
  | move => exact LamSub.refl _
  | read => exact LamSub.addBorrow_right _ _ _ _
  | write _ ih => exact ih
  | seq _ _ ih_a ih_b => exact ih_a.trans ih_b
  | region _ ih => exact ih
  | alloc _ ih => exact ih
  | freeze => exact LamSub.addBorrow_right _ _ _ _
  | recoverCtx _ ih => exact ih
  | borrow _ ih => exact lamSub_of_borrow_body ih
  | drop => exact LamSub.refl _
  | call _ _ ih_a ih_b => exact ih_a.trans ih_b
  | ret _ ih => exact ih
  | spawn _ ih => exact ih
  | atomic _ ih => exact ih
  | unsafeE _ ih => exact ih
  | deref _ ih => exact ih

/-- `LamEff` is total: every expression has a `Λ`-effect from every state.
    (Used for abort propagation, where the aborted continuation still has to
    be given *some* effect.) -/
theorem LamEff.total : ∀ (e : Expr) (σ : Sigma), ∃ σ', LamEff e σ σ' := by
  intro e
  induction e with
  | val v => intro σ; exact ⟨σ, LamEff.val⟩
  | var x => intro σ; exact ⟨σ, LamEff.var⟩
  | abort k => intro σ; exact ⟨σ, LamEff.abort⟩
  | op a b iha ihb =>
      intro σ
      cases iha σ with
      | intro σ₁ h₁ =>
          cases ihb σ₁ with
          | intro σ₂ h₂ => exact ⟨σ₂, LamEff.op h₁ h₂⟩
  | letE x a b iha ihb =>
      intro σ
      cases iha σ with
      | intro σ₁ h₁ =>
          cases ihb σ₁ with
          | intro σ₂ h₂ => exact ⟨σ₂, LamEff.letE h₁ h₂⟩
  | move p => intro σ; exact ⟨σ, LamEff.move⟩
  | read p => intro σ; exact ⟨_, LamEff.read⟩
  | write p e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.write h⟩
  | seq a b iha ihb =>
      intro σ
      cases iha σ with
      | intro σ₁ h₁ =>
          cases ihb σ₁ with
          | intro σ₂ h₂ => exact ⟨σ₂, LamEff.seq h₁ h₂⟩
  | region r e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.region h⟩
  | alloc a e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.alloc h⟩
  | freeze p => intro σ; exact ⟨_, LamEff.freeze⟩
  | recover e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.recoverCtx h⟩
  | borrow p x e ih =>
      intro σ
      cases ih (addBorrow σ 0 p Mode.mut) with
      | intro σ' h => exact ⟨σ', LamEff.borrow h⟩
  | drop p => intro σ; exact ⟨σ, LamEff.drop⟩
  | call f a b iha ihb =>
      intro σ
      cases iha σ with
      | intro σ₁ h₁ =>
          cases ihb σ₁ with
          | intro σ₂ h₂ => exact ⟨σ₂, LamEff.call h₁ h₂⟩
  | ret e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.ret h⟩
  | spawn f e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.spawn h⟩
  | atomic p e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.atomic h⟩
  | unsafeE e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.unsafeE h⟩
  | derefRaw e ih =>
      intro σ
      cases ih σ with
      | intro σ' h => exact ⟨σ', LamEff.deref h⟩

/-- **Monotonicity**: a `Λ`-effect can be replayed from any state with a larger
    `Λ` (and the same `Γ`), keeping the output inclusion. -/
theorem LamEff.mono {e : Expr} {σ σ₁ : Sigma} (h : LamEff e σ σ₁) {τ : Sigma}
    (hγ : σ.gamma = τ.gamma) (hsub : LamSub σ τ) :
    ∃ σ₂, LamEff e τ σ₂ ∧ LamSub σ₁ σ₂ := by
  induction h generalizing τ with
  | val => exact ⟨τ, LamEff.val, hsub⟩
  | var => exact ⟨τ, LamEff.var, hsub⟩
  | abort => exact ⟨τ, LamEff.abort, hsub⟩
  | op ha hb ih_a ih_b =>
      cases ih_a hγ hsub with
      | intro σa rest =>
          cases rest with
          | intro ha' hsub_a =>
              have hγ2 :=
                (LamEff.gamma_eq ha).trans (hγ.trans (LamEff.gamma_eq ha').symm)
              cases ih_b hγ2 hsub_a with
              | intro σb rest2 =>
                  cases rest2 with
                  | intro hb' hsub_b =>
                      exact ⟨σb, LamEff.op ha' hb', hsub_b⟩
  | letE ha hb ih_a ih_b =>
      cases ih_a hγ hsub with
      | intro σa rest =>
          cases rest with
          | intro ha' hsub_a =>
              have hγ2 :=
                (LamEff.gamma_eq ha).trans (hγ.trans (LamEff.gamma_eq ha').symm)
              cases ih_b hγ2 hsub_a with
              | intro σb rest2 =>
                  cases rest2 with
                  | intro hb' hsub_b =>
                      exact ⟨σb, LamEff.letE ha' hb', hsub_b⟩
  | move => exact ⟨τ, LamEff.move, hsub⟩
  | read => exact ⟨_, LamEff.read, LamSub.addBorrow hγ hsub⟩
  | write he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.write he', hsub'⟩
  | seq ha hb ih_a ih_b =>
      cases ih_a hγ hsub with
      | intro σa rest =>
          cases rest with
          | intro ha' hsub_a =>
              have hγ2 :=
                (LamEff.gamma_eq ha).trans (hγ.trans (LamEff.gamma_eq ha').symm)
              cases ih_b hγ2 hsub_a with
              | intro σb rest2 =>
                  cases rest2 with
                  | intro hb' hsub_b =>
                      exact ⟨σb, LamEff.seq ha' hb', hsub_b⟩
  | region he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.region he', hsub'⟩
  | alloc he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.alloc he', hsub'⟩
  | freeze => exact ⟨_, LamEff.freeze, LamSub.addBorrow hγ hsub⟩
  | recoverCtx he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.recoverCtx he', hsub'⟩
  | borrow he ih => exact LamEff.borrow_mono ih hγ hsub
  | drop => exact ⟨τ, LamEff.drop, hsub⟩
  | call ha hb ih_a ih_b =>
      cases ih_a hγ hsub with
      | intro σa rest =>
          cases rest with
          | intro ha' hsub_a =>
              have hγ2 :=
                (LamEff.gamma_eq ha).trans (hγ.trans (LamEff.gamma_eq ha').symm)
              cases ih_b hγ2 hsub_a with
              | intro σb rest2 =>
                  cases rest2 with
                  | intro hb' hsub_b =>
                      exact ⟨σb, LamEff.call ha' hb', hsub_b⟩
  | ret he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.ret he', hsub'⟩
  | spawn he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.spawn he', hsub'⟩
  | atomic he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.atomic he', hsub'⟩
  | unsafeE he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.unsafeE he', hsub'⟩
  | deref he ih =>
      cases ih hγ hsub with
      | intro σ₂ rest =>
          cases rest with
          | intro he' hsub' =>
              exact ⟨σ₂, LamEff.deref he', hsub'⟩

/-- A value expression has no `Λ`-effect. -/
theorem LamEff.val_state {v : Val} {σ σ' : Sigma}
    (h : LamEff (Expr.val v) σ σ') : σ' = σ := by
  cases h
  rfl

/-- `IsVal`-expressions have no `Λ`-effect. -/
theorem IsVal.exists_val {e : Expr} (h : IsVal e) : ∃ v, e = Expr.val v := by
  cases e <;> simp [IsVal] at h
  exact ⟨_, rfl⟩

end LSys
