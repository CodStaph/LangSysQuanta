/-
  LSys/EffHPath.lean

  Handle-aware context effects.

  * `EffHPre` is the prefix effect (no result handles yet); it is the same
    relation as `Effect.EffPre`.
  * `EffHPost C e σ σ' A B` is the suffix effect, taking the hole's result
    handles `A` and producing the context result handles `B`.
  * `EffHStepEval σ e e' σ' A` is the prefix-aware step effect with handles.
-/

import LSys.Effect

namespace LSys

set_option linter.unusedVariables false

/-- Prefix effect with `EffH` premises (handle-carrying). -/
inductive EffHPre : Ctx → Expr → Sigma → Sigma → Prop where
  | hole {e σ} : EffHPre Ctx.hole e σ σ
  | opL {c b e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.opL c b) e σ σ₁
  | opR {a c e σ σ₁ σ₂ A}
      (ha : Effect.EffH σ a σ₁ A) (hc : EffHPre c e σ₁ σ₂) :
      EffHPre (Ctx.opR a c) e σ σ₂
  | letB {x c b e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.letB x c b) e σ σ₁
  | writeB {p c e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.writeB p c) e σ σ₁
  | seqL {c b e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.seqL c b) e σ σ₁
  | allocB {a c e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.allocB a c) e σ σ₁
  | regionB {r c e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.regionB r c) e σ σ₁
  | recoverB {c e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.recoverB c) e σ σ₁
  | borrowB {p x c e σ σ₁} (hc : EffHPre c e (addBorrow σ 0 p Mode.mut) σ₁) :
      EffHPre (Ctx.borrowB p x c) e σ σ₁
  | callB {f c body e σ σ₁} (hc : EffHPre c e σ σ₁) :
      EffHPre (Ctx.callB f c body) e σ σ₁
  | retB {c e σ σ₁} (hc : EffHPre c e σ σ₁) : EffHPre (Ctx.retB c) e σ σ₁
  | spawnB {f c e σ σ₁} (hc : EffHPre c e σ σ₁) : EffHPre (Ctx.spawnB f c) e σ σ₁
  | atomicB {p c e σ σ₁} (hc : EffHPre c e σ σ₁) : EffHPre (Ctx.atomicB p c) e σ σ₁
  | unsafeB {c e σ σ₁} (hc : EffHPre c e σ σ₁) : EffHPre (Ctx.unsafeB c) e σ σ₁
  | derefB {c e σ σ₁} (hc : EffHPre c e σ σ₁) : EffHPre (Ctx.derefB c) e σ σ₁

/-- Suffix effect with handle threading. -/
inductive EffHPost : Ctx → Expr → Sigma → Sigma → List Bid → List Bid → Prop where
  | hole {e σ A} : EffHPost Ctx.hole e σ σ A A
  | opL {c b e σ σ₁ σ₂ A A₁ B}
      (hc : EffHPost c e σ σ₁ A A₁) (hb : Effect.EffH σ₁ b σ₂ B) :
      EffHPost (Ctx.opL c b) e σ σ₂ A B
  | opR {a c e σ σ₁ A B}
      (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.opR a c) e σ σ₁ A B
  | letB {x c b e σ σ₁ σ₂ A A₁ B}
      (hc : EffHPost c e σ σ₁ A A₁) (hb : Effect.EffH σ₁ b σ₂ B) :
      EffHPost (Ctx.letB x c b) e σ σ₂ A B
  | writeB {p c e σ σ₁ A A₁}
      (hc : EffHPost c e σ σ₁ A A₁) :
      EffHPost (Ctx.writeB p c) e σ (setHolders σ₁ p A₁) A []
  | seqL {c b e σ σ₁ σ₂ A A₁ B}
      (hc : EffHPost c e σ σ₁ A A₁) (hb : Effect.EffH σ₁ b σ₂ B) :
      EffHPost (Ctx.seqL c b) e σ σ₂ A B
  | allocB {a c e σ σ₁ A B}
      (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.allocB a c) e σ σ₁ A []
  | regionB {r c e σ σ₁ A B}
      (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.regionB r c) e σ σ₁ A B
  | recoverB {c e σ σ₁ A B}
      (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.recoverB c) e σ σ₁ A B
  | recoverBConsume {c e σ σ₁ A B}
      (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.recoverB c) e σ (ConsumeResult σ₁ B) A []
  | recoverH {b} :
      EffHPost (Ctx.recoverB Ctx.hole) (Expr.val (Val.valH b))
        σ (ConsumeResult σ [b]) [b] []
  | recoverVal {v} :
      EffHPost (Ctx.recoverB Ctx.hole) (Expr.val v) σ σ
        (Effect.holdersOfV v) []
  | borrowB {p x c e σ σ₁ A B}
      (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.borrowB p x c) e σ σ₁ A B
  | callB {f c body e σ σ₁ σ₂ A A₁ B}
      (hc : EffHPost c e σ σ₁ A A₁) (hb : Effect.EffH σ₁ body σ₂ B) :
      EffHPost (Ctx.callB f c body) e σ σ₂ A B
  | retB {c e σ σ₁ A B} (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.retB c) e σ σ₁ A B
  | spawnB {f c e σ σ₁ A B} (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.spawnB f c) e σ σ₁ A B
  | atomicB {p c e σ σ₁ A B} (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.atomicB p c) e σ σ₁ A B
  | unsafeB {c e σ σ₁ A B} (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.unsafeB c) e σ σ₁ A B
  | derefB {c e σ σ₁ A B} (hc : EffHPost c e σ σ₁ A B) :
      EffHPost (Ctx.derefB c) e σ σ₁ A B

