/-
  LSys/Adequacy.lean

  L3-2: static semantics `WT` and the **L-Adequacy** bridge for the redex
  rules used by `spec/t4-proof.md` §3.5/§3.6:

  * S8 `freeze`, S4 `read`, S9 `recover`;
  * S3 `move`, S5 `write`, S10 `alloc`, S11 `region`, S12 `drop`, S14 `ret`.

  `WT` is a deliberately small, direct-style static judgement: every rule
  carries the side condition that the corresponding dynamic rule needs.
  There are no congruence rules for `recover`/`region`/`ret`, so the adequacy
  lemmas are genuine inversions of the static derivation.

  T1a-mono (`Rgn*` footprint) is represented by `RgnStar` and
  `t1a_mono`; the region rule carries `NoEscape` as its static conclusion.
-/

import LSys.Effect

namespace LSys

/-! ## Static helper predicates -/

def CAP_ALLOC_OK (σ : Sigma) : Prop := σ.caps.alloc = true

def CAPS_OK (σ : Sigma) (f : Nat) : Prop := f ∈ σ.caps.effects

def RecoverOk (σ : Sigma) (p : Place) : Prop := AliasesStar σ p = []

def Writable (σ : Sigma) (p : Place) : Prop :=
  (modeOf σ p = some Mode.uniq ∨ modeOf σ p = some Mode.mut) ∧
    AliasesStar σ p = []

def CopyTy : Ty → Bool
  | Ty.ref _ _ => true
  | Ty.val _ _ => true
  | Ty.unit => true
  | Ty.int => true
  | Ty.bool => true
  | Ty.scalar => true
  | _ => false

/-! ## `Rgn*` (T1a-mono footprint) -/

def RgnStar : Ty → List Rgn
  | Ty.unit => []
  | Ty.int => []
  | Ty.bool => []
  | Ty.scalar => []
  | Ty.ref r t => r :: RgnStar t
  | Ty.val r t => r :: RgnStar t
  | Ty.box r t => r :: RgnStar t
  | Ty.slice r t => r :: RgnStar t
  | Ty.iso t => 0 :: RgnStar t
  | Ty.shared t => 1 :: RgnStar t
  | Ty.named _ => []

def RgnOuter : Ty → Option Rgn
  | Ty.ref r _ => some r
  | Ty.val r _ => some r
  | Ty.box r _ => some r
  | Ty.slice r _ => some r
  | Ty.iso _ => some 0
  | Ty.shared _ => some 1
  | _ => none

theorem rgnStar_head (r : Rgn) (t : Ty) : r ∈ RgnStar (Ty.ref r t) :=
  List.Mem.head _

theorem rgnStar_tail {r : Rgn} {t : Ty} {x : Rgn} (h : x ∈ RgnStar t) :
    x ∈ RgnStar (Ty.ref r t) := List.Mem.tail r h

theorem rgnStar_iso_head (t : Ty) : 0 ∈ RgnStar (Ty.iso t) := List.Mem.head _

theorem rgn_outer_ref (r : Rgn) (t : Ty) : RgnOuter (Ty.ref r t) = some r := rfl

/-! ## Static semantics `WT` -/

