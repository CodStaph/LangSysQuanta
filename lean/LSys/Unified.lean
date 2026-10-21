/-
  LSys/Unified.lean

  T4a foundation (integration 1–3): one configuration with heap + environment +
  heap/env holders + borrow table + flight, a unified `WFU` with `H ⇔ B`, and a
  dynamic `ConsumeResultU` that writes the consumed occurrences back into the
  configuration.

  This module closes the modular gap between `Runtime`, `Env`, and `Holders`:
  * `ConfE` (from `Env`) is the single configuration;
  * `WFU` includes heap-cell holders and environment holders, and both
    directions of the holder/borrow correspondence;
  * `ConsumeResultU` clears the consumed occurrences from heap and env holders
    and prunes the borrow table, and preserves `WFU`.
-/

import LSys.Env
import LSys.Holders

namespace LSys

set_option linter.unusedVariables false

/-- A heap occurrence of a bid. -/
def heapHeld (c : ConfE) (b : Bid) : Prop :=
  ∃ l cell, c.heap l = some cell ∧ b ∈ cell.holders

/-- An environment occurrence of a bid. -/
def envHeld (c : ConfE) (b : Bid) : Prop :=
  ∃ x bs, c.envHolds x = some bs ∧ b ∈ bs

/-- Unified WF with the full holder/borrow correspondence (`H ⇔ B`). -/
structure WFU (c : ConfE) extends WFE c : Prop where
  heap_holder_bid : ∀ l cell b, c.heap l = some cell → b ∈ cell.holders →
    ∃ e, e ∈ c.btab ∧ e.bid = b
  env_holder_bid : ∀ x bs b, c.envHolds x = some bs → b ∈ bs →
    ∃ e, e ∈ c.btab ∧ e.bid = b

/-- `H` occurrence at a holder position. -/
def holdsAtPos (c : ConfE) : HoldPos → List Bid
  | HoldPos.heap l =>
      match c.heap l with
      | some cell => cell.holders
      | none => []
  | HoldPos.env x =>
      match c.envHolds x with
      | some bs => bs
      | none => []

def HoldOccurs (c : ConfE) (o : Occ) : Prop := o.bid ∈ holdsAtPos c o.pos

def clearHeap (A : List Bid) (h : Heap) : Heap :=
  fun l => (h l).map (fun cell => { cell with holders := removeBids A cell.holders })

def clearEnvHolds (A : List Bid) (eh : EnvHolds) : EnvHolds :=
  fun x => (eh x).map (removeBids A)

def pruneBtab (A : List Bid) : List BEntry → List BEntry
  | [] => []
  | e :: es => if A.elem e.bid then pruneBtab A es else e :: pruneBtab A es

/-- Dynamic `ConsumeResult` on the unified configuration. -/
def ConsumeResultU (c : ConfE) (A : List Bid) : ConfE :=
  { c with
    heap := clearHeap A c.heap,
    envHolds := clearEnvHolds A c.envHolds,
    btab := pruneBtab A c.btab }

theorem mem_pruneBtab {A : List Bid} {btab : List BEntry} {e : BEntry} :
    e ∈ pruneBtab A btab ↔ e ∈ btab ∧ e.bid ∉ A := by
  induction btab with
  | nil => exact ⟨fun h => nomatch h, fun h => nomatch h.1⟩
  | cons x xs ih =>
      cases hb : A.elem x.bid with
      | true =>
          have hbin : x.bid ∈ A := List.mem_of_elem_eq_true hb
          simp [pruneBtab, hb]
          rw [ih]
          constructor
          · intro h
            exact ⟨List.Mem.tail _ h.1, h.2⟩
          · intro h
            cases h.1 with
            | head => exact absurd hbin h.2
            | tail _ hmem => exact ⟨hmem, h.2⟩
      | false =>
          simp [pruneBtab, hb]
          constructor
          · intro h
            cases h with
            | head => exact ⟨List.Mem.head _, not_mem_of_elem_false hb⟩
            | tail _ hmem =>
                have hh := ih.mp hmem
                exact ⟨List.Mem.tail _ hh.1, hh.2⟩
          · intro h
            cases h.1 with
            | head => exact List.Mem.head _
            | tail _ hmem => exact List.Mem.tail _ (ih.mpr ⟨hmem, h.2⟩)

