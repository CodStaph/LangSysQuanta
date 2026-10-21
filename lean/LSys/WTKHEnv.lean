/-
  LSys/WTKHEnv.lean

  Typing transport along environment extensions (`WTKH.env_ext`).

  The `region` rule now carries the environment-independent region-safety
  premise `RegionSafeLam σ R e` (Λ-only over-approximation), so its
  transport case is just `WTKH.region (ihe hext) hsafe hno` — no
  `EnvExtends.trans` plumbing is needed any more.
-/

import LSys.WTKH
import LSys.EnvExt

namespace LSys

set_option linter.unusedVariables false

/-- `WTKH` is monotone in the environment. -/
theorem WTKH.env_ext {env : EvalEnv} :
    ∀ {heap : EvalHeap} {e : Expr} {σ σ' : Sigma} {A : List Bid},
      WTKH env heap e σ σ' A →
      ∀ {env' : EvalEnv}, EnvExtends env env' → WTKH env' heap e σ σ' A := by
  intro heap e σ σ' A h
  induction h with
  | val => intro env' _; exact WTKH.val
  | var hx => intro env' hext; exact WTKH.var (hext _ _ hx)
  | abort => intro env' _; exact WTKH.abort
  | op ha hb iha ihb =>
      intro env' hext
      exact WTKH.op (iha hext) (ihb hext)
  | letE ha hb iha ihb =>
      intro env' hext
      exact WTKH.letE (iha hext)
        (fun v => ihb v (EnvExtends.setEnv hext _ (ofVal v)))
  | move hp =>
      intro env' _; exact WTKH.move hp
  | read hp hm =>
      intro env' _; exact WTKH.read hp hm
  | write he hw ihe =>
      intro env' hext
      exact WTKH.write (ihe hext) hw
  | seq ha hb iha ihb =>
      intro env' hext
      exact WTKH.seq (iha hext) (ihb hext)
  | region he hsafe hno ihe =>
      intro env' hext
      exact WTKH.region (ihe hext) hsafe hno
  | alloc he hcap ihe =>
      intro env' hext
      exact WTKH.alloc (ihe hext) hcap
  | freeze hm hl =>
      intro env' _; exact WTKH.freeze hm hl
  | recover he ihe =>
      intro env' hext
      exact WTKH.recover (ihe hext)
  | borrow hm he ihe =>
      intro env' hext
      exact WTKH.borrow hm
        (ihe (EnvExtends.setEnv hext _ (RVal.refH 0)))
  | drop hm =>
      intro env' _; exact WTKH.drop hm
  | call ha hcap hb iha ihb =>
      intro env' hext
      exact WTKH.call (iha hext) hcap (ihb hext)
  | ret he ihe =>
      intro env' hext
      exact WTKH.ret (ihe hext)
  | spawn he hcap ihe =>
      intro env' hext
      exact WTKH.spawn (ihe hext) hcap
  | atomic he hm ihe =>
      intro env' hext
      exact WTKH.atomic (ihe hext) hm
  | unsafeE he ihe =>
      intro env' hext
      exact WTKH.unsafeE (ihe hext)
  | deref hp => intro env' _; exact WTKH.deref hp

end LSys