/-- Prefix-aware step effect with handles. -/
inductive EffHStepEval : Sigma → Expr → Expr → Sigma → List Bid → Prop where
  | val {σ v} : EffHStepEval σ (Expr.val v) (Expr.val v) σ []
  | var {σ x v} : EffHStepEval σ (Expr.var x) (Expr.val v) σ []
  | abort {σ k} : EffHStepEval σ (Expr.abort k) (Expr.abort k) σ []
  | op {σ a b} :
      EffHStepEval σ (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        (Expr.val (Val.nat (a + b))) σ []
  | opAny {σ v w} :
      EffHStepEval σ (Expr.op (Expr.val v) (Expr.val w)) (Expr.val (Val.nat 0)) σ []
  | letV {σ x v b} : EffHStepEval σ (Expr.letE x (Expr.val v) b) b σ []
  | seqV {σ v b} : EffHStepEval σ (Expr.seq (Expr.val v) b) b σ []
  | callV {σ f v body} : EffHStepEval σ (Expr.call f (Expr.val v) body) body σ []
  | freeze {σ p b} :
      EffHStepEval σ (Expr.freeze p) (Expr.val (Val.valH b))
        (addBorrow σ b p Mode.frozen) [b]
  | recover {σ b l} :
      EffHStepEval σ (Expr.recover (Expr.val (Val.valH b))) (Expr.val (Val.loc l))
        (ConsumeResult σ [b]) []
  | recoverAny {σ v l} :
      EffHStepEval σ (Expr.recover (Expr.val v)) (Expr.val (Val.loc l)) σ []
  | write {σ p v} :
      EffHStepEval σ (Expr.write p (Expr.val v)) (Expr.val Val.unit)
        (setHolders σ p (Effect.holdersOfV v)) []
  | alloc {σ a v l} :
      EffHStepEval σ (Expr.alloc a (Expr.val v)) (Expr.val (Val.loc l)) σ []
  | move {σ p v} : EffHStepEval σ (Expr.move p) (Expr.val v) (clearPlace σ p) []
  | read {σ p b v} : EffHStepEval σ (Expr.read p) (Expr.val v) (addBorrow σ b p Mode.frozen) [b]
  | drop {σ p} : EffHStepEval σ (Expr.drop p) (Expr.val Val.unit) (clearPlace σ p) []
  | regionV {σ r v} : EffHStepEval σ (Expr.region r (Expr.val v)) (Expr.val v) σ []
  | retV {σ v} : EffHStepEval σ (Expr.ret (Expr.val v)) (Expr.val v) σ []
  | spawnV {σ f v} : EffHStepEval σ (Expr.spawn f (Expr.val v)) (Expr.val Val.unit) σ []
  | atomicV {σ p v} : EffHStepEval σ (Expr.atomic p (Expr.val v)) (Expr.val v) σ []
  | unsafeV {σ v} : EffHStepEval σ (Expr.unsafeE (Expr.val v)) (Expr.val v) σ []
  | derefV {σ l v} : EffHStepEval σ (Expr.derefRaw (Expr.val (Val.loc l))) (Expr.val v) σ []
  | derefAny {σ v} : EffHStepEval σ (Expr.derefRaw (Expr.val v)) (Expr.val (Val.nat 0)) σ []
  | borrowEnter {σ p x e} :
      EffHStepEval σ (Expr.borrow p x e) e (addBorrow σ 0 p Mode.mut) []
  | opL {σ a b a' σ₁ A} (h : EffHStepEval σ a a' σ₁ A) :
      EffHStepEval σ (Expr.op a b) (Expr.op a' b) σ₁ A
  | opR {σ a b b' σ₁ A} (hv : IsVal a) (h : EffHStepEval σ b b' σ₁ A) :
      EffHStepEval σ (Expr.op a b) (Expr.op a b') σ₁ A
  | letB {σ x a b a' σ₁ A} (h : EffHStepEval σ a a' σ₁ A) :
      EffHStepEval σ (Expr.letE x a b) (Expr.letE x a' b) σ₁ A
  | writeB {σ p e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.write p e) (Expr.write p e') σ₁ A
  | seqL {σ a b a' σ₁ A} (h : EffHStepEval σ a a' σ₁ A) :
      EffHStepEval σ (Expr.seq a b) (Expr.seq a' b) σ₁ A
  | allocB {σ a e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.alloc a e) (Expr.alloc a e') σ₁ A
  | regionB {σ r e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.region r e) (Expr.region r e') σ₁ A
  | recoverB {σ e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.recover e) (Expr.recover e') σ₁ A
  | callB {σ f a body a' σ₁ A} (h : EffHStepEval σ a a' σ₁ A) :
      EffHStepEval σ (Expr.call f a body) (Expr.call f a' body) σ₁ A
  | retB {σ e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.ret e) (Expr.ret e') σ₁ A
  | spawnB {σ f e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.spawn f e) (Expr.spawn f e') σ₁ A
  | atomicB {σ p e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.atomic p e) (Expr.atomic p e') σ₁ A
  | unsafeB {σ e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.unsafeE e) (Expr.unsafeE e') σ₁ A
  | derefB {σ e e' σ₁ A} (h : EffHStepEval σ e e' σ₁ A) :
      EffHStepEval σ (Expr.derefRaw e) (Expr.derefRaw e') σ₁ A


theorem effH_recoverH_step {σ : Sigma} {b : Bid} :
    ∃ σ_h σ_a A_h,
      EffHPre (Ctx.recoverB Ctx.hole) (Expr.val (Val.valH b)) σ σ_h ∧
      Effect.EffH σ_h (Expr.val (Val.valH b)) σ_a A_h ∧
      EffHPost (Ctx.recoverB Ctx.hole) (Expr.val (Val.valH b))
        σ_a (ConsumeResult σ [b]) A_h [] :=
  ⟨σ, σ, [b], EffHPre.recoverB EffHPre.hole,
    Effect.EffH.val σ (Val.valH b), EffHPost.recoverH⟩

theorem effH_recoverB_step {c : Ctx} {e : Expr} {σ σ_h σ_a σ₁ : Sigma}
    {A_h A_body : List Bid}
    (hpre : EffHPre c e σ σ_h)
    (heff : Effect.EffH σ_h e σ_a A_h)
    (hpost : EffHPost c e σ_a σ₁ A_h A_body) :
    ∃ σ_h σ_a A_h,
      EffHPre (Ctx.recoverB c) e σ σ_h ∧
      Effect.EffH σ_h e σ_a A_h ∧
      EffHPost (Ctx.recoverB c) e σ_a (ConsumeResult σ₁ A_body) A_h [] :=
  ⟨σ_h, σ_a, A_h, EffHPre.recoverB hpre, heff,
    EffHPost.recoverBConsume hpost⟩

theorem effH_plug_decomp {σ σ' : Sigma} {A : List Bid} {C : Ctx} {e : Expr}
    (h : Effect.EffH σ (plug C e) σ' A) :
    ∃ σ_h σ_a A_h,
      EffHPre C e σ σ_h ∧
      Effect.EffH σ_h e σ_a A_h ∧
      EffHPost C e σ_a σ' A_h A := by
  induction C generalizing σ σ' A e with
  | hole => exact ⟨σ, σ', A, EffHPre.hole, h, EffHPost.hole⟩
  | opL c b =>
      rename_i ih
      cases h with
      | op h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.opL hpre, heff, EffHPost.opL hpost h2⟩
  | opR a c =>
      rename_i ih
      cases h with
      | op h1 h2 =>
          cases ih h2 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.opR h1 hpre, heff, EffHPost.opR hpost⟩
  | letB x c b =>
      rename_i ih
      cases h with
      | letE h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.letB hpre, heff, EffHPost.letB hpost h2⟩
  | writeB p c =>
      rename_i ih
      cases h with
      | write h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.writeB hpre, heff, EffHPost.writeB hpost⟩
  | seqL c b =>
      rename_i ih
      cases h with
      | seq h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.seqL hpre, heff, EffHPost.seqL hpost h2⟩
  | allocB a c =>
      rename_i ih
      cases h with
      | alloc h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.allocB hpre, heff, EffHPost.allocB hpost⟩
  | regionB r c =>
      rename_i ih
      cases h with
      | region h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.regionB hpre, heff, EffHPost.regionB hpost⟩
  | recoverB c =>
      rename_i ih
      cases c with
      | hole =>
          cases h with
          | recover =>
              rename_i b
              exact effH_recoverH_step
          | recoverAny =>
              rename_i v hnot
              exact ⟨σ, σ, Effect.holdersOfV v, EffHPre.recoverB EffHPre.hole,
                Effect.EffH.val _ _, EffHPost.recoverVal⟩
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | opL c b =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | opR a c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | letB x c b =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | writeB p c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | seqL c b =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | allocB a c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | regionB r c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | recoverB c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | borrowB p x c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | callB f c body =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | retB c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | spawnB f c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | atomicB p c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | unsafeB c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost
      | derefB c =>
          cases h with
          | recoverCtx h1 =>
              cases ih h1 with
              | intro σ_h rest =>
                  cases rest with
                  | intro σ_a rest =>
                      cases rest with
                      | intro A_h rest =>
                          cases rest with
                          | intro hpre rest =>
                              cases rest with
                              | intro heff hpost =>
                                  exact effH_recoverB_step hpre heff hpost

  | borrowB p x c =>
      rename_i ih
      cases h with
      | borrow h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.borrowB hpre, heff, EffHPost.borrowB hpost⟩
  | callB f c body =>
      rename_i ih
      cases h with
      | call h1 h2 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.callB hpre, heff, EffHPost.callB hpost h2⟩
  | retB c =>
      rename_i ih
      cases h with
      | ret h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.retB hpre, heff, EffHPost.retB hpost⟩
  | spawnB f c =>
      rename_i ih
      cases h with
      | spawn h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.spawnB hpre, heff, EffHPost.spawnB hpost⟩
  | atomicB p c =>
      rename_i ih
      cases h with
      | atomic h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.atomicB hpre, heff, EffHPost.atomicB hpost⟩
  | unsafeB c =>
      rename_i ih
      cases h with
      | unsafeE h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.unsafeB hpre, heff, EffHPost.unsafeB hpost⟩
  | derefB c =>
      rename_i ih
      cases h with
      | deref h1 =>
          cases ih h1 with
          | intro σ_h rest =>
              cases rest with
              | intro σ_a rest =>
                  cases rest with
                  | intro A_h rest =>
                      cases rest with
                      | intro hpre rest =>
                          cases rest with
                          | intro heff hpost =>
                              exact ⟨σ_h, σ_a, A_h, EffHPre.derefB hpre, heff, EffHPost.derefB hpost⟩

end LSys
