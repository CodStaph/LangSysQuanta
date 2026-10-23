# M1c: stage1 compiles hello.ls.
set -euo pipefail
trap 'if [ -o errexit ]; then echo "run-stage1 FAILED at line $LINENO"; fi' ERR
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

# B-LS B2-lite: empty region block is accepted and compiles to no extra code.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_region_empty.ls bootstrap/build/stage1_region_empty
test -s bootstrap/build/stage1_region_empty
echo "PASS interpreted empty region block -> ELF"

# B-LS B2: non-empty region blocks are accepted as lexical groupings.
for t in stage1_region_let stage1_region_body; do
  ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
    bootstrap/bls/tests/$t.ls bootstrap/build/${t}_stage1
done
echo "PASS interpreted non-empty region blocks -> ELF"

# B-LS B2: val parameter mode is accepted as a by-value binding.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_val_param.ls bootstrap/build/stage1_val_param_stage1
test -s bootstrap/build/stage1_val_param_stage1
echo "PASS interpreted val parameter -> ELF"

# B-LS B2-2: lexical shadowing and val shadowing by let.
for t in stage1_scope_shadow stage1_val_shadow; do
  ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/$t.ls bootstrap/build/${t}_stage1
  test -s bootstrap/build/${t}_stage1
done
echo "PASS interpreted lexical scope -> ELF"

# B-LS B3-1: runtime arena metadata / allocation.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_arena.ls bootstrap/build/stage1_arena_stage1
test -s bootstrap/build/stage1_arena_stage1
echo "PASS interpreted arena -> ELF"

# B-LS B3-2: Buffer[Int] runtime layout.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_buffer.ls bootstrap/build/stage1_buffer_stage1
test -s bootstrap/build/stage1_buffer_stage1
echo "PASS interpreted buffer -> ELF"

# B-LS B3-2b: Buffer[Int] surface syntax.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_buffer_surface.ls bootstrap/build/stage1_buffer_surface_stage1
test -s bootstrap/build/stage1_buffer_surface_stage1
echo "PASS interpreted buffer surface -> ELF"

# B-LS B3-3: Buffer.try_new -> Result[Buffer[Int], Int], including arena failure.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_buffer_try.ls bootstrap/build/stage1_buffer_try_stage1
test -s bootstrap/build/stage1_buffer_try_stage1
echo "PASS interpreted buffer try_new -> ELF"

# B-LS B3-4a: Buffer[Int] read indexing (out-of-range -> -1).
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_buffer_index.ls bootstrap/build/stage1_buffer_index_stage1
test -s bootstrap/build/stage1_buffer_index_stage1
echo "PASS interpreted buffer index -> ELF"

# B-LS B3-4b: Buffer.release / drop b + LIFO arena rewind.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_buffer_release.ls bootstrap/build/stage1_buffer_release_stage1
test -s bootstrap/build/stage1_buffer_release_stage1
echo "PASS interpreted buffer release -> ELF"

# B-LS B2: duplicate active region names must be rejected.
if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/reject/bls_region_dup.ls bootstrap/build/reject_bls_region_dup >/tmp/reject_bls_region_dup.log 2>&1; then
  echo "B-LS REGION-DUP FAILED: duplicate region compiled"
  exit 1
fi
grep -q 'duplicate active region name' /tmp/reject_bls_region_dup.log
echo "PASS B-LS duplicate region diagnostic"

# B2-2: out-of-scope use and val assignment are rejected.
if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/reject/bls_scope_escape.ls bootstrap/build/reject_bls_scope_escape >/tmp/reject_bls_scope_escape.log 2>&1; then
  echo "B-LS SCOPE FAILED: out-of-scope variable compiled"
  exit 1
fi
if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/reject/bls_val_assign.ls bootstrap/build/reject_bls_val_assign >/tmp/reject_bls_val_assign.log 2>&1; then
  echo "B-LS VAL FAILED: val assignment compiled"
  exit 1
fi
grep -q 'val binding is immutable' /tmp/reject_bls_val_assign.log
echo "PASS B-LS lexical scope and val diagnostics"

# B-LS B2-lite: empty comptime block is accepted and compiles to no extra code.
./bootstrap/seed/seed --run bootstrap/src/names_stage.ls   bootstrap/bls/tests/stage1_comptime_empty.ls bootstrap/build/stage1_comptime_empty
test -s bootstrap/build/stage1_comptime_empty
echo "PASS interpreted empty comptime block -> ELF"
# interpreted Stage 2: Result/Option + ?
for t in result_option result_err option_chain option_none option_u8 result_u8_err option_str option_str_none result_str_ok result_str_err option_slice option_slice_chain option_infer option_str_infer gen_enum gen_enum_fn gen_enum_typed gen_enum_empty gen_fn gen_fn_str gen_fn_slice gen_enum_str gen_enum_str_fn gen_enum_slice gen_op gen_op_u8 gen_op_str gen_op_str_unicode gen_slice_cmp gen_slice_cmp_int slice_concat slice_concat_int slice_concat_cap arena_reset; do
  ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls \
    bootstrap/bls/tests/$t.ls bootstrap/build/${t}_stage1
  test -s bootstrap/build/${t}_stage1
