/-
  LSys/Coherent.lean

  Coherent `Eff` / `StepPM` for preservation.

  * `Eff` is a small-step static effect relation; every rule carries the `WT`
    premises it needs.
  * `StepPM` is an inductive, per-rule coupled relation: each constructor
    provides the expression step, runtime step, static effect, `RedexOK`, the
    input `MatchU`, and the post `MatchU`.
  * `stepPM_wt` derives the post `WT`; `preservation` combines it with the
    coupled post `MatchU`.
-/

import LSys.Preservation
import LSys.WTPreservation

namespace LSys
namespace Coherent

set_option linter.unusedVariables false

def holdersOfV : Val → List Bid
  | Val.valH b => [b]
  | Val.refH b => [b]
  | _ => []

/-- Small-step static effects, with `WT` premises. -/
inductive Eff : Sigma → Expr → Sigma → Prop where
  | val {σ} {v} (hwt : WT σ (Expr.val v)) : Eff σ (Expr.val v) σ
  | var {σ} {x} (hwt : WT σ (Expr.var x)) : Eff σ (Expr.var x) σ
  | abort {σ} {k} (hwt : WT σ (Expr.abort k)) : Eff σ (Expr.abort k) σ
  | op {σ} {a b} (hwt : WT σ (Expr.op a b)) : Eff σ (Expr.op a b) σ
  | freeze {σ} {p b} (hwt : WT σ (Expr.freeze p)) :
      Eff σ (Expr.freeze p) (addBorrow σ b p Mode.frozen)
  | recover {σ} {b} (hwt : WT σ (Expr.recover (Expr.val (Val.valH b)))) :
      Eff σ (Expr.recover (Expr.val (Val.valH b))) (ConsumeResult σ [b])
  | recoverAny {σ} {v} (hwt : WT σ (Expr.recover (Expr.val v))) :
      Eff σ (Expr.recover (Expr.val v)) σ
  | write {σ} {p v} (hwt : WT σ (Expr.write p (Expr.val v))) :
      Eff σ (Expr.write p (Expr.val v)) (setHolders σ p (holdersOfV v))
  | alloc {σ} {a v} (hwt : WT σ (Expr.alloc a (Expr.val v))) :
      Eff σ (Expr.alloc a (Expr.val v)) σ
  | move {σ} {p} (hwt : WT σ (Expr.move p)) : Eff σ (Expr.move p) (clearPlace σ p)
  | read {σ} {p} (hwt : WT σ (Expr.read p)) :
      Eff σ (Expr.read p) (addBorrow σ 0 p Mode.frozen)
  | drop {σ} {p} (hwt : WT σ (Expr.drop p)) : Eff σ (Expr.drop p) (clearPlace σ p)
  | region {σ} {r v} (hwt : WT σ (Expr.region r (Expr.val v))) :
      Eff σ (Expr.region r (Expr.val v)) σ
  | ret {σ} {v} (hwt : WT σ (Expr.ret (Expr.val v))) :
      Eff σ (Expr.ret (Expr.val v)) σ
  | spawn {σ} {f v} (hwt : WT σ (Expr.spawn f (Expr.val v))) :
      Eff σ (Expr.spawn f (Expr.val v)) σ
  | atomic {σ} {p v} (hwt : WT σ (Expr.atomic p (Expr.val v))) :
      Eff σ (Expr.atomic p (Expr.val v)) σ
  | unsafeE {σ} {v} (hwt : WT σ (Expr.unsafeE (Expr.val v))) :
      Eff σ (Expr.unsafeE (Expr.val v)) σ
  | deref {σ} {v} (hwt : WT σ (Expr.derefRaw (Expr.val v))) :
      Eff σ (Expr.derefRaw (Expr.val v)) σ
  | letV {σ} {x} {v} {b} (hwtBody : WT σ b) :
      Eff σ (Expr.letE x (Expr.val v) b) σ
  | seqV {σ} {v} {b} (hwtBody : WT σ b) : Eff σ (Expr.seq (Expr.val v) b) σ
  | callV {σ} {f} {v} {body} (hwtBody : WT σ body) :
      Eff σ (Expr.call f (Expr.val v) body) σ
  | borrowEnter {σ} {p x e} (hwtBody : WT σ e) :
      Eff σ (Expr.borrow p x e) σ