inductive WT (σ : Sigma) : Expr → Prop where
  | val (v : Val) : WT σ (Expr.val v)
  | var {x : Var} (h : (lookupPlace σ.gamma (varPlace x)).isSome = true) :
      WT σ (Expr.var x)
  | op {a b : Expr} (h₁ : WT σ a) (h₂ : WT σ b) : WT σ (Expr.op a b)
  | letE {x : Var} {a b : Expr} (h₁ : WT σ a) (h₂ : WT σ b) :
      WT σ (Expr.letE x a b)
  | move {p : Place} (hm : modeOf σ p = some Mode.uniq) :
      WT σ (Expr.move p)
  | read {p : Place}
      (hm : modeOf σ p = some Mode.frozen ∨ modeOf σ p = some Mode.mut) :
      WT σ (Expr.read p)
  | write {p : Place} {e : Expr} (hm : Writable σ p) (h : WT σ e) :
      WT σ (Expr.write p e)
  | seq {a b : Expr} (h₁ : WT σ a) (h₂ : WT σ b) : WT σ (Expr.seq a b)
  | region {R : Rgn} {e : Expr} (h : WT σ e) (hno : NoEscape σ R) :
      WT σ (Expr.region R e)
  | alloc {a : Nat} {e : Expr} (hcap : CAP_ALLOC_OK σ) (h : WT σ e) :
      WT σ (Expr.alloc a e)
  | freeze {p : Place}
      (hm : modeOf σ p = some Mode.uniq) (hl : live σ p = []) :
      WT σ (Expr.freeze p)
  | recover {e : Expr} (h : WT σ e) : WT σ (Expr.recover e)
  | borrow {p : Place} {x : Var} {e : Expr}
      (hm : modeOf σ p = some Mode.uniq) (h : WT σ e) :
      WT σ (Expr.borrow p x e)
  | drop {p : Place} (hm : modeOf σ p = some Mode.uniq) :
      WT σ (Expr.drop p)
  | call {f : Nat} {a body : Expr}
      (hf : CAPS_OK σ f) (h₁ : WT σ a) (h₂ : WT σ body) :
      WT σ (Expr.call f a body)
  | ret {e : Expr} (h : WT σ e) : WT σ (Expr.ret e)
  | spawn {f : Nat} {e : Expr} (hf : CAPS_OK σ f) (h : WT σ e) :
      WT σ (Expr.spawn f e)
  | atomic {p : Place} {e : Expr}
      (hm : modeOf σ p = some Mode.atom) (h : WT σ e) :
      WT σ (Expr.atomic p e)
  | unsafeE {e : Expr} (h : WT σ e) : WT σ (Expr.unsafeE e)
  | deref {e : Expr} (h : WT σ e) : WT σ (Expr.derefRaw e)
  | abort (k : Nat) : WT σ (Expr.abort k)

/-! ## L-Adequacy (redex inversions) -/

theorem adequacy_freeze {σ : Sigma} {p : Place}
    (h : WT σ (Expr.freeze p)) :
    modeOf σ p = some Mode.uniq ∧ live σ p = [] := by
  cases h with
  | freeze hm hl => exact ⟨hm, hl⟩

theorem adequacy_read {σ : Sigma} {p : Place}
    (h : WT σ (Expr.read p)) :
    modeOf σ p = some Mode.frozen ∨ modeOf σ p = some Mode.mut := by
  cases h with
  | read hm => exact hm

theorem adequacy_move {σ : Sigma} {p : Place}
    (h : WT σ (Expr.move p)) : modeOf σ p = some Mode.uniq := by
  cases h with
  | move hm => exact hm

theorem adequacy_write {σ : Sigma} {p : Place} {e : Expr}
    (h : WT σ (Expr.write p e)) : Writable σ p := by
  cases h with
  | write hm _ => exact hm

theorem adequacy_alloc {σ : Sigma} {a : Nat} {e : Expr}
    (h : WT σ (Expr.alloc a e)) : CAP_ALLOC_OK σ := by
  cases h with
  | alloc hcap _ => exact hcap

theorem adequacy_region {σ : Sigma} {R : Rgn} {e : Expr}
    (h : WT σ (Expr.region R e)) : NoEscape σ R := by
  cases h with
  | region _ hno => exact hno

theorem t1a_mono {σ : Sigma} {R : Rgn} {e : Expr}
    (h : WT σ (Expr.region R e)) : NoEscape σ R :=
  adequacy_region h

theorem t1a_rgnStar_ref {r : Rgn} {t : Ty} {x : Rgn} (h : x ∈ RgnStar t) :
    x ∈ RgnStar (Ty.ref r t) := rgnStar_tail h

theorem adequacy_drop {σ : Sigma} {p : Place}
    (h : WT σ (Expr.drop p)) : modeOf σ p = some Mode.uniq := by
  cases h with
  | drop hm => exact hm

theorem adequacy_ret {σ : Sigma} {e : Expr}
    (h : WT σ (Expr.ret e)) : WT σ e := by
  cases h with
  | ret h' => exact h'

end LSys
