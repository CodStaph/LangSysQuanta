#!/usr/bin/env bash
# ddc.sh — S3-4: dual-compiler seed DDC + self-compiled compiler differential.
#
# 05 §6.3.1/§6.3.2:
#   dual       build seed with two C compilers (gcc + clang; DDC_CC1/DDC_CC2
#              override) and require byte-identical compile-mode products
#              (hello smoke, stage1 = C-compiled-by-seed) and identical
#              interpretation products (seed --run C C). On a Linux host the
#              chain is extended natively (stage1 -> stage2 -> cmp).
#   self-diff  compile AND EXECUTE the whole compiled-test corpus with the
#              SELF-built compiler (bootstrap/build/stage2_self) and require
#              the same behavior (exit code + stdout) as the seed-built
#              reference (bootstrap/build/stage1-seed). Product bytes are NOT
#              compared: seed codegen and names_stage codegen legitimately
#              differ byte-wise (verified 2026-11-28: all 17 seed-compilable
#              corpus products differ from the interpreted ones). Runs on
#              Linux / QEMU guest only. Modes via DDC_SELF_DIFF_MODE (default
#              gate): gate - divergences must exactly match
#              bootstrap/ci/ddc-known-gaps.txt; enumerate - print the table
#              and always exit 0 (used to collect the baseline).
#
# Both modes print machine-readable PASS/LINES and sha256s.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

MODE="${1:-dual}"
CC1="${DDC_CC1:-clang}"
CC2="${DDC_CC2:-gcc}"
C_SRC="bootstrap/seed/seed.c"
SRC="bootstrap/src/names_stage.ls"
GAPS="bootstrap/ci/ddc-known-gaps.txt"
OUT=".temp/ddc"
GUEST_LINUX_TEST="bootstrap/bls/tests/hello.ls"

die() { echo "ddc: $*" >&2; exit 1; }

seed_build() { # cc out
  local cc="$1" out="$2"
  case "$(uname -s 2>/dev/null || echo unknown)" in
    *MINGW*|*MSYS*|*CYGWIN*|*Windows*)
      "$cc" -O2 -fno-builtin -D_CRT_SECURE_NO_WARNINGS "$C_SRC" -o "$out" ;;
    *)
      "$cc" -nostdlib -static -fno-pic -no-pie -fno-stack-protector -fno-builtin -O2 \
        "$C_SRC" -o "$out" ;;
  esac
}

smoke() { # seed_binary
  local out rc
  set +e
  out="$("$1" --run "$GUEST_LINUX_TEST")"
  rc=$?
  set -e
  [ "$rc" -eq 0 ] || die "smoke rc mismatch: $1 ($rc)"
  [ "$out" = "hello from L-Sys bootstrap" ] || die "smoke output mismatch: $1"
}

dual() {
  command -v "$CC1" >/dev/null 2>&1 || die "compiler 1 not found: $CC1 (set DDC_CC1)"
  command -v "$CC2" >/dev/null 2>&1 || die "compiler 2 not found: $CC2 (set DDC_CC2)"
  [ "$CC1" != "$CC2" ] || die "DDC needs two DIFFERENT compilers (both: $CC1)"
  mkdir -p "$OUT"
  echo "ddc: dual build  CC1=$CC1  CC2=$CC2"
  seed_build "$CC1" "$OUT/seed1" || die "seed build 1 failed ($CC1)"
  seed_build "$CC2" "$OUT/seed2" || die "seed build 2 failed ($CC2)"

  # 1) interpreter smoke on both seeds
  smoke "$OUT/seed1"
  smoke "$OUT/seed2"

  # 2) compile-mode products must be byte-identical between the two seeds
  "$OUT/seed1" "$GUEST_LINUX_TEST" -o "$OUT/hello1" || die "seed1 hello compile failed"
  "$OUT/seed2" "$GUEST_LINUX_TEST" -o "$OUT/hello2" || die "seed2 hello compile failed"
  cmp "$OUT/hello1" "$OUT/hello2" || die "DDC FAILED: hello products differ"
  echo "PASS ddc: hello products byte-identical across $CC1/$CC2"

  # 3) core: stage1 (names_stage compiled by each seed) must be byte-identical
  "$OUT/seed1" "$SRC" -o "$OUT/stage1a" || die "seed1 stage1 compile failed"
  "$OUT/seed2" "$SRC" -o "$OUT/stage1b" || die "seed2 stage1 compile failed"
  cmp "$OUT/stage1a" "$OUT/stage1b" || die "DDC FAILED: stage1 products differ (seed has compiler-divergent behavior/UB)"
  echo "PASS ddc: stage1 products byte-identical across $CC1/$CC2 (05 §6.3.1)"

  # 4) interpretation-mode self-compile through both seeds
  "$OUT/seed1" --run "$SRC" "$SRC" "$OUT/self1" || die "seed1 --run self-compile failed"
  "$OUT/seed2" --run "$SRC" "$SRC" "$OUT/self2" || die "seed2 --run self-compile failed"
  cmp "$OUT/self1" "$OUT/self2" || die "DDC FAILED: interpreted self-compile products differ"
  echo "PASS ddc: interpreted self-compile byte-identical across $CC1/$CC2 (05 §6.3.2)"

  # 5) native chain extension (Linux only)
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Linux*)
      "$OUT/stage1a" "$SRC" "$OUT/stage2a" || die "stage1a -> stage2a failed"
      "$OUT/stage1b" "$SRC" "$OUT/stage2b" || die "stage1b -> stage2b failed"
      cmp "$OUT/stage2a" "$OUT/stage2b" || die "DDC FAILED: native stage2 products differ"
      echo "PASS ddc: native stage2 byte-identical across $CC1/$CC2"
      cmp "$OUT/stage2a" "$OUT/self1" \
        || die "NOTE: native stage2 != interpreted self-compile (interpretation divergence)"
      echo "PASS ddc: native stage2 == interpreted self-compile (interpreter faithful)"
      sha256sum "$OUT/stage1a" "$OUT/stage2a" "$OUT/self1"
      ;;
    *)
      echo "ddc: native chain extension skipped on $(uname -s) (needs Linux execution)"
      sha256sum "$OUT/stage1a" "$OUT/self1"
      ;;
  esac
  echo "PASS ddc dual ($CC1 + $CC2)"
}