theorem heap_clear_some {A : List Bid} {h : Heap} {q : Loc} {cell : Cell}
    (hq : clearHeap A h q = some cell) :
    ∃ old, h q = some old ∧ cell = { old with holders := removeBids A old.holders } := by
  unfold clearHeap at hq
  cases hold : h q with
  | none =>
      rw [hold] at hq
      simp [Option.map] at hq
  | some old =>
      rw [hold] at hq
      simp [Option.map] at hq
      cases hq
      exact ⟨old, rfl, rfl⟩

theorem holdsAtPos_clear (A : List Bid) (c : ConfE) (o : Occ) :
    HoldOccurs (ConsumeResultU c A) o ↔ HoldOccurs c o ∧ o.bid ∉ A := by
  cases o with
  | mk pos bid =>
      cases pos with
      | heap l =>
          unfold HoldOccurs ConsumeResultU holdsAtPos clearHeap
          dsimp only
          cases hc : c.heap l with
          | none =>
              simp [Option.map]
              constructor
              · intro h; cases h
              · intro h; cases h.1
          | some cell => simp [Option.map, mem_removeBids]
      | env x =>
          unfold HoldOccurs ConsumeResultU holdsAtPos clearEnvHolds
          dsimp only
          cases he : c.envHolds x with
          | none =>
              simp [Option.map]
              constructor
              · intro h; cases h
              · intro h; cases h.1
          | some bs => simp [Option.map, mem_removeBids]

theorem consumeU_exact (A : List Bid) (c : ConfE) (o : Occ) :
    HoldOccurs (ConsumeResultU c A) o ↔ HoldOccurs c o ∧ o.bid ∉ A :=
  holdsAtPos_clear A c o

theorem consumeU_removes {A : List Bid} {c : ConfE} {o : Occ}
    (hb : o.bid ∈ A) : ¬ HoldOccurs (ConsumeResultU c A) o := by
  intro h
  exact (holdsAtPos_clear A c o).1 h |>.2 hb


theorem isLiveValE_holders {c : ConfE} {v : RVal} {b : Bid}
    (hv : isLiveValE c v = true) (hb : b ∈ holdersOfVal v) :
    hasBid c.btab b = true := by
  cases v with
  | unit => cases hb
  | nat n => cases hb
  | loc l => cases hb
  | valH x =>
      simp only [holdersOfVal] at hb
      cases hb with
      | head => exact hv
      | tail _ h => cases h
  | refH x =>
      simp only [holdersOfVal] at hb
      cases hb with
      | head => exact hv
      | tail _ h => cases h

theorem wfu_letVar {c : ConfE} {x : Var} {v : RVal} (hwf : WFU c)
    (hfresh : c.env x = none) (hfreshH : c.envHolds x = none)
    (hv : isLiveValE c v = true) : WFU (letVar c x v) := by
  have hwfe : WFE (letVar c x v) := wfe_letVar hwf.toWFE hfresh hfreshH hv
  refine ⟨hwfe, ?_, ?_⟩
  · intro l cell b hcell hmem
    exact hwf.heap_holder_bid l cell b hcell hmem
  · intro y bs b hbs hmem
    cases hyeq : y == x with
    | true =>
        have heq := eq_of_beq_true hyeq
        rw [heq] at hbs
        unfold letVar at hbs
        dsimp only at hbs
        rw [if_pos rfl] at hbs
        cases hbs
        exact hasBid_true (isLiveValE_holders hv hmem)
    | false =>
        have hne := ne_of_beq_false hyeq
        unfold letVar at hbs
        dsimp only at hbs
        rw [if_neg hne] at hbs
        exact hwf.env_holder_bid y bs b hbs hmem

theorem wfu_moveVar {c : ConfE} {x : Var} {v : RVal} (hwf : WFU c)
    (hx : c.env x = some v) (hholds : c.envHolds x = some (holdersOfVal v)) :
    WFU (moveVar c x v) := by
  have hwfe : WFE (moveVar c x v) := wfe_moveVar hwf.toWFE hx hholds
  refine ⟨hwfe, ?_, ?_⟩
  · intro l cell b hcell hmem
    exact hwf.heap_holder_bid l cell b hcell hmem
  · intro y bs b hbs hmem
    cases hyeq : y == x with
    | true =>
        have heq := eq_of_beq_true hyeq
        rw [heq] at hbs
        unfold moveVar at hbs
        dsimp only at hbs
        rw [if_pos rfl] at hbs
        cases hbs
    | false =>
        have hne := ne_of_beq_false hyeq
        unfold moveVar at hbs
        dsimp only at hbs
        rw [if_neg hne] at hbs
        exact hwf.env_holder_bid y bs b hbs hmem

