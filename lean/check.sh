#!/usr/bin/env bash
# lean/check.sh — machine-check the Lean core (L-Term).
#
# Requires Lean 4.6.0.  Resolution order:
#   1. $LEAN
#   2. `lean` on PATH (e.g. via elan)
#   3. .tools/lean/*/bin/lean (local download, gitignored)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

LEAN="${LEAN:-}"
if [ -z "$LEAN" ]; then
  LEAN="$(command -v lean || true)"
fi
if [ -z "$LEAN" ]; then
  for c in "$ROOT"/.tools/lean/*/bin/lean "$ROOT"/.tools/lean/*/bin/lean.exe; do
    if [ -x "$c" ]; then
      LEAN="$c"
      break
    fi
  done
fi
if [ -z "$LEAN" ] || [ ! -x "$LEAN" ]; then
  echo "lean/check: Lean 4.6 not found; set LEAN=/path/to/lean" >&2
  exit 2
fi

# `sorry` compiles with a warning; treat it as a failure explicitly.
if grep -nE '\b(sorry|admit)\b' lean/LSys/*.lean; then
  echo "lean/check: FAIL: found sorry/admit" >&2
  exit 1
fi

mkdir -p .temp
# Build the L3 modules in dependency order.
for m in Term StepEval State Effect LamEff Runtime EvalConf Env EnvExt EffHPath EffHC EffHCounterexample EvalEff EffHMeasure EffHCK LamStep StepC Adequacy WTK Progress Block TypedStep Holders Unified Preservation PreservationCounterexample WTPreservation Coherent WTPlugCounterexample WTyH WTyHCtx WTyHStar LetHandle PlaceWF StepBridge WTKH EffHCK RedexK WTKHEnv WTKHPreservation FreeVars EffHCEnv CoherentH CoherentK Path T4a T4aSafe; do
  LEAN_PATH=lean "$LEAN" -o "lean/LSys/$m.olean" "lean/LSys/$m.lean"
done
LEAN_PATH=lean "$LEAN" lean/verify_axioms.lean | tee .temp/lean-axioms.txt

if grep -q 'sorryAx' .temp/lean-axioms.txt; then
  echo "lean/check: FAIL: a theorem depends on sorryAx" >&2
  exit 1
fi

echo "PASS lean: L3 + T4a foundation (steps 1-6; no sorry, no sorryAx)"
