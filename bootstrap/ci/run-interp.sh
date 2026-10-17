#!/usr/bin/env bash
# B-LS interpreter tests (seed --run). Runs on Linux and Windows/MSYS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SEED="./bootstrap/seed/seed"
[ -x "$SEED" ] || SEED="./bootstrap/seed/seed.exe"

check() {
  file="$1"; want_rc="$2"; want_out="$3"
  set +e
  out="$("$SEED" --run "$file")"
  rc=$?
  set -e
  if [ "$rc" -ne "$want_rc" ]; then
    echo "FAIL $file: rc=$rc want=$want_rc" >&2
    exit 1
  fi
  if [ "$out" != "$want_out" ]; then
    echo "FAIL $file: out=[$out] want=[$want_out]" >&2
    exit 1
  fi
  echo "PASS $file (rc=$rc)"
}

check bootstrap/bls/tests/hello.ls   0 "hello from L-Sys bootstrap"
check bootstrap/bls/tests/calc.ls    14 "calc ok"
check bootstrap/bls/tests/funcs.ls   7  "funcs ok"
check bootstrap/bls/tests/arrays.ls  7  "arr ok"
check bootstrap/bls/tests/enums.ls   1  "enum ok"
check bootstrap/bls/tests/structs.ls 7  "struct ok"
check bootstrap/bls/tests/slices.ls  177 "slice ok"
check bootstrap/bls/tests/slice_params.ls 177 "sparam ok"
check bootstrap/bls/tests/ops.ls 12 "ops ok"
check bootstrap/bls/tests/match.ls 1 "green"
check bootstrap/bls/tests/payload.ls 42 "some"

set +e
argv_out="$("$SEED" --run bootstrap/bls/tests/argv.ls foo boo)"
argv_rc=$?
set -e
test "$argv_rc" -eq 0
test "$argv_out" = "argv ok"
echo "PASS argv.ls (rc=$argv_rc, args foo boo)"

rm -f bootstrap/build/copy.ls
check bootstrap/bls/tests/io.ls 0 "io ok"
cmp bootstrap/bls/tests/hello.ls bootstrap/build/copy.ls
echo "interp: all B-LS tests passed"