theorem wfu_borrowVar {c : ConfE} {l : Loc} {x : Var} {b : Bid} (hwf : WFU c)
    (hl : liveBE c l = true) (hfresh : c.env x = none) (hfreshH : c.envHolds x = none)
    (hbid : hasBid c.btab b = false) : WFU (borrowVar c l x b) := by
  have hwfe : WFE (borrowVar c l x b) :=
    wfe_borrowVar hwf.toWFE hl hfresh hfreshH hbid
  refine ⟨hwfe, ?_, ?_⟩
  · intro l' cell b' hcell hmem
    cases hwf.heap_holder_bid l' cell b' hcell hmem with
    | intro e he => exact ⟨e, List.Mem.tail _ he.1, he.2⟩
  · intro y bs b' hbs hmem
    cases hyeq : y == x with
    | true =>
        have heq := eq_of_beq_true hyeq
        rw [heq] at hbs
        unfold borrowVar at hbs
        dsimp only at hbs
        rw [if_pos rfl] at hbs
        cases hbs
        cases hmem with
        | head =>
            exact ⟨{ bid := b, target := l, mode := Mode.mut, rgn := cellRgnOf c l },
              List.Mem.head _, rfl⟩
        | tail _ h => cases h
    | false =>
        have hne := ne_of_beq_false hyeq
        unfold borrowVar at hbs
        dsimp only at hbs
        rw [if_neg hne] at hbs
        cases hwf.env_holder_bid y bs b' hbs hmem with
        | intro e he => exact ⟨e, List.Mem.tail _ he.1, he.2⟩


theorem liveBE_consumeU (c : ConfE) (A : List Bid) (l : Loc) :
    liveBE (ConsumeResultU c A) l = liveBE c l := by
  unfold liveBE ConsumeResultU clearHeap
  dsimp only
  cases hc : c.heap l with
  | none => simp [hc, Option.map]
  | some cell => simp [hc, Option.map]

theorem env_clear_some {A : List Bid} {eh : EnvHolds} {x : Var} {bs : List Bid}
    (h : clearEnvHolds A eh x = some bs) :
    ∃ old, eh x = some old ∧ bs = removeBids A old := by
  unfold clearEnvHolds at h
  cases he : eh x with
  | none =>
      rw [he] at h
      simp [Option.map] at h
  | some old =>
      rw [he] at h
      simp [Option.map] at h
      exact ⟨old, rfl, by rw [← h]⟩

theorem heap_clear_at {A : List Bid} {h : Heap} {l : Loc} {cell : Cell}
    (hq : h l = some cell) :
    clearHeap A h l = some { cell with holders := removeBids A cell.holders } := by
  unfold clearHeap
  rw [hq]
  simp [Option.map]

theorem env_clear_at {A : List Bid} {eh : EnvHolds} {x : Var} {bs : List Bid}
    (hx : eh x = some bs) :
    clearEnvHolds A eh x = some (removeBids A bs) := by
  unfold clearEnvHolds
  rw [hx]
  simp [Option.map]

