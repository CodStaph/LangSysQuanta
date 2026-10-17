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

# interpreted calc stage1
./bootstrap/seed/seed --run bootstrap/src/calc.ls   bootstrap/bls/tests/calc.ls bootstrap/build/calc_stage1
test -s bootstrap/build/calc_stage1
echo "PASS interpreted calc stage1 -> ELF"

# interpreted funcs stage1
./bootstrap/seed/seed --run bootstrap/src/funcs.ls   bootstrap/bls/tests/funcs2.ls bootstrap/build/funcs2_stage1
test -s bootstrap/build/funcs2_stage1
echo "PASS interpreted funcs stage1 -> ELF"

# interpreted slice stage1
./bootstrap/seed/seed --run bootstrap/src/slice_stage.ls \
  bootstrap/bls/tests/stage1_slice.ls bootstrap/build/stage1_slice_stage1
test -s bootstrap/build/stage1_slice_stage1
echo "PASS interpreted slice stage1 -> ELF"

# interpreted struct/enum stage1
./bootstrap/seed/seed --run bootstrap/src/struct_stage.ls \
  bootstrap/bls/tests/stage1_struct_enum.ls bootstrap/build/stage1_struct_enum_stage1
test -s bootstrap/build/stage1_struct_enum_stage1
echo "PASS interpreted struct/enum stage1 -> ELF"

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

  ./bootstrap/build/stage1-calc bootstrap/bls/tests/calc.ls bootstrap/build/calc_stage1b
  set +e
  calc_out="$(./bootstrap/build/calc_stage1b)"
  calc_rc=$?
  set -e
  test "$calc_rc" -eq 14
  test "$calc_out" = "calc ok"
  echo "PASS compiled calc stage1 -> exit 14"

  ./bootstrap/build/stage1-funcs bootstrap/bls/tests/funcs2.ls bootstrap/build/funcs2b
  set +e
  ./bootstrap/build/funcs2b
  funcs2_rc=$?
  set -e
  test "$funcs2_rc" -eq 3
  echo "PASS compiled funcs stage1 -> exit 3"

  ./bootstrap/build/stage1-slice bootstrap/bls/tests/stage1_slice.ls bootstrap/build/stage1_slice_b
  set +e
  ./bootstrap/build/stage1_slice_b
  slice_rc=$?
  set -e
  test "$slice_rc" -eq 177
  echo "PASS compiled slice stage1 -> exit 177"

  ./bootstrap/build/stage1-struct bootstrap/bls/tests/stage1_struct_enum.ls bootstrap/build/stage1_struct_enum_b
  set +e
  ./bootstrap/build/stage1_struct_enum_b
  struct_rc=$?
  set -e
  test "$struct_rc" -eq 177
  echo "PASS compiled struct/enum stage1 -> exit 177"
else
  echo "SKIP compiled stage1 execution on $(uname -s)"
fi