done
echo "PASS interpreted Result/Option/? stage1 -> ELF"

# Stage 2 negative cases: compilation must fail.
for t in qmark_mismatch none_no_type gen_enum_payload gen_op_slice; do
  if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls       bootstrap/bls/tests/reject/$t.ls bootstrap/build/reject_$t >/tmp/reject_$t.log 2>&1; then
    echo "REJECT FAILED: $t compiled"
    exit 1
  fi
done
# B-LS B1: recognized-but-unimplemented Stage 2 syntax must fail with a
# stable E-LS-UNSUPPORTED diagnostic instead of a misleading parse error.
for t in bls_buffer bls_buffer_ret bls_buffer_field bls_buffer_expr bls_buffer_try bls_buffer_index_write bls_buffer_drop_int bls_slice_buffer bls_buffer_array bls_enum_multi bls_ref bls_eff bls_requires bls_ensures bls_comptime bls_generic_multi; do
  if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls       bootstrap/bls/tests/reject/$t.ls bootstrap/build/reject_$t >/tmp/reject_$t.log 2>&1; then
    echo "B-LS UNSUPPORTED FAILED: $t compiled"
    exit 1
  fi
  if ! grep -q 'E-LS-UNSUPPORTED' /tmp/reject_$t.log; then
    echo "B-LS UNSUPPORTED FAILED: $t missing diagnostic"
    cat /tmp/reject_$t.log
    exit 1
  fi
done
if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/reject/bls_dup_fn.ls bootstrap/build/reject_bls_dup_fn >/tmp/reject_bls_dup_fn.log 2>&1; then
  echo "B-LS DUP FAILED: duplicate function compiled"
  exit 1
fi
grep -q 'E-LS-DUP' /tmp/reject_bls_dup_fn.log
echo "PASS B-LS duplicate function diagnostic"

if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/reject/bls_main_params.ls bootstrap/build/reject_bls_main_params >/tmp/reject_bls_main_params.log 2>&1; then
  echo "B-LS MAIN FAILED: main with parameters compiled"
  exit 1
fi
grep -q 'E-LS-MAIN' /tmp/reject_bls_main_params.log
echo "PASS B-LS main signature diagnostic"

if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/reject/bls_main_ret.ls bootstrap/build/reject_bls_main_ret >/tmp/reject_bls_main_ret.log 2>&1; then
  echo "B-LS MAIN-RET FAILED: non-Int main compiled"
  exit 1
fi
grep -q 'E-LS-MAIN' /tmp/reject_bls_main_ret.log
echo "PASS B-LS main return diagnostic"

if ./bootstrap/seed/seed --run bootstrap/src/names_stage.ls     bootstrap/bls/tests/reject/bls_arity.ls bootstrap/build/reject_bls_arity >/tmp/reject_bls_arity.log 2>&1; then
  echo "B-LS ARITY FAILED: wrong argument count compiled"
  exit 1
fi
grep -q 'E-LS-ARITY' /tmp/reject_bls_arity.log
echo "PASS B-LS call arity diagnostic"

echo "PASS B-LS unsupported syntax diagnostics"

