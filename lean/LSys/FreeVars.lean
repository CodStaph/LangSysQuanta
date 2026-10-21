/-
  LSys/FreeVars.lean

  Free variables of an expression and the invariant that a `WTKH`-typed
  expression only mentions variables bound in its environment
  (`VarsBound`).  This is the basis for transporting effects/region safety
  along environment extensions (layer 2 of route A).
-/

import LSys.WTKH

namespace LSys

set_option linter.unusedVariables false

/-- Free variables (the core has no binding in `WT`/`WTKH`'s environment,
    except for the value-dependent `let`/`borrow` bodies). -/
def fv : Expr → List Var
  | Expr.val _ => []
  | Expr.var x => [x]
  | Expr.op a b => fv a ++ fv b
  | Expr.letE x a b => fv a ++ (fv b).filter (fun y => !(y == x))
  | Expr.move _ => []
  | Expr.read _ => []
  | Expr.write _ e => fv e
  | Expr.seq a b => fv a ++ fv b
  | Expr.region _ e => fv e
  | Expr.alloc _ e => fv e
  | Expr.freeze _ => []
  | Expr.recover e => fv e
  | Expr.borrow _ x e => (fv e).filter (fun y => !(y == x))
  | Expr.drop _ => []
  | Expr.call _ a body => fv a ++ fv body
  | Expr.ret e => fv e
  | Expr.spawn _ e => fv e
  | Expr.atomic _ e => fv e
  | Expr.unsafeE e => fv e
  | Expr.derefRaw e => fv e
  | Expr.abort _ => []

/-- Standard free variables (no `let`/`borrow` binder removal), used for the
    binding-free effect relation `EffHC`. -/
def fvE : Expr → List Var
  | Expr.val _ => []
  | Expr.var x => [x]
  | Expr.op a b => fvE a ++ fvE b
  | Expr.letE _ a b => fvE a ++ fvE b
  | Expr.move _ => []
  | Expr.read _ => []
  | Expr.write _ e => fvE e
  | Expr.seq a b => fvE a ++ fvE b
  | Expr.region _ e => fvE e
  | Expr.alloc _ e => fvE e
  | Expr.freeze _ => []
  | Expr.recover e => fvE e
  | Expr.borrow _ _ e => fvE e
  | Expr.drop _ => []
  | Expr.call _ a body => fvE a ++ fvE body
  | Expr.ret e => fvE e
  | Expr.spawn _ e => fvE e
  | Expr.atomic _ e => fvE e
  | Expr.unsafeE e => fvE e
  | Expr.derefRaw e => fvE e
  | Expr.abort _ => []

/-- All free variables of `e` are bound in `env`. -/
def VarsBound (env : EvalEnv) (e : Expr) : Prop :=
  ∀ x, x ∈ fv e → ∃ v, env x = some v

/-! ### Membership helpers -/

theorem mem_append_iff {α : Type} {a b : List α} {x : α} :
    x ∈ a ++ b ↔ x ∈ a ∨ x ∈ b := by
  induction a with
  | nil => exact ⟨fun h => Or.inr h, fun h => h.elim (fun h1 => nomatch h1) (fun h2 => h2)⟩
  | cons z zs ih =>
      constructor
      · intro h
        cases h with
        | head => exact Or.inl (List.Mem.head _)
        | tail _ ht =>
            cases ih.mp ht with
            | inl h1 => exact Or.inl (List.Mem.tail _ h1)
            | inr h2 => exact Or.inr h2
      · intro h
        cases h with
        | inl h1 =>
            cases h1 with
            | head => exact List.Mem.head _
            | tail _ ht => exact List.Mem.tail _ (ih.mpr (Or.inl ht))
        | inr h2 => exact List.Mem.tail _ (ih.mpr (Or.inr h2))

theorem mem_filter_subset' {α : Type} {f : α → Bool} {l : List α} {a : α}
    (h : a ∈ l.filter f) : a ∈ l := by
  induction l with
  | nil => cases h
  | cons b bs ih =>
      simp only [List.filter] at h
      cases hb : f b with
      | true =>
          rw [hb] at h
          simp only at h
          cases h with
          | head => exact List.Mem.head _
          | tail _ ht => exact List.Mem.tail _ (ih ht)
      | false =>
          rw [hb] at h
          simp only at h
          exact List.Mem.tail _ (ih h)

