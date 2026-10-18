#!/usr/bin/env bash
# M1c: stage1 compiles hello.ls.
set -euo pipefail
trap 'echo "run-stage1 FAILED at line $LINENO"' ERR
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

./bootstrap/build.sh

# 1) interpreted stage1 (works on Windows and Linux)
./bootstrap/seed/seed --run bootstrap/src/main.ls \
  bootstrap/bls/tests/hello.ls bootstrap/build/hello_stage1
test -s bootstrap/build/hello_stage1
READELF_BIN="${READELF:-}"
if [ -z "$READELF_BIN" ]; then
  if command -v llvm-readelf >/dev/null 2>&1; then READELF_BIN=llvm-readelf; else READELF_BIN=readelf; fi
fi
"$READELF_BIN" -h bootstrap/build/hello_stage1 | grep -q 'EXEC'
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

# interpreted multi-character names stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_names.ls bootstrap/build/stage1_names_stage1
test -s bootstrap/build/stage1_names_stage1
echo "PASS interpreted names stage1 -> ELF"

# interpreted Unicode-name stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_unicode_names.ls bootstrap/build/stage1_unicode_names_stage1
test -s bootstrap/build/stage1_unicode_names_stage1
echo "PASS interpreted Unicode-name stage1 -> ELF"

# interpreted 256-byte identifier stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_long_name.ls bootstrap/build/stage1_long_name_stage1
test -s bootstrap/build/stage1_long_name_stage1
echo "PASS interpreted 256-byte identifier stage1 -> ELF"

# interpreted built-in I/O stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_io.ls bootstrap/build/stage1_io_stage1
test -s bootstrap/build/stage1_io_stage1
echo "PASS interpreted built-in I/O stage1 -> ELF"

# interpreted general Str stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/str.ls bootstrap/build/str_stage1
test -s bootstrap/build/str_stage1
echo "PASS interpreted Str stage1 -> ELF"

# interpreted Str I/O path
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_str_io.ls bootstrap/build/stage1_str_io_stage1
test -s bootstrap/build/stage1_str_io_stage1
echo "PASS interpreted Str I/O stage1 -> ELF"

# interpreted nested call arguments
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_nested_call.ls bootstrap/build/stage1_nested_call_stage1
test -s bootstrap/build/stage1_nested_call_stage1
echo "PASS interpreted nested-call stage1 -> ELF"

# interpreted control-flow stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_control.ls bootstrap/build/stage1_control_stage1
test -s bootstrap/build/stage1_control_stage1
echo "PASS interpreted control-flow stage1 -> ELF"

# interpreted nested-index stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/stage1_nested_index.ls bootstrap/build/stage1_nested_index_stage1
test -s bootstrap/build/stage1_nested_index_stage1
echo "PASS interpreted nested-index stage1 -> ELF"

# interpreted high data-offset (>1 MB) stage1
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/high_offset.ls bootstrap/build/high_offset_stage1
test -s bootstrap/build/high_offset_stage1
echo "PASS interpreted high-offset stage1 -> ELF"

# interpreted >16 MB data-offset stage1 (stage1/stage2 compile only)
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/big_offset.ls bootstrap/build/big_offset_stage1
test -s bootstrap/build/big_offset_stage1
echo "PASS interpreted big-offset stage1 -> ELF"

# interpreted logical && / || with nested slice indexes
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/logic_ops.ls bootstrap/build/logic_ops_stage1
test -s bootstrap/build/logic_ops_stage1
echo "PASS interpreted logic-ops stage1 -> ELF"

# interpreted nested break (break patch reuse)
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/break_nested.ls bootstrap/build/break_nested_stage1
test -s bootstrap/build/break_nested_stage1
echo "PASS interpreted nested-break stage1 -> ELF"

# interpreted division/modulo (single cqo/idiv)
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/bls/tests/divmod.ls bootstrap/build/divmod_stage1
test -s bootstrap/build/divmod_stage1
echo "PASS interpreted divmod stage1 -> ELF"