echo "PASS Stage 2 negative cases rejected"

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

  # B0.3a-2: slice_at must be compiled by stage1 and execute correctly.
  ./bootstrap/build/stage1-names bootstrap/bls/tests/slice_at.ls bootstrap/build/slice_at_b
  set +e
  ./bootstrap/build/slice_at_b
  slice_at_rc=$?
  set -e
  test "$slice_at_rc" -eq 88
  echo "PASS compiled slice_at stage1 -> exit 88"

  # B2: compiled val parameter mode.
  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_val_param.ls bootstrap/build/stage1_val_param_b
  set +e
  ./bootstrap/build/stage1_val_param_b
  val_rc=$?
  set -e
  test "$val_rc" -eq 7
  echo "PASS compiled val parameter stage1 -> exit 7"

  for t in stage1_scope_shadow stage1_val_shadow; do
    ./bootstrap/build/stage1-names bootstrap/bls/tests/$t.ls bootstrap/build/${t}_b
    set +e
    ./bootstrap/build/${t}_b
    t_rc=$?
    set -e
    if [ "$t" = "stage1_scope_shadow" ]; then want=7; else want=3; fi
    test "$t_rc" -eq "$want"
    echo "PASS compiled $t stage1 -> exit $want"
  done

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_arena.ls bootstrap/build/stage1_arena_b
  set +e
  ./bootstrap/build/stage1_arena_b
  arena_rc=$?
  set -e
  test "$arena_rc" -eq 7
  echo "PASS compiled arena stage1 -> exit 7"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_buffer.ls bootstrap/build/stage1_buffer_b
  set +e
  ./bootstrap/build/stage1_buffer_b
  buf_rc=$?
  set -e
  test "$buf_rc" -eq 7
  echo "PASS compiled buffer stage1 -> exit 7"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_buffer_surface.ls bootstrap/build/stage1_buffer_surface_b
  set +e
  ./bootstrap/build/stage1_buffer_surface_b
  bsurf_rc=$?
  set -e
  test "$bsurf_rc" -eq 7
  echo "PASS compiled buffer surface stage1 -> exit 7"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_buffer_try.ls bootstrap/build/stage1_buffer_try_b
  set +e
  ./bootstrap/build/stage1_buffer_try_b
  btry_rc=$?
  set -e
  test "$btry_rc" -eq 7
  echo "PASS compiled buffer try_new stage1 -> exit 7"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_buffer_index.ls bootstrap/build/stage1_buffer_index_b
  set +e
  ./bootstrap/build/stage1_buffer_index_b
  bidx_rc=$?
  set -e
  test "$bidx_rc" -eq 7
  echo "PASS compiled buffer index stage1 -> exit 7"

  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_buffer_release.ls bootstrap/build/stage1_buffer_release_b
  set +e
  ./bootstrap/build/stage1_buffer_release_b
  brel_rc=$?
  set -e
  test "$brel_rc" -eq 7
  echo "PASS compiled buffer release stage1 -> exit 7"

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

  # B-LS B2-lite: compiled stage1 must also accept an empty comptime block.
  # The interpreted path is checked above ("empty comptime block"); this is the
  # compiled-stage1 half of the same assertion. main returns 0, so exit code 0.
  ./bootstrap/build/stage1-names bootstrap/bls/tests/stage1_comptime_empty.ls bootstrap/build/stage1_comptime_empty_b
  set +e
  ./bootstrap/build/stage1_comptime_empty_b
  ct_rc=$?
  set -e
  test "$ct_rc" -eq 0
  echo "PASS compiled empty comptime block -> exit 0"

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


  # Stage 2: Result/Option + ?
  for t in result_option result_err option_chain option_none option_u8 result_u8_err option_str option_str_none result_str_ok result_str_err option_slice option_slice_chain option_infer option_str_infer gen_enum gen_enum_fn gen_enum_typed gen_enum_empty gen_fn gen_fn_str gen_fn_slice gen_enum_str gen_enum_str_fn gen_enum_slice gen_op gen_op_u8 gen_op_str gen_op_str_unicode gen_slice_cmp gen_slice_cmp_int slice_concat slice_concat_int slice_concat_cap arena_reset; do
    ./bootstrap/build/stage1-names bootstrap/bls/tests/$t.ls bootstrap/build/${t}_b
    set +e
    ./bootstrap/build/${t}_b
    t_rc=$?
    set -e
    case $t in
      result_option) t_expect=13 ;;
      result_err) t_expect=7 ;;
      option_chain) t_expect=6 ;;
      option_none) t_expect=9 ;;
      option_u8) t_expect=200 ;;
      result_u8_err) t_expect=5 ;;
      option_str) t_expect=3 ;;
      option_str_none) t_expect=9 ;;
      result_str_ok) t_expect=2 ;;
      result_str_err) t_expect=207 ;;
      option_slice) t_expect=10 ;;
      option_slice_chain) t_expect=10 ;;
      option_infer) t_expect=1 ;;
      option_str_infer) t_expect=2 ;;
      gen_enum) t_expect=1 ;;
      gen_enum_fn) t_expect=7 ;;
      gen_enum_typed) t_expect=7 ;;
      gen_enum_empty) t_expect=9 ;;
      gen_fn) t_expect=5 ;;
      gen_fn_str) t_expect=2 ;;
      gen_fn_slice) t_expect=10 ;;
      gen_enum_str) t_expect=2 ;;
      gen_enum_str_fn) t_expect=2 ;;
      gen_enum_slice) t_expect=10 ;;
      gen_op) t_expect=7 ;;
      gen_op_u8) t_expect=4 ;;
      gen_op_str) t_expect=2 ;;
      gen_op_str_unicode) t_expect=2 ;;
      gen_slice_cmp) t_expect=5 ;;
      gen_slice_cmp_int) t_expect=6 ;;
      slice_concat) t_expect=15 ;;
      slice_concat_int) t_expect=110 ;;
      slice_concat_cap) t_expect=71 ;;
      arena_reset) t_expect=2 ;;
      *) t_expect=0 ;;
    esac
    test "$t_rc" -eq "$t_expect"
    echo "PASS compiled $t -> exit $t_rc"
  done

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
