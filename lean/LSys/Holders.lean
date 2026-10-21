/-
  LSys/Holders.lean

  T4a foundation (step 3): a dynamic `H` (holder occurrences) and a dynamic
  `ConsumeResult`.

  The static `ConsumeResult`/`l_consume` live in `LSys.State`.  Here the same
  occurrence-removal operation is defined on an explicit occurrence list
  (`HoldPos × Bid`), which is the runtime counterpart of `H`:

  * `removeOccD A occ` removes exactly the occurrences whose bid is in `A`;
  * `consumeD_exact` is the dynamic `L-Consume`;
  * `removeOccD_nil` is the dynamic `recover` consumption lemma.
-/

import LSys.Env

namespace LSys

inductive HoldPos where
  | heap (l : Loc)
  | env (x : Var)
  deriving Repr, DecidableEq

structure Occ where
  pos : HoldPos
  bid : Bid
  deriving Repr, DecidableEq

def removeOccD (A : List Bid) : List Occ → List Occ
  | [] => []
  | o :: rest => if A.elem o.bid then removeOccD A rest else o :: removeOccD A rest

theorem mem_removeOccD {A : List Bid} {occ : List Occ} {o : Occ} :
    o ∈ removeOccD A occ ↔ o ∈ occ ∧ o.bid ∉ A := by
  induction occ with
  | nil => exact ⟨fun h => nomatch h, fun h => nomatch h.1⟩
  | cons x xs ih =>
      cases hb : A.elem x.bid with
      | true =>
          have hbin : x.bid ∈ A := List.mem_of_elem_eq_true hb
          simp [removeOccD, hb]
          rw [ih]
          constructor
          · intro h
            exact ⟨List.Mem.tail _ h.1, h.2⟩
          · intro h
            cases h.1 with
            | head => exact absurd hbin h.2
            | tail _ hmem => exact ⟨hmem, h.2⟩
      | false =>
          have hnb : x.bid ∉ A := not_mem_of_elem_false hb
          simp [removeOccD, hb]
          constructor
          · intro h
            cases h with
            | head => exact ⟨List.Mem.head _, hnb⟩
            | tail _ hmem =>
                have hh := ih.mp hmem
                exact ⟨List.Mem.tail _ hh.1, hh.2⟩
          · intro h
            cases h.1 with
            | head => exact List.Mem.head _
            | tail _ hmem =>
                exact List.Mem.tail _ (ih.mpr ⟨hmem, h.2⟩)

/-- Dynamic `L-Consume`: consuming `A` removes exactly the `A` occurrences. -/
theorem consumeD_exact (A : List Bid) (occ : List Occ) (o : Occ) :
    o ∈ removeOccD A occ ↔ o ∈ occ ∧ o.bid ∉ A :=
  mem_removeOccD

theorem consumeD_removes {A : List Bid} {occ : List Occ} {o : Occ}
    (hb : o.bid ∈ A) : o ∉ removeOccD A occ := by
  intro h
  exact (mem_removeOccD.1 h).2 hb

theorem consumeD_keeps {A : List Bid} {occ : List Occ} {o : Occ}
    (hb : o.bid ∉ A) : o ∈ removeOccD A occ ↔ o ∈ occ := by
  rw [mem_removeOccD]
  exact ⟨fun h => h.1, fun h => ⟨h, hb⟩⟩

/-- If every occurrence is in the consumed set, `recover` leaves no holder. -/
theorem removeOccD_nil {A : List Bid} {occ : List Occ}
    (h : ∀ o, o ∈ occ → o.bid ∈ A) : removeOccD A occ = [] := by
  induction occ with
  | nil => rfl
  | cons x xs ih =>
      have hx : x.bid ∈ A := h x (List.Mem.head _)
      have hb : A.elem x.bid = true := List.elem_eq_true_of_mem hx
      simp only [removeOccD, hb]
      exact ih (fun o ho => h o (List.Mem.tail _ ho))

def consumeD (h : List Occ) (A : List Bid) : List Occ := removeOccD A h

/-- Runtime `H` update used by `recover`: consume the target handle set. -/
theorem recoverD_clears {occ : List Occ} {A : List Bid}
    (h : ∀ o, o ∈ occ → o.bid ∈ A) : consumeD occ A = [] :=
  removeOccD_nil h

end LSys