# interpreted self-compile: stage1 source -> stage2 ELF
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/src/names_stage.ls bootstrap/build/stage2_selfhost_interpreted
test -s bootstrap/build/stage2_selfhost_interpreted
echo "PASS interpreted stage1 self-compile -> stage2 ELF"

# deterministic interpreted stage1: two runs must be byte-identical
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/src/names_stage.ls bootstrap/build/stage2_interp_a
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
  bootstrap/src/names_stage.ls bootstrap/build/stage2_interp_b
cmp bootstrap/build/stage2_interp_a bootstrap/build/stage2_interp_b
echo "PASS interpreted stage1 determinism (stage2_a == stage2_b)"

# 3) compiled stage1 (Linux only)
if [ "$(uname -s)" = "Linux" ]; then
  set +e
  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_names.ls bootstrap/build/stage1_names_b > /tmp/names_compile.out 2>&1
  cnames_rc=$?
  set -e
  echo "stage1-names compile rc=$cnames_rc"
  cat /tmp/names_compile.out
  test "$cnames_rc" -eq 0
  set +e
  ./bootstrap/build/stage1_names_b
  names_rc=$?
  set -e
  test "$names_rc" -eq 177
  echo "PASS compiled names stage1 -> exit 177"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_unicode_names.ls bootstrap/build/stage1_unicode_names_b
  set +e
  ./bootstrap/build/stage1_unicode_names_b
  unames_rc=$?
  set -e
  test "$unames_rc" -eq 177
  echo "PASS compiled Unicode-name stage1 -> exit 177"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_long_name.ls bootstrap/build/stage1_long_name_b
  set +e
  ./bootstrap/build/stage1_long_name_b
  lname_rc=$?
  set -e
  test "$lname_rc" -eq 177
  echo "PASS compiled 256-byte identifier stage1 -> exit 177"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_io.ls bootstrap/build/stage1_io_b
  cp bootstrap/bls/tests/hello.ls bootstrap/build/io_in.txt
  ./bootstrap/build/stage1_io_b bootstrap/build/io_in.txt bootstrap/build/io_out.txt
  cmp bootstrap/build/io_in.txt bootstrap/build/io_out.txt
  echo "PASS compiled built-in I/O stage1 -> read/write via argv"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/str.ls bootstrap/build/str_b
  set +e
  str_out="$(./bootstrap/build/str_b)"
  str_rc=$?
  set -e
  test "$str_rc" -eq 10
  test "$str_out" = "你好, Str ✅"
  echo "PASS compiled Str stage1 -> exit 10"

  set +e
  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_str_io.ls bootstrap/build/stage1_str_io_b >/tmp/sio_compile.out 2>&1
  sio_crc=$?
  set -e
  cat /tmp/sio_compile.out
  test "$sio_crc" -eq 0
  set +e
  ./bootstrap/build/stage1_str_io_b
  sio_rc=$?
  echo "Str I/O rc=$sio_rc"
  set -e
  test "$sio_rc" -gt 0
  cmp bootstrap/bls/tests/hello.ls bootstrap/build/str_io_out.txt
  echo "PASS compiled Str I/O stage1 -> read/write via Str path"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_nested_call.ls bootstrap/build/stage1_nested_call_b
  set +e
  ./bootstrap/build/stage1_nested_call_b
  ncall_rc=$?
  set -e
  test "$ncall_rc" -eq 7
  echo "PASS compiled nested-call stage1 -> exit 7"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_control.ls bootstrap/build/stage1_control_b
  set +e
  ctl_out="$(./bootstrap/build/stage1_control_b)"
  ctl_rc=$?
  set -e
  test "$ctl_rc" -eq 14
  test "$ctl_out" = "ctl ok"
  echo "PASS compiled control-flow stage1 -> exit 14"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_nested_index.ls bootstrap/build/stage1_nested_index_b
  set +e
  ./bootstrap/build/stage1_nested_index_b
  nidx_rc=$?
  set -e
  test "$nidx_rc" -eq 177
  echo "PASS compiled nested-index stage1 -> exit 177"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/high_offset.ls bootstrap/build/high_offset_b
  set +e
  ./bootstrap/build/high_offset_b
  hoff_rc=$?
  set -e
  test "$hoff_rc" -eq 177
  echo "PASS compiled high-offset stage1 -> exit 177"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/big_offset.ls bootstrap/build/big_offset_b
  set +e
  ./bootstrap/build/big_offset_b
  bigoff_rc=$?
  set -e
  test "$bigoff_rc" -eq 177
  echo "PASS compiled big-offset stage1 -> exit 177"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/logic_ops.ls bootstrap/build/logic_ops_b
  set +e
  ./bootstrap/build/logic_ops_b
  logic_rc=$?
  set -e
  test "$logic_rc" -eq 202
  echo "PASS compiled logic-ops stage1 -> exit 202"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/break_nested.ls bootstrap/build/break_nested_b
  set +e
  ./bootstrap/build/break_nested_b
  brk_rc=$?
  set -e
  test "$brk_rc" -eq 103
  echo "PASS compiled nested-break stage1 -> exit 103"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/divmod.ls bootstrap/build/divmod_b
  set +e
  ./bootstrap/build/divmod_b
  div_rc=$?
  set -e
  test "$div_rc" -eq 132
  echo "PASS compiled divmod stage1 -> exit 132"

  # M1d-1b: compiled stage1 compiles itself, then stage2 compiles calc
  ./bootstrap/build/stage1-names bootstrap/src/names_stage.ls bootstrap/build/stage2_self
  test -s bootstrap/build/stage2_self
  ./bootstrap/build/stage2_self bootstrap/bls/tests/calc.ls bootstrap/build/calc_by_stage2
  set +e
  calc2_out="$(./bootstrap/build/calc_by_stage2)"
  calc2_rc=$?
  set -e
  test "$calc2_rc" -eq 14
  test "$calc2_out" = "calc ok"
  echo "PASS stage1 self-compile -> stage2 compiles calc (exit 14)"

  ./bootstrap/build/stage2_self bootstrap/bls/tests/high_offset.ls bootstrap/build/high_offset_by_stage2
  set +e
  ./bootstrap/build/high_offset_by_stage2
  ho2_rc=$?
  set -e
  test "$ho2_rc" -eq 177
  echo "PASS stage2 compiles high-offset -> exit 177"

  ./bootstrap/build/stage2_self bootstrap/bls/tests/big_offset.ls bootstrap/build/big_offset_by_stage2
  set +e
  ./bootstrap/build/big_offset_by_stage2
  bigoff2_rc=$?
  set -e
  test "$bigoff2_rc" -eq 177
  echo "PASS stage2 compiles big-offset -> exit 177"

  # >256 MiB data layout (31-bit metadata, RIP-relative disp32)
  ./bootstrap/build/stage1-names bootstrap/bls/tests/huge_offset.ls bootstrap/build/huge_offset_b
  set +e
  ./bootstrap/build/huge_offset_b
  huge_rc=$?
  set -e
  test "$huge_rc" -eq 177
  echo "PASS compiled huge-offset stage1 -> exit 177"

  ./bootstrap/build/stage2_self bootstrap/bls/tests/huge_offset.ls bootstrap/build/huge_offset_by_stage2
  set +e
  ./bootstrap/build/huge_offset_by_stage2
  huge2_rc=$?
  set -e
  test "$huge2_rc" -eq 177
  echo "PASS stage2 compiles huge-offset -> exit 177"

  # M1d-2: fixed point stage2 -> stage3
  ./bootstrap/build/stage2_self bootstrap/src/names_stage.ls bootstrap/build/stage3_self
  cmp bootstrap/build/stage2_self bootstrap/build/stage3_self
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum bootstrap/build/stage2_self bootstrap/build/stage3_self
  fi
  echo "PASS fixed point: stage2 == stage3"
else
  echo "SKIP compiled stage1 execution on $(uname -s)"
fi
