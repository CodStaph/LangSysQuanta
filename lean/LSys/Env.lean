/-
  LSys/Env.lean

  T4a foundation (step 2): variable environments, `let`, `move`, `borrow`,
  and environment-held aliases.

  Modular extension of `LSys.Runtime`; the heap fragment stays unchanged.
  Environments are total functions (`Var → Option RVal`) so `let`/`move`/
  `borrow` preservation is constructive and Mathlib-free.

  WF fragment:
  * heap values point at live cells (I2);
  * environment values point at live cells (I2-env);
  * borrow targets are live (I1);
  * every borrow is in flight or held by an environment variable (I3);
  * unique bids (I4).

  Holder-to-borrow correspondence (I5) and `H`/`ConsumeResult` are the next
  module (`LSys.Holders`).
-/

import LSys.Runtime

namespace LSys

set_option linter.unusedVariables false

abbrev Env := Var → Option RVal
abbrev EnvHolds := Var → Option (List Bid)

structure ConfE where
  heap : Heap
  env : Env
  envHolds : EnvHolds
  btab : List BEntry
  flight : List Bid

def liveBE (c : ConfE) (l : Loc) : Bool :=
  match c.heap l with
  | some cell => cell.live
  | none => false

def isLiveValE (c : ConfE) : RVal → Bool
  | RVal.loc l => liveBE c l
  | RVal.refH b => hasBid c.btab b
  | RVal.valH b => hasBid c.btab b
  | _ => true

def setEnv (e : Env) (x : Var) (v : RVal) : Env :=
  fun y => if y = x then some v else e y

def removeEnv (e : Env) (x : Var) : Env :=
  fun y => if y = x then none else e y

theorem setEnv_same (e : Env) (x : Var) (v : RVal) : setEnv e x v x = some v := by
  unfold setEnv
  rw [if_pos rfl]

theorem setEnv_other {e : Env} {x y : Var} {v : RVal} (hne : y ≠ x) :
    setEnv e x v y = e y := by
  unfold setEnv
  rw [if_neg hne]

theorem removeEnv_same (e : Env) (x : Var) : removeEnv e x x = none := by
  unfold removeEnv
  rw [if_pos rfl]

theorem removeEnv_other {e : Env} {x y : Var} (hne : y ≠ x) :
    removeEnv e x y = e y := by
  unfold removeEnv
  rw [if_neg hne]

theorem setHolds_same (e : EnvHolds) (x : Var) (bs : List Bid) :
    (fun y => if y = x then some bs else e y) x = some bs := by
  dsimp only
  rw [if_pos rfl]

theorem setHolds_other {e : EnvHolds} {x y : Var} {bs : List Bid} (hne : y ≠ x) :
    (fun z => if z = x then some bs else e z) y = e y := by
  dsimp only
  rw [if_neg hne]

theorem removeHolds_same (e : EnvHolds) (x : Var) :
    (fun y => if y = x then none else e y) x = none := by
  dsimp only
  rw [if_pos rfl]

theorem removeHolds_other {e : EnvHolds} {x y : Var} (hne : y ≠ x) :
    (fun z => if z = x then none else e z) y = e y := by
  dsimp only
  rw [if_neg hne]

def heapHeldE (c : ConfE) (b : Bid) : Prop :=
  ∃ l cell, c.heap l = some cell ∧ b ∈ cell.holders

def envHeldE (c : ConfE) (b : Bid) : Prop :=
  ∃ x bs, c.envHolds x = some bs ∧ b ∈ bs

structure WFE (c : ConfE) : Prop where
  heap_locs : ∀ q cell l, c.heap q = some cell → cell.val = RVal.loc l →
    liveBE c l = true
  env_locs : ∀ x v l, c.env x = some v → v = RVal.loc l → liveBE c l = true
  btab_live : ∀ e, e ∈ c.btab → liveBE c e.target = true
  btab_held : ∀ e, e ∈ c.btab →
    e.bid ∈ c.flight ∨ heapHeldE c e.bid ∨ envHeldE c e.bid
  unique : ∀ e1 e2, e1 ∈ c.btab → e2 ∈ c.btab → e1.bid = e2.bid → e1 = e2