theorem mem_filter_true {α : Type} {f : α → Bool} {l : List α} {a : α}
    (h : a ∈ l.filter f) : f a = true := by
  induction l with
  | nil => cases h
  | cons b bs ih =>
      simp only [List.filter] at h
      cases hb : f b with
      | true =>
          rw [hb] at h
          simp only at h
          cases h with
          | head => exact hb
          | tail _ ht => exact ih ht
      | false =>
          rw [hb] at h
          simp only at h
          exact ih h

theorem ne_of_not_beq {a b : Nat} (h : (!(a == b)) = true) : a ≠ b := by
  intro hab
  have hb : (a == b) = true := (beq_iff_eq a b).mpr hab
  rw [hb] at h
  cases h

theorem setEnv_some_iff {env : EvalEnv} {x y : Var} {v w : RVal} :
    setEnv env x v y = some w ↔ (y = x ∧ v = w) ∨ (y ≠ x ∧ env y = some w) := by
  cases Nat.decEq y x with
  | isTrue hxy =>
      cases hxy
      rw [setEnv_same]
      constructor
      · intro hw
        cases hw
        exact Or.inl ⟨rfl, rfl⟩
      · intro h
        cases h with
        | inl h1 => rw [h1.2]
        | inr h2 => exact absurd rfl h2.1
  | isFalse hne =>
      rw [setEnv_other hne]
      constructor
      · intro hw
        exact Or.inr ⟨hne, hw⟩
      · intro h
        cases h with
        | inl h1 => exact absurd h1.1 hne
        | inr h2 => exact h2.2

/-! ### Typed expressions only mention bound variables

With outcome-typed `WTKH` the syntactic property splits: a **normal** outcome
guarantees that every free variable is bound, while an **aborting** outcome
does not (a prefix abort makes the continuation unreachable, so the calculus
deliberately does not type it — `opAborts`/`letAborts`/… have no premise for
the continuation).  Both forms are captured by the disjunctive statement
`WTKH.vars_bound_or_aborts`. -/

