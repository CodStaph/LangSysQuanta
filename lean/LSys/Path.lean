/-
  LSys/Path.lean

  T4a foundation (step 5): field/index paths and the `Desc*`/`Anc*` relations.

  The runtime/`State` core keeps place identifiers opaque.  This module gives
  the path structure used by the paper's `overlap`, `Desc*`, and `Anc*`:
  a path is a list of fields/indices, `Prefix p q` means `p` is an ancestor
  of `q`, and `Desc p q = Prefix p q`.
-/

import LSys.State

namespace LSys

set_option linter.unusedVariables false


inductive Prefix : Path → Path → Prop where
  | nil (q : Path) : Prefix [] q
  | cons {a : Nat} {as bs : Path} : Prefix as bs → Prefix (a :: as) (a :: bs)

theorem prefix_nil (p : Path) : Prefix [] p := Prefix.nil p

theorem prefix_refl (p : Path) : Prefix p p := by
  induction p with
  | nil => exact Prefix.nil []
  | cons a as ih => exact Prefix.cons ih

theorem prefix_trans {p q r : Path} (h1 : Prefix p q) (h2 : Prefix q r) :
    Prefix p r := by
  induction h1 generalizing r with
  | nil => exact Prefix.nil r
  | cons h ih =>
      cases h2 with
      | cons h2' => exact Prefix.cons (ih h2')

theorem prefix_cons_inv {a : Nat} {as bs : Path}
    (h : Prefix (a :: as) (a :: bs)) : Prefix as bs := by
  cases h with
  | cons h' => exact h'

/-- A descendant path: `p` is a prefix of `q`. -/
def Desc (p q : Path) : Prop := Prefix p q

/-- An ancestor path: `q` is a prefix of `p`. -/
def Anc (p q : Path) : Prop := Prefix q p

theorem desc_refl (p : Path) : Desc p p := prefix_refl p

theorem desc_trans {p q r : Path} (h1 : Desc p q) (h2 : Desc q r) : Desc p r :=
  prefix_trans h1 h2

theorem desc_nil (p : Path) : Desc [] p := Prefix.nil p

theorem desc_cons {a : Nat} {as bs : Path} (h : Desc as bs) :
    Desc (a :: as) (a :: bs) := Prefix.cons h

theorem anc_refl (p : Path) : Anc p p := prefix_refl p

theorem anc_trans {p q r : Path} (h1 : Anc p q) (h2 : Anc q r) : Anc p r :=
  prefix_trans h2 h1

theorem desc_anc_antisymm {p q : Path} (h1 : Desc p q) (h2 : Anc p q) : p = q := by
  induction h1 with
  | nil =>
      cases h2 with
      | nil => rfl
  | cons h ih =>
      cases h2 with
      | cons h2' =>
          have hh := ih h2'
          rw [hh]

/-- Paper `overlap(p,q)`: one path is a prefix of the other. -/
def Overlap (p q : Path) : Prop := Desc p q ∨ Anc p q

theorem overlap_refl (p : Path) : Overlap p p := Or.inl (desc_refl p)

theorem overlap_symm {p q : Path} (h : Overlap p q) : Overlap q p := by
  cases h with
  | inl h => exact Or.inr h
  | inr h => exact Or.inl h

theorem desc_append (p q : Path) : Desc p (p ++ q) := by
  induction p with
  | nil => exact Prefix.nil _
  | cons a as ih => exact Prefix.cons ih

/-- The root (`[]`) overlaps every path. -/
theorem overlap_root (p : Path) : Overlap [] p := Or.inl (desc_nil p)

/-- Strict descendant: `p` is a proper prefix of `q`. -/
def StrictDesc (p q : Path) : Prop := Desc p q ∧ p ≠ q

end LSys
