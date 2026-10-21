/-
  LSys/EnvExt.lean

  Environment extension lemmas used by route A: `let`/`borrow` require the
  bound variable to be fresh, so their environment updates are extensions.
-/

import LSys.EvalConf
import LSys.Env

namespace LSys

set_option linter.unusedVariables false

theorem EnvExtends.setEnv {env env' : EvalEnv} (h : LSys.EnvExtends env env')
    (x : Var) (v : RVal) :
    LSys.EnvExtends (LSys.setEnv env x v) (LSys.setEnv env' x v) := by
  intro y w hy
  cases Nat.decEq y x with
  | isTrue hxy =>
      cases hxy
      rw [LSys.setEnv_same] at hy
      rw [LSys.setEnv_same]
      exact hy
  | isFalse hxy =>
      rw [LSys.setEnv_other hxy] at hy
      rw [LSys.setEnv_other hxy]
      exact h y w hy

theorem EnvExtends.setEnv_self {env : EvalEnv} {x : Var} {v : RVal}
    (hfresh : env x = none) :
    LSys.EnvExtends env (LSys.setEnv env x v) := by
  intro y w hy
  cases Nat.decEq y x with
  | isTrue hxy =>
      cases hxy
      rw [hfresh] at hy
      cases hy
  | isFalse hxy =>
      rw [LSys.setEnv_other hxy]
      exact hy

end LSys
