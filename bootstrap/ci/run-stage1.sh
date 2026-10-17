#!/usr/bin/env bash
# M1c: stage1 compiles hello.ls.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

./bootstrap/build.sh

# 1) interpreted stage1 (works on Windows and Linux)
./bootstrap/seed/seed --run bootstrap/src/main.ls \
  bootstrap/bls/tests/hello.ls bootstrap/build/hello_stage1
test -s bootstrap/build/hello_stage1
"${READELF:-llvm-readelf}" -h bootstrap/build/hello_stage1 | grep -q 'EXEC'
echo "PASS interpreted stage1 -> hello ELF"

# 2) interpreted arith stage1
./bootstrap/seed/seed --run bootstrap/src/arith.ls   bootstrap/bls/tests/arith.ls bootstrap/build/arith_stage1
test -s bootstrap/build/arith_stage1
echo "PASS interpreted arith stage1 -> ELF"

# 3) compiled stage1 (Linux only)
if [ "$(uname -s)" = "Linux" ]; then
  ./bootstrap/build/stage1 bootstrap/bls/tests/hello.ls bootstrap/build/hello_stage1b
  out="$(./bootstrap/build/hello_stage1b)"
  test "$out" = "hello from L-Sys bootstrap"
  echo "PASS compiled stage1 -> hello runs"

  ./bootstrap/build/stage1-arith bootstrap/bls/tests/arith.ls bootstrap/build/arith_stage1b
  set +e
  ./bootstrap/build/arith_stage1b
  arith_rc=$?
  set -e
  test "$arith_rc" -eq 12
  echo "PASS compiled arith stage1 -> exit 12"
else
  echo "SKIP compiled stage1 execution on $(uname -s)"
fi
