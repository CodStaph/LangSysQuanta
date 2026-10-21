/-
  LSys/WTPlugCounterexample.lean

  Check of `wt_plug_eff`, the lemma needed to remove `sctx.hwt_out`.

  Result: **it is false for the current input-only `WT`.**  A `freeze` inside a
  `region R` block adds a borrow in `R`; the input state satisfies `NoEscape`
  and the post value is well typed, but the rebuilt `region R { val(valH b) }`
  no longer satisfies `NoEscape` for the post state.

  Therefore removing `hwt_out` requires a stronger static design: either an
  effect-aware `WT` that tracks the region body's effect (and checks
  `NoEscape` on both input and effect output), or a `RegionSafe` effect
  invariant.
-/

import LSys.Coherent

namespace LSys

set_option linter.unusedVariables false

def cexPlaceW : Place := []

def cexBindW : Binding :=
  { ty := Ty.int, mode := Mode.uniq, rgn := 0 }

def cexSigmaW : Sigma :=
  { gamma := [(cexPlaceW, cexBindW)],
    lam := [],
    moved := [],
    holders := [],
    caps := { alloc := true, effects := [] } }

def cexBorrowW : Borrow :=
  { bid := 0, place := cexPlaceW, mode := Mode.frozen, rgn := 0 }

def cexSigmaW' : Sigma := addBorrow cexSigmaW 0 cexPlaceW Mode.frozen

theorem cex_mode : modeOf cexSigmaW cexPlaceW = some Mode.uniq := by
  rfl

theorem cex_live : live cexSigmaW cexPlaceW = [] := by
  rfl

theorem cex_no_escape_in : NoEscape cexSigmaW 0 := by
  intro br hmem hrg
  simp [cexSigmaW] at hmem
  cases hmem

theorem cex_wt_freeze : WT cexSigmaW (Expr.freeze cexPlaceW) :=
  WT.freeze cex_mode cex_live

theorem cex_wt_region : WT cexSigmaW (Expr.region 0 (Expr.freeze cexPlaceW)) :=
  WT.region cex_wt_freeze cex_no_escape_in

theorem cex_eff : Coherent.Eff cexSigmaW (Expr.freeze cexPlaceW) cexSigmaW' :=
  Coherent.Eff.freeze cex_wt_freeze

theorem cex_wt_value : WT cexSigmaW' (Expr.val (Val.valH 0)) :=
  WT.val _

theorem cex_lam_mem : cexBorrowW ∈ cexSigmaW'.lam := by
  have hr : rgnOf cexSigmaW cexPlaceW = 0 := rfl
  simp [cexSigmaW', addBorrow, cexSigmaW, cexBorrowW, hr]
  exact List.Mem.head _

theorem cex_not_wt_region' :
    ¬ WT cexSigmaW' (Expr.region 0 (Expr.val (Val.valH 0))) := by
  intro h
  cases h with
  | region hinner hno =>
      exact hno cexBorrowW cex_lam_mem rfl

/-- `wt_plug_eff` fails on `Ctx.regionB 0 Ctx.hole`, `freeze`, `val(valH 0)`. -/
theorem not_wt_plug_eff :
    ¬ (∀ {σ σ' : Sigma} {C : Ctx} {e e' : Expr},
        WT σ (plug C e) → Coherent.Eff σ e σ' → WT σ' e' →
          WT σ' (plug C e')) := by
  intro h
  exact cex_not_wt_region'
    (h (C := Ctx.regionB 0 Ctx.hole) (e := Expr.freeze cexPlaceW)
      (e' := Expr.val (Val.valH 0)) cex_wt_region cex_eff cex_wt_value)

theorem cex_not_regionSafe_freeze :
    ¬ Effect.RegionSafe cexSigmaW 0 (Expr.freeze cexPlaceW) := by
  intro h
  have hno' := h (addBorrow cexSigmaW 0 cexPlaceW Mode.frozen) Effect.Eff.freeze
  exact hno' cexBorrowW cex_lam_mem rfl

/-- The proposed `regionSafe_eff_step` without a `Step` premise is false:
    `e'` can be an arbitrary expression that leaves an unconsumed borrow. -/
theorem not_regionSafe_eff_step :
    ¬ (∀ {σ σ' : Sigma} {R : Rgn} {C : Ctx} {e e' : Expr},
        Effect.RegionSafe σ R (plug C e) →
        Effect.Eff σ e σ' →
        Effect.RegionSafe σ' R (plug C e')) := by
  intro h
  have hpre : Effect.RegionSafe cexSigmaW 0 (plug Ctx.hole (Expr.val Val.unit)) :=
    Effect.regionSafe_val cex_no_escape_in
  have heff : Effect.Eff cexSigmaW (Expr.val Val.unit) cexSigmaW :=
    Effect.Eff.val _ _
  have hpost := h (R := 0) (C := Ctx.hole)
    (e := Expr.val Val.unit) (e' := Expr.freeze cexPlaceW) hpre heff
  exact cex_not_regionSafe_freeze hpost




end LSys