# Pairwise corpus: the union of the run-stage1.sh compiled half (behavior
# contracts there; here we compare self-built vs seed-built side by side).
CORPUS="stage1_names stage1_unicode_names stage1_long_name stage1_comptime_empty
slice_at stage1_val_param stage1_scope_shadow stage1_val_shadow
stage1_arena stage1_buffer stage1_buffer_surface stage1_buffer_try
stage1_buffer_index stage1_buffer_release stage1_buffer_region stage1_region_return
stage1_str_budget stage1_arena_stats stage1_arena_region stage1_arena_mark
stage1_arena_free stage1_alloc_fail stage1_arena_compact stage1_region_quota
stage1_io str stage1_str_io stage1_nested_call stage1_control
result_option result_err option_chain option_none option_u8 result_u8_err
option_str option_str_none result_str_ok result_str_err option_slice
option_slice_chain option_infer option_str_infer gen_enum gen_enum_fn
gen_enum_typed gen_enum_empty gen_fn gen_fn_str gen_fn_slice gen_enum_str
gen_enum_str_fn gen_enum_slice gen_multi gen_multi_where gen_struct
gen_struct_fields stage1_struct_value stage1_gen_struct_param stage1_gen_struct_new
stage1_trait_calls ref_int ref_str_slice ref_buffer ref_slice_index ref_str_write
ref_slice_write ref_values ref_fields ref_escape_ok ref_array ref_payload
effects contracts contract_requires contract_ensures struct_payload gen_op
gen_op_u8 gen_op_str gen_op_str_unicode gen_slice_cmp gen_slice_cmp_int
slice_concat slice_concat_int slice_concat_cap arena_reset stage1_trait_eq_ord
stage1_trait_bound stage1_nested_index high_offset big_offset logic_ops
break_nested divmod huge_offset"