def cellRgnOf (c : ConfE) (l : Loc) : Rgn :=
  match c.heap l with
  | some cell => cell.rgn
  | none => 0

def letVar (c : ConfE) (x : Var) (v : RVal) : ConfE :=
  { c with
    env := setEnv c.env x v,
    envHolds := fun y => if y = x then some (holdersOfVal v) else c.envHolds y }

def moveVar (c : ConfE) (x : Var) (v : RVal) : ConfE :=
  { c with
    env := removeEnv c.env x,
    envHolds := fun y => if y = x then none else c.envHolds y,
    flight := holdersOfVal v ++ c.flight }

def borrowVar (c : ConfE) (l : Loc) (x : Var) (b : Bid) : ConfE :=
  { c with
    env := setEnv c.env x (RVal.refH b),
    envHolds := fun y => if y = x then some [b] else c.envHolds y,
    btab := { bid := b, target := l, mode := Mode.mut, rgn := cellRgnOf c l } :: c.btab }

theorem wfe_letVar {c : ConfE} {x : Var} {v : RVal} (hwf : WFE c)
    (hfresh : c.env x = none) (hfreshH : c.envHolds x = none)
    (hv : isLiveValE c v = true) : WFE (letVar c x v) := by
  constructor
  · intro q cell l hq hval
    exact hwf.heap_locs q cell l hq hval
  · intro y v' l hy hval
    cases hyeq : y == x with
    | true =>
        have heq := eq_of_beq_true hyeq
        rw [heq] at hy
        unfold letVar at hy
        dsimp only at hy
        rw [setEnv_same] at hy
        cases hy
        rw [hval] at hv
        exact hv
    | false =>
        have hne := ne_of_beq_false hyeq
        unfold letVar at hy
        dsimp only at hy
        rw [setEnv_other hne] at hy
        exact hwf.env_locs y v' l hy hval
  · intro e he
    exact hwf.btab_live e he
  · intro e he
    cases hwf.btab_held e he with
    | inl hfl => exact Or.inl hfl
    | inr hrest =>
        cases hrest with
        | inl hheap => exact Or.inr (Or.inl hheap)
        | inr hheld =>
            cases hheld with
            | intro y hy =>
            cases hy with
            | intro bs hbs =>
                cases hbs with
                | intro hsome hmem =>
                    cases hyeq : y == x with
                    | true =>
                        have heq := eq_of_beq_true hyeq
                        have hsomex : c.envHolds x = some bs := by
                          rw [← heq]
                          exact hsome
                        rw [hfreshH] at hsomex
                        cases hsomex
                    | false =>
                        have hne := ne_of_beq_false hyeq
                        refine Or.inr (Or.inr ⟨y, bs, ?_, hmem⟩)
                        unfold letVar
                        dsimp only
                        rw [if_neg hne]
                        exact hsome
  · intro e1 e2 h1 h2 hb
    exact hwf.unique e1 e2 h1 h2 hb

