/-
  LSys/WTKHEnv.lean

  Typing transport along environment extensions (`WTKH.env_ext`).

  The `region` rule carries the environment-independent region-safety premise
  `RegionSafeLam σ R e` (Λ-only over-approximation), so its transport case is
  just the constructor application — no `EnvExtends.trans` plumbing.
-/

import LSys.WTKH
import LSys.EnvExt

namespace LSys

set_option linter.unusedVariables false

/-- `WTKH` is monotone in the environment. -/
theorem WTKH.env_ext {env : EvalEnv} :
    ∀ {heap : EvalHeap} {e : Expr} {σ : Sigma} {o : Outcome},
      WTKH env heap e σ o →
      ∀ {env' : EvalEnv}, EnvExtends env env' → WTKH env' heap e σ o := by
  intro heap e σ o h
  induction h with
  | val => intro env' _; exact WTKH.val
  | var hx => intro env' hext; exact WTKH.var (hext _ _ hx)
  | abort => intro env' _; exact WTKH.abort
  | opOk ha hb iha ihb =>
      intro env' hext
      exact WTKH.opOk (iha hext) (ihb hext)
  | opAborts ha iha =>
      intro env' hext
      exact WTKH.opAborts (iha hext)
  | letOk ha hb iha ihb =>
      intro env' hext
      exact WTKH.letOk (iha hext)
        (fun v => ihb v (EnvExtends.setEnv hext _ (ofVal v)))
  | letAborts ha iha =>
      intro env' hext
      exact WTKH.letAborts (iha hext)
  | move hp => intro env' _; exact WTKH.move hp
  | read hp hm => intro env' _; exact WTKH.read hp hm
  | writeOk he hw ihe =>
      intro env' hext
      exact WTKH.writeOk (ihe hext) hw
  | writeAborts he ihe =>
      intro env' hext
      exact WTKH.writeAborts (ihe hext)
  | seqOk ha hb iha ihb =>
      intro env' hext
      exact WTKH.seqOk (iha hext) (ihb hext)
  | seqAborts ha iha =>
      intro env' hext
      exact WTKH.seqAborts (iha hext)
  | regionOk he hsafe hno ihe =>
      intro env' hext
      exact WTKH.regionOk (ihe hext) hsafe hno
  | regionAborts he hsafe ihe =>
      intro env' hext
      exact WTKH.regionAborts (ihe hext) hsafe
  | allocOk he hcap ihe =>
      intro env' hext
      exact WTKH.allocOk (ihe hext) hcap
  | allocAborts he ihe =>
      intro env' hext
      exact WTKH.allocAborts (ihe hext)
  | freeze hm hl => intro env' _; exact WTKH.freeze hm hl
  | recoverOk he ihe =>
      intro env' hext
      exact WTKH.recoverOk (ihe hext)
  | recoverAborts he ihe =>
      intro env' hext
      exact WTKH.recoverAborts (ihe hext)
  | borrow hm he ihe =>
      intro env' hext
      exact WTKH.borrow hm (ihe (EnvExtends.setEnv hext _ (RVal.refH 0)))
  | drop hm => intro env' _; exact WTKH.drop hm
  | callOk ha hcap hb iha ihb =>
      intro env' hext
      exact WTKH.callOk (iha hext) hcap (ihb hext)
  | callAborts ha iha =>
      intro env' hext
      exact WTKH.callAborts (iha hext)
  | ret he ihe =>
      intro env' hext
      exact WTKH.ret (ihe hext)
  | spawnOk he hcap ihe =>
      intro env' hext
      exact WTKH.spawnOk (ihe hext) hcap
  | spawnAborts he ihe =>
      intro env' hext
      exact WTKH.spawnAborts (ihe hext)
  | atomicOk he hm ihe =>
      intro env' hext
      exact WTKH.atomicOk (ihe hext) hm
  | atomicAborts he ihe =>
      intro env' hext
      exact WTKH.atomicAborts (ihe hext)
  | unsafeE he ihe =>
      intro env' hext
      exact WTKH.unsafeE (ihe hext)
  | deref hp => intro env' _; exact WTKH.deref hp

end LSys