theorem WTKH.vars_bound_or_aborts {env : EvalEnv} {heap : EvalHeap} {e : Expr}
    {σ : Sigma} {o : Outcome} (h : WTKH env heap e σ o) :
    VarsBound env e ∨ ∃ σab : Sigma, o = .aborts σab := by
  induction h with
  | val => exact Or.inl (by intro x hx; cases hx)
  | var hx =>
      refine Or.inl ?_
      intro y hy
      cases hy with
      | head => exact ⟨_, hx⟩
      | tail _ ht => cases ht
  | abort => exact Or.inr ⟨_, rfl⟩
  | opOk ha hb iha ihb =>
      cases iha with
      | inl hA =>
          cases ihb with
          | inl hB =>
              refine Or.inl ?_
              intro y hy
              cases mem_append_iff.mp hy with
              | inl h1 => exact hA y h1
              | inr h2 => exact hB y h2
          | inr rest =>
              cases rest with
              | intro σab hB =>
                  exact Or.inr ⟨σab, by rw [hB]; exact Outcome.map_aborts _ _⟩
      | inr rest =>
          cases rest with
          | intro σab hA => cases hA
  | opAborts ha iha => exact Or.inr ⟨_, rfl⟩
  | letOk ha hb iha ihb =>
      cases iha with
      | inl hA =>
          cases ihb Val.unit with
          | inl hB =>
              refine Or.inl ?_
              intro y hy
              simp only [fv] at hy
              cases mem_append_iff.mp hy with
              | inl h1 => exact hA y h1
              | inr h2 =>
                  have hpred := mem_filter_true h2
                  have hne : y ≠ _ := ne_of_not_beq hpred
                  cases hB y (mem_filter_subset' h2) with
                  | intro w hw =>
                      cases setEnv_some_iff.mp hw with
                      | inl h1 => exact absurd h1.1 hne
                      | inr h2' => exact ⟨w, h2'.2⟩
          | inr rest =>
              cases rest with
              | intro σab hB => exact Or.inr ⟨σab, hB⟩
      | inr rest =>
          cases rest with
          | intro σab hA => cases hA
  | letAborts ha iha => exact Or.inr ⟨_, rfl⟩
  | move hp => exact Or.inl (by intro x hx; cases hx)
  | read hp hm => exact Or.inl (by intro x hx; cases hx)
  | writeOk he hw ihe =>
      cases ihe with
      | inl hE =>
          refine Or.inl ?_
          intro y hy
          exact hE y hy
      | inr rest =>
          cases rest with
          | intro σab hE => cases hE
  | writeAborts he ihe => exact Or.inr ⟨_, rfl⟩
  | seqOk ha hb iha ihb =>
      cases iha with
      | inl hA =>
          cases ihb with
          | inl hB =>
              refine Or.inl ?_
              intro y hy
              cases mem_append_iff.mp hy with
              | inl h1 => exact hA y h1
              | inr h2 => exact hB y h2
          | inr rest =>
              cases rest with
              | intro σab hB => exact Or.inr ⟨σab, hB⟩
      | inr rest =>
          cases rest with
          | intro σab hA => cases hA
  | seqAborts ha iha => exact Or.inr ⟨_, rfl⟩
  | regionOk he hsafe hno ihe =>
      cases ihe with
      | inl hE =>
          refine Or.inl ?_
          intro y hy
          exact hE y hy
      | inr rest =>
          cases rest with
          | intro σab hE => cases hE
  | regionAborts he hsafe ihe => exact Or.inr ⟨_, rfl⟩
  | allocOk he hcap ihe =>
      cases ihe with
      | inl hE =>
          refine Or.inl ?_
          intro y hy
          exact hE y hy
      | inr rest =>
          cases rest with
          | intro σab hE => cases hE
  | allocAborts he ihe => exact Or.inr ⟨_, rfl⟩
  | freeze hm hl => exact Or.inl (by intro x hx; cases hx)
  | recoverOk he ihe =>
      cases ihe with
      | inl hE =>
          refine Or.inl ?_
          intro y hy
          exact hE y hy
      | inr rest =>
          cases rest with
          | intro σab hE => cases hE
  | recoverAborts he ihe => exact Or.inr ⟨_, rfl⟩
  | borrow hm he ihe =>
      cases ihe with
      | inl hE =>
          refine Or.inl ?_
          intro y hy
          simp only [fv] at hy
          have hpred := mem_filter_true hy
          have hne : y ≠ _ := ne_of_not_beq hpred
          cases hE y (mem_filter_subset' hy) with
          | intro w hw =>
              cases setEnv_some_iff.mp hw with
              | inl h1 => exact absurd h1.1 hne
              | inr h2 => exact ⟨w, h2.2⟩
      | inr rest =>
          cases rest with
          | intro σab hE => exact Or.inr ⟨σab, hE⟩
  | drop hm => exact Or.inl (by intro x hx; cases hx)
  | callOk ha hcap hb iha ihb =>
      cases iha with
      | inl hA =>
          cases ihb with
          | inl hB =>
              refine Or.inl ?_
              intro y hy
              cases mem_append_iff.mp hy with
              | inl h1 => exact hA y h1
              | inr h2 => exact hB y h2
          | inr rest =>
              cases rest with
              | intro σab hB => exact Or.inr ⟨σab, hB⟩
      | inr rest =>
          cases rest with
          | intro σab hA => cases hA
  | callAborts ha iha => exact Or.inr ⟨_, rfl⟩
  | ret he ihe =>
      cases ihe with
      | inl hE => exact Or.inl (by intro y hy; exact hE y hy)
      | inr rest =>
          cases rest with
          | intro σab hE => exact Or.inr ⟨σab, hE⟩
  | spawnOk he hcap ihe =>
      cases ihe with
      | inl hE => exact Or.inl (by intro y hy; exact hE y hy)
      | inr rest =>
          cases rest with
          | intro σab hE => cases hE
  | spawnAborts he ihe => exact Or.inr ⟨_, rfl⟩
  | atomicOk he hm ihe =>
      cases ihe with
      | inl hE => exact Or.inl (by intro y hy; exact hE y hy)
      | inr rest =>
          cases rest with
          | intro σab hE => cases hE
  | atomicAborts he ihe => exact Or.inr ⟨_, rfl⟩
  | unsafeE he ihe =>
      cases ihe with
      | inl hE => exact Or.inl (by intro y hy; exact hE y hy)
      | inr rest =>
          cases rest with
          | intro σab hE => exact Or.inr ⟨σab, hE⟩
  | deref hp => exact Or.inl (by intro x hx; cases hx)

/-- Corollary for a normal outcome. -/
theorem WTKH.vars_bound {env : EvalEnv} {heap : EvalHeap} {e : Expr}
    {σ σ' : Sigma} {A : List Bid} (h : WTKH env heap e σ (.ok σ' A)) :
    VarsBound env e := by
  cases WTKH.vars_bound_or_aborts h with
  | inl h => exact h
  | inr rest =>
      cases rest with
      | intro σab ho => cases ho

end LSys