self_diff() {
  [ "$(uname -s 2>/dev/null || echo unknown)" = "Linux" ] \
    || { echo "ddc: self-diff needs Linux (runs in the QEMU guest / CI), skipping on $(uname -s)"; exit 0; }
  local ref="bootstrap/build/stage1-seed"
  local self="bootstrap/build/stage2_self"
  local sdmode="${DDC_SELF_DIFF_MODE:-gate}"
  [ -x "$ref" ] || die "self-diff: $ref missing (seed-built reference)"
  [ -x "$self" ] || die "self-diff: $self missing (self-built compiler)"
  mkdir -p /tmp/ddc-selfdiff
  : > /tmp/ddc-selfdiff/divergent.txt
  local total=0
  local probes=""
  if ls bootstrap/bls/tests/ddc-probe/*.ls >/dev/null 2>&1; then
    for p in bootstrap/bls/tests/ddc-probe/*.ls; do probes="$probes $p"; done
  fi
  for entry in $CORPUS $probes; do
    local src="bootstrap/bls/tests/$entry.ls"
    [ -f "$src" ] || src="$entry"
    total=$((total + 1))
    local tag
    tag="$(basename "$src" .ls)"
    # reference side (seed-built compiler)
    local ra=""; local rca=0
    if "$ref" "$src" "/tmp/ddc-selfdiff/ref_$tag" >/tmp/ddc-selfdiff/ref_$tag.log 2>&1; then
      set +e; "/tmp/ddc-selfdiff/ref_$tag" >/tmp/ddc-selfdiff/ref_$tag.out 2>&1; rca=$?; set -e
      ra="ok"
    else
      rca=-1; ra="compile-fail"
    fi
    # subject side (self-built compiler)
    local rb=""; local rcb=0
    if "$self" "$src" "/tmp/ddc-selfdiff/self_$tag" >/tmp/ddc-selfdiff/self_$tag.log 2>&1; then
      set +e; "/tmp/ddc-selfdiff/self_$tag" >/tmp/ddc-selfdiff/self_$tag.out 2>&1; rcb=$?; set -e
      rb="ok"
    else
      rcb=-1; rb="compile-fail"
      printf 'self-diff:   self-compile error for %s: %s\n' "$tag" \
        "$(head -n 1 "/tmp/ddc-selfdiff/self_$tag.log" 2>/dev/null || echo '(no log)')"
    fi
    local status="same"
    if [ "$ra" != "$rb" ] || [ "$rca" != "$rcb" ]; then
      status="DIVERGENT ($ra/$rca vs $rb/$rcb)"
      echo "$tag" >> /tmp/ddc-selfdiff/divergent.txt
    elif ! cmp -s "/tmp/ddc-selfdiff/ref_$tag.out" "/tmp/ddc-selfdiff/self_$tag.out" 2>/dev/null; then
      status="DIVERGENT (stdout differs)"
      echo "$tag" >> /tmp/ddc-selfdiff/divergent.txt
    fi
    printf 'self-diff: %-28s ref=%-12s(%3s)  self=%-12s(%3s)  %s\n' \
      "$tag" "$ra" "$rca" "$rb" "$rcb" "$status"
  done
  local ndiv
  ndiv="$(wc -l < /tmp/ddc-selfdiff/divergent.txt | tr -d ' ')"
  echo "self-diff: $total programs, $ndiv divergent (mode=$sdmode)"
  if [ "$sdmode" = "enumerate" ]; then
    echo "self-diff: ENUMERATE mode - no gate (baseline collection)"
    exit 0
  fi
  # gate mode: divergences must exactly match the known-gaps list.
  # A gap entry is a non-comment, non-blank line. The trailing platform AIGC
  # watermark ("AI生成", auto-appended to agent-authored text files and kept
  # by policy) is NOT an entry; every read of $GAPS below filters it out.
  local expected=0
  if [ -f "$GAPS" ]; then
    expected="$(grep -c -v -e '^\s*#' -e '^\s*$' -e '^AI生成\s*$' "$GAPS" || true)"
  fi
  if [ "$ndiv" -ne "$expected" ]; then
    echo "self-diff: FAIL - $ndiv divergent, $expected expected (see $GAPS)" >&2
    echo "self-diff: observed:" >&2
    cat /tmp/ddc-selfdiff/divergent.txt >&2
    echo "self-diff: expected:" >&2
    grep -v -e '^\s*#' -e '^\s*$' -e '^AI生成\s*$' "$GAPS" || true
    exit 1
  fi
  # every observed divergence must be listed (exact set match)
  while IFS= read -r t; do
    [ -n "$t" ] || continue
    grep -qx "$t" "$GAPS" 2>/dev/null || {
      echo "self-diff: FAIL - divergence not in known-gaps: $t" >&2
      exit 1
    }
  done < /tmp/ddc-selfdiff/divergent.txt
  # every listed gap must still diverge (stale entries must be removed)
  grep -v -e '^\s*#' -e '^\s*$' -e '^AI生成\s*$' "$GAPS" 2>/dev/null | while IFS= read -r t; do
    [ -n "$t" ] || continue
    grep -qx "$t" /tmp/ddc-selfdiff/divergent.txt || {
      echo "self-diff: FAIL - stale known-gap (no longer diverges): $t" >&2
      exit 1
    }
  done
  echo "PASS self-diff: divergences match known-gaps exactly ($ndiv)"
}

case "$MODE" in
  dual) dual ;;
  self-diff) self_diff ;;
  *) die "usage: ddc.sh [dual|self-diff]" ;;
esac
