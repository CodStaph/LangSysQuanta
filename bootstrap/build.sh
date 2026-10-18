#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
CC="${CC:-clang}"
mkdir -p "$ROOT/build"

host="$(uname -s 2>/dev/null || echo unknown)"
case "$host" in
  *MINGW*|*MSYS*|*CYGWIN*|*Windows*)
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
    # SKIP_SEED_CC=1 reuses an already cross-compiled freestanding seed instead
    # of invoking the C compiler. Used by bootstrap/ci/run-qemu.sh, where the
    # seed is built on the host and there is no compiler inside the guest; the
    # rest of the Linux branch (and every CI assertion) is unchanged.
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
    "$ROOT/seed/seed" "$ROOT/bls/tests/hello.ls" -o "$ROOT/build/hello"
    "$ROOT/seed/seed" "$ROOT/bls/tests/unicode.ls" -o "$ROOT/build/unicode"
    "$ROOT/seed/seed" "$ROOT/bls/tests/str.ls" -o "$ROOT/build/str"
    "$ROOT/seed/seed" "$ROOT/bls/tests/calc.ls" -o "$ROOT/build/calc"
    "$ROOT/seed/seed" "$ROOT/bls/tests/funcs.ls" -o "$ROOT/build/funcs"
    "$ROOT/seed/seed" "$ROOT/bls/tests/arrays.ls" -o "$ROOT/build/arrays"
    "$ROOT/seed/seed" "$ROOT/bls/tests/enums.ls" -o "$ROOT/build/enums"
    "$ROOT/seed/seed" "$ROOT/bls/tests/structs.ls" -o "$ROOT/build/structs"
    "$ROOT/seed/seed" "$ROOT/bls/tests/slices.ls" -o "$ROOT/build/slices"
    "$ROOT/seed/seed" "$ROOT/bls/tests/io.ls" -o "$ROOT/build/io"
    "$ROOT/seed/seed" "$ROOT/bls/tests/slice_params.ls" -o "$ROOT/build/slice_params"
    "$ROOT/seed/seed" "$ROOT/bls/tests/ops.ls" -o "$ROOT/build/ops"
    "$ROOT/seed/seed" "$ROOT/bls/tests/match.ls" -o "$ROOT/build/match"
    "$ROOT/seed/seed" "$ROOT/bls/tests/payload.ls" -o "$ROOT/build/payload"
    "$ROOT/seed/seed" "$ROOT/bls/tests/argv.ls" -o "$ROOT/build/argv"
    "$ROOT/seed/seed" "$ROOT/bls/tests/dynpath.ls" -o "$ROOT/build/dynpath"
    "$ROOT/seed/seed" "$ROOT/src/main.ls" -o "$ROOT/build/stage1"
    "$ROOT/seed/seed" "$ROOT/src/arith.ls" -o "$ROOT/build/stage1-arith"
    "$ROOT/seed/seed" "$ROOT/src/calc.ls" -o "$ROOT/build/stage1-calc"
    "$ROOT/seed/seed" "$ROOT/src/funcs.ls" -o "$ROOT/build/stage1-funcs"
    "$ROOT/seed/seed" "$ROOT/src/slice_stage.ls" -o "$ROOT/build/stage1-slice"
    "$ROOT/seed/seed" "$ROOT/src/struct_stage.ls" -o "$ROOT/build/stage1-struct"
    "$ROOT/seed/seed" "$ROOT/src/names_stage.ls" -o "$ROOT/build/stage1-names"
    echo "built: $ROOT/build/hello"
    "$ROOT/build/hello"
    ;;
  *)
    echo "unsupported host: $host (use Linux or Windows/MSYS)" >&2
    exit 2
    ;;
esac
