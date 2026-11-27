#!/usr/bin/env bash
# assemble.sh - regenerate src/names_stage.ls from src/modules/*.ls (S3-2).
#
# The stage1 compiler is edited as modules (numeric filename prefixes fix the
# concatenation order); src/names_stage.ls is the committed generated artifact
# that every downstream consumer (build.sh, CI, the EBNF syntax gate and the
# self-host chain) keeps reading. After editing any module, run this script
# and commit the regenerated names_stage.ls together with the module change -
# build.sh re-verifies the concatenation with cmp on every invocation.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"

cat "$ROOT"/modules/*.ls > "$ROOT/names_stage.ls"
n="$(ls "$ROOT"/modules/*.ls | wc -l | tr -d ' ')"
echo "assembled: $ROOT/names_stage.ls ($n modules, byte-exact concatenation)"
