#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-clang}"
mkdir -p "$ROOT/build"

# S3-2 module split: the stage1 compiler source is assembled from
# src/modules/*.ls (concatenation order = numeric filename prefixes) and
# src/names_stage.ls is the committed generated artifact. The cmp below is
# the anti-drift machine assertion: editing a module without re-running
# bootstrap/src/assemble.sh fails the build here instead of silently
# shipping a stale compiler source.
if [ -d "$ROOT/src/modules" ]; then
  asm_tmp="$(mktemp)"
  cat "$ROOT"/src/modules/*.ls > "$asm_tmp"
  if ! cmp -s "$asm_tmp" "$ROOT/src/names_stage.ls"; then
    rm -f "$asm_tmp"
    echo "build.sh: src/names_stage.ls is out of sync with src/modules/*.ls" >&2
    echo "build.sh: run bootstrap/src/assemble.sh and commit the regenerated artifact" >&2
    exit 4
  fi
  rm -f "$asm_tmp"
fi

host="$(uname -s 2>/dev/null || echo unknown)"
case "$host" in
  *MINGW*|*MSYS*|*CYGWIN*|*Windows*)
    # Windows is a development host only (05 §0.1): the emitted binaries are
    # Linux ELF executables and cannot run here, so the selfhost main path
    # below is not reachable on this host. The seed cross-compile path stays;
    # execution verification runs via bootstrap/ci/run-qemu.sh.
    "$CC" -O2 -fno-builtin -D_CRT_SECURE_NO_WARNINGS \
      "$ROOT/seed/seed.c" -o "$ROOT/seed/seed.exe"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/hello.ls" -o "$ROOT/build/hello"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/unicode.ls" -o "$ROOT/build/unicode"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/str.ls" -o "$ROOT/build/str"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/calc.ls" -o "$ROOT/build/calc"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/funcs.ls" -o "$ROOT/build/funcs"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/arrays.ls" -o "$ROOT/build/arrays"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/enums.ls" -o "$ROOT/build/enums"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/structs.ls" -o "$ROOT/build/structs"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/slices.ls" -o "$ROOT/build/slices"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/io.ls" -o "$ROOT/build/io"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/slice_params.ls" -o "$ROOT/build/slice_params"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/ops.ls" -o "$ROOT/build/ops"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/match.ls" -o "$ROOT/build/match"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/payload.ls" -o "$ROOT/build/payload"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/argv.ls" -o "$ROOT/build/argv"
    "$ROOT/seed/seed.exe" "$ROOT/bls/tests/dynpath.ls" -o "$ROOT/build/dynpath"
    "$ROOT/seed/seed.exe" "$ROOT/src/main.ls" -o "$ROOT/build/stage1"
    "$ROOT/seed/seed.exe" "$ROOT/src/arith.ls" -o "$ROOT/build/stage1-arith"
    "$ROOT/seed/seed.exe" "$ROOT/src/calc.ls" -o "$ROOT/build/stage1-calc"
    "$ROOT/seed/seed.exe" "$ROOT/src/funcs.ls" -o "$ROOT/build/stage1-funcs"
    "$ROOT/seed/seed.exe" "$ROOT/src/slice_stage.ls" -o "$ROOT/build/stage1-slice"
    "$ROOT/seed/seed.exe" "$ROOT/src/struct_stage.ls" -o "$ROOT/build/stage1-struct"
    "$ROOT/seed/seed.exe" "$ROOT/src/names_stage.ls" -o "$ROOT/build/stage1-names"
    echo "built: $ROOT/build/hello (ELF64 x86_64; not executed on Windows)"
    if command -v llvm-readelf >/dev/null 2>&1; then
      llvm-readelf -h "$ROOT/build/hello" | sed -n '1,16p'
    fi
    ;;
  Linux*)
    # S3-1 deseeding: pick the compiler that produces every artifact below.
    #   main path   : build/stage2_self exists -> everything is compiled with
    #                 it. The seed and the C compiler are OUT of the build.
    #   cold start  : no build/stage2_self (fresh checkout, audit,
    #                 reproduction) -> the classic chain
    #                 seed -> stage1-names -> stage2_self pulls the selfhost
    #                 compiler up exactly once; every artifact is then
    #                 compiled with stage2_self only.
    # FORCE_SEED_CHAIN=1 explicitly re-runs the cold-start chain for audits.
    if [ -x "$ROOT/build/stage2_self" ] && [ "${FORCE_SEED_CHAIN:-0}" != "1" ]; then
      SELFHOST="$ROOT/build/stage2_self"
      echo "selfhost: main path - compiler = build/stage2_self (seed out of the build)"
    else
      # SKIP_SEED_CC=1 reuses an already cross-compiled freestanding seed
      # instead of invoking the C compiler. Used by bootstrap/ci/run-qemu.sh,
      # where the seed is built on the host and there is no compiler inside
      # the guest.
      if [ "${SKIP_SEED_CC:-0}" = "1" ]; then
        if [ ! -x "$ROOT/seed/seed" ]; then
          echo "SKIP_SEED_CC=1 but prebuilt seed is missing: $ROOT/seed/seed" >&2
          exit 3
        fi
        echo "seed: using prebuilt freestanding ELF (SKIP_SEED_CC=1)"
      else
        "$CC" -nostdlib -static -fno-pic -no-pie -fno-stack-protector -fno-builtin -O2 \
          "$ROOT/seed/seed.c" -o "$ROOT/seed/seed"
      fi
      # NOTE: the seed takes `-o <out>`; the stage1 family (names_stage) takes
      # positional `<in> <out>` arguments (argc >= 3, argv[1]/argv[2]).
      "$ROOT/seed/seed" "$ROOT/src/names_stage.ls" -o "$ROOT/build/stage1-names"
      "$ROOT/build/stage1-names" "$ROOT/src/names_stage.ls" "$ROOT/build/stage2_self"
      SELFHOST="$ROOT/build/stage2_self"
      echo "selfhost: cold start - seed chain produced build/stage2_self"
    fi
    # NOTE: SELFHOST is a stage1-family binary - it takes positional
    # `<in> <out>` arguments, NOT the seed's `-o` form.
    #
    # S3-1 scope: build.sh produces the selfhost compiler chain plus the src
    # baselines only. The 16 bls/tests/* M0/M1a/M1b milestone artifacts are the
    # seed's programs: run-linux.sh compiles them with the seed as test
    # infrastructure (names_stage has known narrower surfaces there - e.g.
    # match arms restricted to `{ return expr; }`), keeping every historical
    # exit-code/stdout assertion semantically unchanged.
    "$SELFHOST" "$ROOT/src/main.ls" "$ROOT/build/stage1"
    "$SELFHOST" "$ROOT/src/arith.ls" "$ROOT/build/stage1-arith"
    "$SELFHOST" "$ROOT/src/calc.ls" "$ROOT/build/stage1-calc"
    "$SELFHOST" "$ROOT/src/funcs.ls" "$ROOT/build/stage1-funcs"
    "$SELFHOST" "$ROOT/src/slice_stage.ls" "$ROOT/build/stage1-slice"
    "$SELFHOST" "$ROOT/src/struct_stage.ls" "$ROOT/build/stage1-struct"
    "$SELFHOST" "$ROOT/src/names_stage.ls" "$ROOT/build/stage1-names"
    echo "selfhost: built compiler chain + src baselines (build/stage1-*)"
    ;;
  *)
    echo "unsupported host: $host (use Linux or Windows/MSYS)" >&2
    exit 2
    ;;
esac