/-- `ConsumeResultU` preserves the unified WF (`H ⇔ B`). -/
theorem consumeU_wfu {c : ConfE} {A : List Bid} (hwf : WFU c) :
    WFU (ConsumeResultU c A) := by
  have hwfe : WFE (ConsumeResultU c A) := by
    constructor
    · intro q cell l hq hval
      cases heap_clear_some hq with
      | intro old hold =>
          have hval_old : old.val = RVal.loc l := by
            rw [hold.2] at hval
            exact hval
          have hl := hwf.heap_locs q old l hold.1 hval_old
          rw [liveBE_consumeU]
          exact hl
    · intro x v l hx hval
      rw [liveBE_consumeU]
      exact hwf.env_locs x v l hx hval
    · intro e he
      rw [liveBE_consumeU]
      exact hwf.btab_live e (mem_pruneBtab.1 he).1
    · intro e he
      have hpair := mem_pruneBtab.1 he
      have hbnot : e.bid ∉ A := hpair.2
      cases hwf.btab_held e hpair.1 with
      | inl hfl => exact Or.inl hfl
      | inr hrest =>
          cases hrest with
          | inl hheap =>
              cases hheap with
              | intro l hcell =>
                  cases hcell with
                  | intro cell hc =>
                      cases hc with
                      | intro hlook hmem =>
                          exact Or.inr (Or.inl ⟨l,
                            { cell with holders := removeBids A cell.holders },
                            heap_clear_at hlook,
                            mem_removeBids.2 ⟨hmem, hbnot⟩⟩)
          | inr henv =>
              cases henv with
              | intro x hx =>
                  cases hx with
                  | intro bs hbs =>
                      cases hbs with
                      | intro hlook hmem =>
                          exact Or.inr (Or.inr ⟨x, removeBids A bs,
                            env_clear_at hlook,
                            mem_removeBids.2 ⟨hmem, hbnot⟩⟩)
    · intro e1 e2 h1 h2 hb
      exact hwf.unique e1 e2 (mem_pruneBtab.1 h1).1 (mem_pruneBtab.1 h2).1 hb
  refine ⟨hwfe, ?_, ?_⟩
  · intro l cell b hcell hmem
    cases heap_clear_some hcell with
    | intro old hold =>
        rw [hold.2] at hmem
        have hmem_old : b ∈ old.holders := (mem_removeBids.1 hmem).1
        have hbnot : b ∉ A := (mem_removeBids.1 hmem).2
        cases hwf.heap_holder_bid l old b hold.1 hmem_old with
        | intro e he =>
            exact ⟨e, mem_pruneBtab.2 ⟨he.1, by rw [he.2]; exact hbnot⟩, he.2⟩
  · intro x bs b hbs hmem
    cases env_clear_some hbs with
    | intro old hcase =>
        cases hcase with
        | intro hlook hbeq =>
            cases hbeq
            have hmem_old : b ∈ old := (mem_removeBids.1 hmem).1
            have hbnot : b ∉ A := (mem_removeBids.1 hmem).2
            cases hwf.env_holder_bid x old b hlook hmem_old with
            | intro e hent =>
                exact ⟨e, mem_pruneBtab.2 ⟨hent.1, by rw [hent.2]; exact hbnot⟩, hent.2⟩

theorem t1_wfu_no_dangling {c : ConfE} {q : Loc} {cell : Cell} {l : Loc}
    (hwf : WFU c) (hq : c.heap q = some cell) (hv : cell.val = RVal.loc l) :
    ∃ target, c.heap l = some target ∧ target.live = true := by
  have hl := hwf.heap_locs q cell l hq hv
  unfold liveBE at hl
  cases htarget : c.heap l with
  | none =>
      rw [htarget] at hl
      exact Bool.noConfusion hl
  | some target =>
      rw [htarget] at hl
      exact ⟨target, rfl, hl⟩

theorem t1_wfu_env_no_dangling {c : ConfE} {x : Var} {v : RVal} {l : Loc}
    (hwf : WFU c) (hx : c.env x = some v) (hv : v = RVal.loc l) :
    ∃ target, c.heap l = some target ∧ target.live = true := by
  have hl := hwf.env_locs x v l hx hv
  unfold liveBE at hl
  cases htarget : c.heap l with
  | none =>
      rw [htarget] at hl
      exact Bool.noConfusion hl
  | some target =>
      rw [htarget] at hl
      exact ⟨target, rfl, hl⟩

/-- **T3 (dynamic `ConsumeResultU`)**: if every current occurrence is in the
    consumed set `A`, then no occurrence survives in `ConsumeResultU c A`. -/
theorem t3_consumeU_consumes {c : ConfE} {A : List Bid}
    (h : ∀ o, HoldOccurs c o → o.bid ∈ A) :
    ∀ o, ¬ HoldOccurs (ConsumeResultU c A) o := by
  intro o ho
  exact (holdsAtPos_clear A c o).1 ho |>.2 (h o ((holdsAtPos_clear A c o).1 ho).1)


end LSys