/-- Per-rule coupled preservation step. -/
inductive StepPM : Sigma → ConfE → Expr → State → Sigma → ConfE → Expr → State → Prop where
  | sval {σ c s c' s' v}
      (hm : MatchU σ c s) (hs : Step (Expr.val v) s (Expr.val v) s')
      (hr : RStepE c c') (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.val v) s σ c' (Expr.val v) s'
  | svar {σ c s c' s' x v}
      (hm : MatchU σ c s) (hs : Step (Expr.var x) s (Expr.val v) s')
      (hr : RStepE c c') (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.var x) s σ c' (Expr.val v) s'
  | sabort {σ c s c' s' k}
      (hm : MatchU σ c s) (hs : Step (Expr.abort k) s (Expr.abort k) s')
      (hr : RStepE c c') (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.abort k) s σ c' (Expr.abort k) s'
  | sop {σ c s c' s' a b}
      (hm : MatchU σ c s)
      (hs : Step (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        s (Expr.val (Val.nat (a + b))) s')
      (hr : RStepE c c')
      (heff : Eff σ (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b))) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.op (Expr.val (Val.nat a)) (Expr.val (Val.nat b)))
        s σ c' (Expr.val (Val.nat (a + b))) s'
  | sopAny {σ c s c' s' v w}
      (hm : MatchU σ c s)
      (hs : Step (Expr.op (Expr.val v) (Expr.val w)) s (Expr.val (Val.nat 0)) s')
      (hr : RStepE c c')
      (heff : Eff σ (Expr.op (Expr.val v) (Expr.val w)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.op (Expr.val v) (Expr.val w)) s σ c' (Expr.val (Val.nat 0)) s'
  | sfreeze {σ c s c' s' p b}
      (hm : MatchU σ c s) (hs : Step (Expr.freeze p) s (Expr.val (Val.valH b)) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.freeze p) (addBorrow σ b p Mode.frozen))
      (hm' : MatchU (addBorrow σ b p Mode.frozen) c' s') :
      StepPM σ c (Expr.freeze p) s (addBorrow σ b p Mode.frozen)
        c' (Expr.val (Val.valH b)) s'
  | srecover {σ c s c' s' b l}
      (hm : MatchU σ c s)
      (hs : Step (Expr.recover (Expr.val (Val.valH b))) s (Expr.val (Val.loc l)) s')
      (hr : RStepE c c')
      (heff : Eff σ (Expr.recover (Expr.val (Val.valH b))) (ConsumeResult σ [b]))
      (hm' : MatchU (ConsumeResult σ [b]) c' s') :
      StepPM σ c (Expr.recover (Expr.val (Val.valH b))) s
        (ConsumeResult σ [b]) c' (Expr.val (Val.loc l)) s'
  | srecoverAny {σ c s c' s' v l}
      (hm : MatchU σ c s) (hs : Step (Expr.recover (Expr.val v)) s (Expr.val (Val.loc l)) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.recover (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.recover (Expr.val v)) s σ c' (Expr.val (Val.loc l)) s'
  | swrite {σ c s c' s' p v}
      (hm : MatchU σ c s) (hs : Step (Expr.write p (Expr.val v)) s (Expr.val Val.unit) s')
      (hr : RStepE c c')
      (heff : Eff σ (Expr.write p (Expr.val v)) (setHolders σ p (holdersOfV v)))
      (hm' : MatchU (setHolders σ p (holdersOfV v)) c' s') :
      StepPM σ c (Expr.write p (Expr.val v)) s
        (setHolders σ p (holdersOfV v)) c' (Expr.val Val.unit) s'
  | salloc {σ c s c' s' a v l}
      (hm : MatchU σ c s) (hs : Step (Expr.alloc a (Expr.val v)) s (Expr.val (Val.loc l)) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.alloc a (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.alloc a (Expr.val v)) s σ c' (Expr.val (Val.loc l)) s'
  | smove {σ c s c' s' p v}
      (hm : MatchU σ c s) (hs : Step (Expr.move p) s (Expr.val v) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.move p) (clearPlace σ p))
      (hm' : MatchU (clearPlace σ p) c' s') :
      StepPM σ c (Expr.move p) s (clearPlace σ p) c' (Expr.val v) s'
  | sread {σ c s c' s' p v}
      (hm : MatchU σ c s) (hs : Step (Expr.read p) s (Expr.val v) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.read p) (addBorrow σ 0 p Mode.frozen))
      (hm' : MatchU (addBorrow σ 0 p Mode.frozen) c' s') :
      StepPM σ c (Expr.read p) s (addBorrow σ 0 p Mode.frozen) c' (Expr.val v) s'
  | sdrop {σ c s c' s' p}
      (hm : MatchU σ c s) (hs : Step (Expr.drop p) s (Expr.val Val.unit) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.drop p) (clearPlace σ p))
      (hm' : MatchU (clearPlace σ p) c' s') :
      StepPM σ c (Expr.drop p) s (clearPlace σ p) c' (Expr.val Val.unit) s'
  | sregion {σ c s c' s' r v}
      (hm : MatchU σ c s) (hs : Step (Expr.region r (Expr.val v)) s (Expr.val v) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.region r (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.region r (Expr.val v)) s σ c' (Expr.val v) s'
  | sret {σ c s c' s' v}
      (hm : MatchU σ c s) (hs : Step (Expr.ret (Expr.val v)) s (Expr.val v) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.ret (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.ret (Expr.val v)) s σ c' (Expr.val v) s'
  | sspawn {σ c s c' s' f v}
      (hm : MatchU σ c s) (hs : Step (Expr.spawn f (Expr.val v)) s (Expr.val Val.unit) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.spawn f (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.spawn f (Expr.val v)) s σ c' (Expr.val Val.unit) s'
  | satomic {σ c s c' s' p v}
      (hm : MatchU σ c s) (hs : Step (Expr.atomic p (Expr.val v)) s (Expr.val v) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.atomic p (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.atomic p (Expr.val v)) s σ c' (Expr.val v) s'
  | sunsafe {σ c s c' s' v}
      (hm : MatchU σ c s) (hs : Step (Expr.unsafeE (Expr.val v)) s (Expr.val v) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.unsafeE (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.unsafeE (Expr.val v)) s σ c' (Expr.val v) s'
  | sderef {σ c s c' s' l v}
      (hm : MatchU σ c s) (hs : Step (Expr.derefRaw (Expr.val (Val.loc l))) s (Expr.val v) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.derefRaw (Expr.val (Val.loc l))) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.derefRaw (Expr.val (Val.loc l))) s σ c' (Expr.val v) s'
  | sderefAny {σ c s c' s' v}
      (hm : MatchU σ c s) (hs : Step (Expr.derefRaw (Expr.val v)) s (Expr.val (Val.nat 0)) s')
      (hr : RStepE c c') (heff : Eff σ (Expr.derefRaw (Expr.val v)) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.derefRaw (Expr.val v)) s σ c' (Expr.val (Val.nat 0)) s'
  | sletV {σ c s c' s' x v b}
      (hm : MatchU σ c s) (hs : Step (Expr.letE x (Expr.val v) b) s b s')
      (hr : RStepE c c') (heff : Eff σ (Expr.letE x (Expr.val v) b) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.letE x (Expr.val v) b) s σ c' b s'
  | sseqV {σ c s c' s' v b}
      (hm : MatchU σ c s) (hs : Step (Expr.seq (Expr.val v) b) s b s')
      (hr : RStepE c c') (heff : Eff σ (Expr.seq (Expr.val v) b) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.seq (Expr.val v) b) s σ c' b s'
  | scallV {σ c s c' s' f v body}
      (hm : MatchU σ c s) (hs : Step (Expr.call f (Expr.val v) body) s body s')
      (hr : RStepE c c') (heff : Eff σ (Expr.call f (Expr.val v) body) σ)
      (hm' : MatchU σ c' s') :
      StepPM σ c (Expr.call f (Expr.val v) body) s σ c' body s'
  | sborrowEnter {σ : Sigma} {c : ConfE} {s : State} {c' : ConfE} {s' : State}
      {p : Place} {x : Var} {e : Expr}
      (hm : MatchU σ c s) (hs : Step (Expr.borrow p x e) s e (State.mk (s.borrow + 1)))
      (hr : RStepE c c') (heff : Eff σ (Expr.borrow p x e) σ)
      (hm' : MatchU σ c' (State.mk (s.borrow + 1))) :
      StepPM σ c (Expr.borrow p x e) s σ c' e (State.mk (s.borrow + 1))
  | sabortCtx {σ c s c' s' C k}
      (hnot : C ≠ Ctx.hole)
      (hm : MatchU σ c s)
      (hs : Step (plug C (Expr.abort k)) s (Expr.abort k) s')
      (hr : RStepE c c') (hm' : MatchU σ c' s') :
      StepPM σ c (plug C (Expr.abort k)) s σ c' (Expr.abort k) s'
  | sctx {σ c e s σ' c' e' s' C}
      (hchild : StepPM σ c e s σ' c' e' s')
      (hm : MatchU σ c s) (hm' : MatchU σ' c' s')
      (hwt_out : WT σ' (plug C e')) :
      StepPM σ c (plug C e) s σ' c' (plug C e') s'

/-- Post `WT` of a coherent step (recursive; `sctx` uses the child IH). -/
theorem stepPM_wt {σ : Sigma} {c : ConfE} {e : Expr} {s : State}
    {σ' : Sigma} {c' : ConfE} {e' : Expr} {s' : State}
    (hstep : StepPM σ c e s σ' c' e' s') (hwt : WT σ e) : WT σ' e' := by
  induction hstep with
  | sval => exact WT.val _
  | svar => exact WT.val _
  | sabort => exact WT.abort _
  | sop => exact WT.val _
  | sopAny => exact WT.val _
  | sfreeze => exact WT.val _
  | srecover => exact WT.val _
  | srecoverAny => exact WT.val _
  | swrite => exact WT.val _
  | salloc => exact WT.val _
  | smove => exact WT.val _
  | sread => exact WT.val _
  | sdrop => exact WT.val _
  | sregion => exact WT.val _
  | sret => exact WT.val _
  | sspawn => exact WT.val _
  | satomic => exact WT.val _
  | sunsafe => exact WT.val _
  | sderef => exact WT.val _
  | sderefAny => exact WT.val _
  | sletV => exact (by
      cases hwt with
      | letE h1 h2 => exact h2)
  | sseqV => exact (by
      cases hwt with
      | seq h1 h2 => exact h2)
  | scallV => exact (by
      cases hwt with
      | call hf h1 h2 => exact h2)
  | sborrowEnter => exact (by
      cases hwt with
      | borrow hm h1 => exact h1)
  | sabortCtx => exact WT.abort _
  | sctx hchild hm hm' hwt_out =>
      exact hwt_out

/-- Post `MatchU` of a coherent step. -/
theorem stepPM_post {σ : Sigma} {c : ConfE} {e : Expr} {s : State}
    {σ' : Sigma} {c' : ConfE} {e' : Expr} {s' : State}
    (hstep : StepPM σ c e s σ' c' e' s') : MatchU σ' c' s' := by
  induction hstep with
  | sval hm hs hr hm' => exact hm'
  | svar hm hs hr hm' => exact hm'
  | sabort hm hs hr hm' => exact hm'
  | sop hm hs hr heff hm' => exact hm'
  | sopAny hm hs hr heff hm' => exact hm'
  | sfreeze hm hs hr heff hm' => exact hm'
  | srecover hm hs hr heff hm' => exact hm'
  | srecoverAny hm hs hr heff hm' => exact hm'
  | swrite hm hs hr heff hm' => exact hm'
  | salloc hm hs hr heff hm' => exact hm'
  | smove hm hs hr heff hm' => exact hm'
  | sread hm hs hr heff hm' => exact hm'
  | sdrop hm hs hr heff hm' => exact hm'
  | sregion hm hs hr heff hm' => exact hm'
  | sret hm hs hr heff hm' => exact hm'
  | sspawn hm hs hr heff hm' => exact hm'
  | satomic hm hs hr heff hm' => exact hm'
  | sunsafe hm hs hr heff hm' => exact hm'
  | sderef hm hs hr heff hm' => exact hm'
  | sderefAny hm hs hr heff hm' => exact hm'
  | sletV hm hs hr heff hm' => exact hm'
  | sseqV hm hs hr heff hm' => exact hm'
  | scallV hm hs hr heff hm' => exact hm'
  | sborrowEnter hm hs hr heff hm' => exact hm'
  | sabortCtx hnot hm hs hr hm' => exact hm'
  | sctx hchild hm hm' hwt_out => exact hm'

/-- Preservation for the coherent relation. -/
theorem preservation {σ : Sigma} {c : ConfE} {e : Expr} {s : State}
    {σ' : Sigma} {c' : ConfE} {e' : Expr} {s' : State}
    (hwt : WT σ e) (_hm : MatchU σ c s)
    (hstep : StepPM σ c e s σ' c' e' s') :
    WT σ' e' ∧ MatchU σ' c' s' :=
  ⟨stepPM_wt hstep hwt, stepPM_post hstep⟩

end Coherent
end LSys
