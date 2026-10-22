/-
  LSys/CoherentK.lean

  Route A, step 6: the handle-aware runtime coupling re-founded on
  `EffHStepEvalCK` and the **outcome-typed** `WTKH`.

  Differences from `LSys/CoherentH.StepPMH` (kept as legacy):

  * the expression step is `EffHStepEvalCK`, which threads `env` and `Σ`:
    `letV` emits `setEnv` + `bindHolders`, `borrowEnter` emits `setEnv` +
    `addBorrow`;
  * the post typing is `WTKH`, derived by `WTKH.preserved`, and the **outcome
    is invariant** under steps.  Hence there is no `hwt_out` premise — the
    post judgement is `WTKH c'.env c'.heap c'.expr σ' o` for the *same* `o`;
  * no separate `wt_ctx`/plug lemma is needed: `EffHStepEvalCK` is already
    closed under the 14 congruence contexts and all 14 abort rules, so a step
    of `plug C e` is itself a configuration step (and `WTKH.preserved` applies
    to it directly).
-/

import LSys.StepBridge
import LSys.WTKH
import LSys.WTKHPreservation

namespace LSys

set_option linter.unusedVariables false

/-- `holdersOfVal` on the injected value constructor. -/
theorem holdersOfVal_ofVal (v : Val) : holdersOfVal (ofVal v) = Effect.holdersOfV v := by
  cases v <;> rfl

/-- The value alignment grows with a `let`/`borrow` binding: both the
    expression environment and the runtime environment gain the same binding. -/