theorem wfe_moveVar {c : ConfE} {x : Var} {v : RVal} (hwf : WFE c)
    (hx : c.env x = some v) (hholds : c.envHolds x = some (holdersOfVal v)) :
    WFE (moveVar c x v) := by
  constructor
  · intro q cell l hq hval
    exact hwf.heap_locs q cell l hq hval
  · intro y v' l hy hval
    cases hyeq : y == x with
    | true =>
        have heq := eq_of_beq_true hyeq
        rw [heq] at hy
        unfold moveVar at hy
        dsimp only at hy
        rw [removeEnv_same] at hy
        cases hy
    | false =>
        have hne := ne_of_beq_false hyeq
        unfold moveVar at hy
        dsimp only at hy
        rw [removeEnv_other hne] at hy
        exact hwf.env_locs y v' l hy hval
  · intro e he
    exact hwf.btab_live e he
  · intro e he
    cases hwf.btab_held e he with
    | inl hfl => exact Or.inl (List.mem_append_of_mem_right (holdersOfVal v) hfl)
    | inr hrest =>
        cases hrest with
        | inl hheap => exact Or.inr (Or.inl hheap)
        | inr hheld =>
            cases hheld with
            | intro y hy =>
            cases hy with
            | intro bs hbs =>
                cases hbs with
                | intro hsome hmem =>
                    cases hyeq : y == x with
                    | true =>
                        have heq := eq_of_beq_true hyeq
                        have hbsx : c.envHolds x = some bs := by
                          rw [← heq]
                          exact hsome
                        rw [hholds] at hbsx
                        cases hbsx
                        exact Or.inl (List.mem_append_of_mem_left c.flight hmem)
                    | false =>
                        have hne := ne_of_beq_false hyeq
                        refine Or.inr (Or.inr ⟨y, bs, ?_, hmem⟩)
                        unfold moveVar
                        dsimp only
                        rw [if_neg hne]
                        exact hsome
  · intro e1 e2 h1 h2 hb
    exact hwf.unique e1 e2 h1 h2 hb

theorem wfe_borrowVar {c : ConfE} {l : Loc} {x : Var} {b : Bid} (hwf : WFE c)
    (hl : liveBE c l = true) (hfresh : c.env x = none) (hfreshH : c.envHolds x = none)
    (hbid : hasBid c.btab b = false) : WFE (borrowVar c l x b) := by
  constructor
  · intro q cell l' hq hval
    exact hwf.heap_locs q cell l' hq hval
  · intro y v' l' hy hval
    cases hyeq : y == x with
    | true =>
        have heq := eq_of_beq_true hyeq
        rw [heq] at hy
        unfold borrowVar at hy
        dsimp only at hy
        rw [setEnv_same] at hy
        cases hy
        cases hval
    | false =>
        have hne := ne_of_beq_false hyeq
        unfold borrowVar at hy
        dsimp only at hy
        rw [setEnv_other hne] at hy
        exact hwf.env_locs y v' l' hy hval
  · intro e he
    cases he with
    | head =>
        show liveBE c l = true
        exact hl
    | tail _ heold => exact hwf.btab_live e heold
  · intro e he
    cases he with
    | head =>
        refine Or.inr (Or.inr ⟨x, [b], ?_, ?_⟩)
        · unfold borrowVar; dsimp only; rw [if_pos rfl]
        · exact List.Mem.head _
    | tail _ heold =>
        cases hwf.btab_held e heold with
        | inl hfl => exact Or.inl hfl
        | inr hrest =>
            cases hrest with
            | inl hheap => exact Or.inr (Or.inl hheap)
            | inr hheld =>
                cases hheld with
                | intro y hy =>
                    cases hy with
                    | intro bs hbs =>
                        cases hbs with
                        | intro hsome hmem =>
                            cases hyeq : y == x with
                            | true =>
                                have heq := eq_of_beq_true hyeq
                                have hsomex : c.envHolds x = some bs := by
                                  rw [← heq]
                                  exact hsome
                                rw [hfreshH] at hsomex
                                cases hsomex
                            | false =>
                                have hne := ne_of_beq_false hyeq
                                refine Or.inr (Or.inr ⟨y, bs, ?_, hmem⟩)
                                unfold borrowVar
                                dsimp only
                                rw [if_neg hne]
                                exact hsome
  · intro e1 e2 h1 h2 hb
    cases h1 with
    | head =>
        cases h2 with
        | head => rfl
        | tail _ h2old =>
            have hne := hasBid_false hbid e2 h2old
            exact absurd hb.symm hne
    | tail _ h1old =>
        cases h2 with
        | head =>
            have hne := hasBid_false hbid e1 h1old
            exact absurd hb hne
        | tail _ h2old =>
            exact hwf.unique e1 e2 h1old h2old hb

end LSys