theorem MatchV.setEnv {c ce' : ConfE} {env : EvalEnv} {heap : EvalHeap}
    {x : Var} {v : RVal} (hm : MatchV c env heap)
    (henv : ce'.env = setEnv c.env x v)
    (hheap : evalHeapOfConf ce' = evalHeapOfConf c) :
    MatchV ce' (setEnv env x v) heap := by
  constructor
  · intro y w hy
    cases Nat.decEq y x with
    | isTrue hxy =>
        cases hxy
        rw [setEnv_same] at hy
        cases hy
        rw [henv, setEnv_same]
    | isFalse hxy =>
        rw [setEnv_other hxy] at hy
        rw [henv, setEnv_other hxy]
        exact hm.env_sub y w hy
  · exact hm.heap_eq.trans hheap.symm

/-- Configuration after a `letV` step (`setEnv`, no state change). -/
def letConf (c : EvalConf) (b : Expr) (x : Var) (v : Val) : EvalConf :=
  { c with expr := b, env := setEnv c.env x (ofVal v) }

/-- Configuration after a `borrowEnter` step (`setEnv` + frame counter). -/
def borrowConf (c : EvalConf) (e : Expr) (x : Var) : EvalConf :=
  { c with expr := e, env := setEnv c.env x (RVal.refH 0), state := State.mk (c.state.borrow + 1) }

/-- Handle-aware, prefix-aware step coupled with the runtime configuration,
    over `EffHStepEvalCK`. -/
structure StepPMK (A' : List Bid) (σ : Sigma) (c : EvalConf) (e : Expr)
    (ce : ConfE) (s : State) (σ' : Sigma) (c' : EvalConf) (ce' : ConfE)
    (s' : State) : Prop where
  hstep : EffHStepEvalCK σ c e c' σ' A'
  match_pre : MatchUS σ ce s
  value_pre : MatchV ce c.env c.heap
  rstep : RStepE ce ce'
  match_post : MatchUS σ' ce' s'
  value_post : MatchV ce' c'.env c'.heap

/-- Pure expression steps (no runtime change) use the identity runtime step. -/
theorem StepPMK.ofStepRefl {A' : List Bid} {σ : Sigma} {c : EvalConf}
    {e : Expr} {c' : EvalConf} {σ' : Sigma} {ce : ConfE} {s : State}
    (hstep : EffHStepEvalCK σ c e c' σ' A')
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hm' : MatchUS σ' ce s) (hmv' : MatchV ce c'.env c'.heap) :
    StepPMK A' σ c e ce s σ' c' ce s :=
  ⟨hstep, hm, hmv, RStepE.refl, hm', hmv'⟩

/-- Generic redex: any configuration step together with a runtime step and the
    post matches. -/
theorem StepPMK.redex {A' : List Bid} {σ : Sigma} {c : EvalConf} {e : Expr}
    {c' : EvalConf} {σ' : Sigma} {ce : ConfE} {s : State} {ce' : ConfE}
    {s' : State} (hstep : EffHStepEvalCK σ c e c' σ' A')
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hr : RStepE ce ce') (hm' : MatchUS σ' ce' s')
    (hmv' : MatchV ce' c'.env c'.heap) :
    StepPMK A' σ c e ce s σ' c' ce' s' :=
  ⟨hstep, hm, hmv, hr, hm', hmv'⟩

/-- **Outcome-invariant preservation** at the hole: no `hwt_out`. -/
theorem StepPMK.wt {A' : List Bid} {σ : Sigma} {c : EvalConf} {e : Expr}
    {ce : ConfE} {s : State} {σ' : Sigma} {c' : EvalConf} {ce' : ConfE}
    {s' : State} (h : StepPMK A' σ c e ce s σ' c' ce' s')
    {o : Outcome} (hwt : WTKH c.env c.heap e σ o) :
    WTKH c'.env c'.heap c'.expr σ' o :=
  WTKH.preserved hwt h.hstep rfl rfl

/-- The active preservation interface. -/
theorem StepPMK.preservation {A' : List Bid} {σ : Sigma} {c : EvalConf}
    {e : Expr} {ce : ConfE} {s : State} {σ' : Sigma} {c' : EvalConf}
    {ce' : ConfE} {s' : State} (h : StepPMK A' σ c e ce s σ' c' ce' s')
    {o : Outcome} (hwt : WTKH c.env c.heap e σ o) :
    WTKH c'.env c'.heap c'.expr σ' o :=
  StepPMK.wt h hwt

/-- Typing inside a congruence context: because `EffHStepEvalCK` already
    contains the context rules, a step of `plug C e` is an ordinary
    configuration step — no plug lemma is needed. -/
theorem StepPMK.wt_plug {A' : List Bid} {σ : Sigma} {c c' : EvalConf}
    {C : Ctx} {e : Expr} {ce : ConfE} {s : State} {σ' : Sigma}
    {ce' : ConfE} {s' : State}
    (h : StepPMK A' σ c (plug C e) ce s σ' c' ce' s')
    {o : Outcome} (hwt : WTKH c.env c.heap (plug C e) σ o) :
    WTKH c'.env c'.heap c'.expr σ' o :=
  StepPMK.wt h hwt

/-! ## Value-consistent redexes -/

/-- Value-consistent `var` step: the residual value is the one bound in `env`. -/
theorem StepPMK.varV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {x : Var} {v : RVal} (hm : MatchUS σ ce s)
    (hmv : MatchV ce c.env c.heap) (h : c.env x = some v) :
    StepPMK (holdersOfR v) σ { c with expr := Expr.var x } (Expr.var x) ce s
      σ (withExpr c (Expr.val (toVal v))) ce s :=
  ⟨EffHStepEvalCK.varV h, hm, hmv, RStepE.refl, hm, hmv⟩

/-- Value-consistent `deref` step: the location `l` is the heap place `[l]`. -/
theorem StepPMK.derefV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {l : Loc} {v : RVal} (hm : MatchUS σ ce s)
    (hmv : MatchV ce c.env c.heap) (h : c.heap (locPlace l) = some v) :
    StepPMK (holdersOfR v) σ
      { c with expr := Expr.derefRaw (Expr.val (Val.loc l)) }
      (Expr.derefRaw (Expr.val (Val.loc l))) ce s
      σ (withExpr c (Expr.val (toVal v))) ce s :=
  ⟨EffHStepEvalCK.derefV h, hm, hmv, RStepE.refl, hm, hmv⟩

/-- Value-consistent `move` step (lookup premise); `move` changes `Σ`, so the
    post matches are premises. -/
theorem StepPMK.moveV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {p : Place} {v : RVal}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (h : c.heap p = some v)
    (hr : RStepE ce ce') (hm' : MatchUS (clearPlace σ p) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (toVal v))) :
    StepPMK (holdersOfR v) σ { c with expr := Expr.move p } (Expr.move p) ce s
      (clearPlace σ p) c' ce' s' := by
  subst hexpr
  exact ⟨EffHStepEvalCK.moveV h, hm, hmv, hr, hm', hmv'⟩

/-- Value-consistent `read` step (lookup premise). -/
theorem StepPMK.readV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {c' : EvalConf} {ce' : ConfE} {s' : State} {p : Place} {v : RVal}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (h : c.heap p = some v)
    (hr : RStepE ce ce')
    (hm' : MatchUS (addBorrow σ (freshBid σ) p Mode.frozen) ce' s')
    (hmv' : MatchV ce' c'.env c'.heap)
    (hexpr : c' = withExpr c (Expr.val (toVal v))) :
    StepPMK (holdersOfR v) σ { c with expr := Expr.read p } (Expr.read p) ce s
      (addBorrow σ (freshBid σ) p Mode.frozen) c' ce' s' := by
  subst hexpr
  exact ⟨EffHStepEvalCK.readV h, hm, hmv, hr, hm', hmv'⟩

/-- Value-consistent `let` step: the configuration step emits `setEnv` +
    `bindHolders`, the runtime step is `letVar`, and both alignments are
    derived (`MatchUS.letVarWithHolders`, `MatchV.setEnv`). -/
theorem StepPMK.letV {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State}
    {x : Var} {v : Val} {b : Expr}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hfresh : c.env x = none) (hfresh' : ce.env x = none) :
    StepPMK [] σ { c with expr := Expr.letE x (Expr.val v) b }
      (Expr.letE x (Expr.val v) b) ce s
      (bindHolders σ x (Effect.holdersOfV v))
      (letConf c b x v) (letVar ce x (ofVal v)) s :=
  ⟨EffHStepEvalCK.letV hfresh, hm, hmv, RStepE.letVar hfresh',
    holdersOfVal_ofVal v ▸ MatchUS.letVarWithHolders hm,
    MatchV.setEnv hmv rfl rfl⟩

/-- `borrow` entry: the configuration step binds `x` to the canonical borrow
    handle (`refH 0`) and adds the borrow to `Σ`; the runtime step is
    `borrowVar` with bid `0` (which also records the new `btab` entry).  The
    post `MatchUS` — including `p = [l]` and `rgnOf σ p = cellRgnOf ce l` — is a
    premise, because `addBorrow` changes `Σ`. -/
theorem StepPMK.borrowEnter {σ : Sigma} {c : EvalConf} {p : Place} {x : Var}
    {e : Expr} {ce : ConfE} {s : State} {l : Loc}
    (hm : MatchUS σ ce s) (hmv : MatchV ce c.env c.heap)
    (hfresh : c.env x = none) (hfresh' : ce.env x = none)
    (hm' : MatchUS (addBorrow σ 0 p Mode.mut) (borrowVar ce l x 0)
      (State.mk (s.borrow + 1))) :
    StepPMK [] σ { c with expr := Expr.borrow p x e } (Expr.borrow p x e) ce s
      (addBorrow σ 0 p Mode.mut)
      (borrowConf c e x)
      (borrowVar ce l x 0) (State.mk (s.borrow + 1)) :=
  ⟨EffHStepEvalCK.borrowEnter hfresh, hm, hmv, RStepE.borrowVar hfresh', hm',
    MatchV.setEnv hmv rfl rfl⟩

/-- `borrow` frame exit: the configuration step pops a frame, paired with the
    runtime `borrowPop`; the post `MatchUS` is derived. -/
theorem StepPMK.borrowExit {σ : Sigma} {c : EvalConf} {v : Val} {n : Nat}
    {ce : ConfE} {b : Bid}
    (hm : MatchUS σ { ce with flight := b :: ce.flight } (State.mk (n + 1)))
    (hmv : MatchV { ce with flight := b :: ce.flight } c.env c.heap) :
    StepPMK [] σ { c with expr := Expr.val v, state := State.mk (n + 1) }
      (Expr.val v) { ce with flight := b :: ce.flight } (State.mk (n + 1))
      σ { c with expr := Expr.val v, state := State.mk n } ce (State.mk n) :=
  ⟨EffHStepEvalCK.borrowExit, hm, hmv, RStepE.borrowPop, MatchUS.borrowPop hm,
    ⟨hmv.env_sub, by rw [← evalHeapOfConf_push]; exact hmv.heap_eq⟩⟩

/-- `abort` frame exit: same, for an aborting value. -/
theorem StepPMK.abortBorrow {σ : Sigma} {c : EvalConf} {k : Nat} {n : Nat}
    {ce : ConfE} {b : Bid}
    (hm : MatchUS σ { ce with flight := b :: ce.flight } (State.mk (n + 1)))
    (hmv : MatchV { ce with flight := b :: ce.flight } c.env c.heap) :
    StepPMK [] σ { c with expr := Expr.abort k, state := State.mk (n + 1) }
      (Expr.abort k) { ce with flight := b :: ce.flight } (State.mk (n + 1))
      σ { c with expr := Expr.abort k, state := State.mk n } ce (State.mk n) :=
  ⟨EffHStepEvalCK.abortBorrow, hm, hmv, RStepE.borrowPop, MatchUS.borrowPop hm,
    ⟨hmv.env_sub, by rw [← evalHeapOfConf_push]; exact hmv.heap_eq⟩⟩

/-! ## Multi-step closure -/

inductive StepPMKStar :
    Sigma → EvalConf → Expr → ConfE → State →
    Sigma → EvalConf → Expr → ConfE → State → Prop where
  | refl {σ : Sigma} {c : EvalConf} {ce : ConfE} {s : State} :
      StepPMKStar σ c c.expr ce s σ c c.expr ce s
  | step {σ : Sigma} {c : EvalConf} {e : Expr} {ce : ConfE} {s : State}
      {σ' : Sigma} {c' : EvalConf} {ce' : ConfE} {s' : State}
      {A' : List Bid} (h : StepPMK A' σ c e ce s σ' c' ce' s')
      {σ'' : Sigma} {c'' : EvalConf} {e'' : Expr} {ce'' : ConfE} {s'' : State}
      (rest : StepPMKStar σ' c' c'.expr ce' s' σ'' c'' e'' ce'' s'') :
      StepPMKStar σ c e ce s σ'' c'' e'' ce'' s''

/-- The outcome is preserved along any number of runtime-coupled steps. -/
theorem StepPMKStar.wt {σ : Sigma} {c : EvalConf} {e : Expr} {ce : ConfE}
    {s : State} :
    ∀ {σ' : Sigma} {c' : EvalConf} {e' : Expr} {ce' : ConfE} {s' : State},
      StepPMKStar σ c e ce s σ' c' e' ce' s' →
      ∀ {o : Outcome}, WTKH c.env c.heap e σ o →
        WTKH c'.env c'.heap e' σ' o := by
  intro σ' c' e' ce' s' hstar
  induction hstar with
  | refl => intro o hwt; exact hwt
  | step h _ ih => intro o hwt; exact ih (StepPMK.wt h hwt)

/-- Whole-run preservation. -/
theorem StepPMKStar.preservation {σ : Sigma} {c : EvalConf} {e : Expr}
    {ce : ConfE} {s : State} {σ' : Sigma} {c' : EvalConf} {e' : Expr}
    {ce' : ConfE} {s' : State}
    (hstar : StepPMKStar σ c e ce s σ' c' e' ce' s')
    {o : Outcome} (hwt : WTKH c.env c.heap e σ o) :
    WTKH c'.env c'.heap e' σ' o :=
  StepPMKStar.wt hstar hwt

end LSys
