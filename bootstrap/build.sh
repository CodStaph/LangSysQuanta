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
    echo "built: $ROOT/build/hello (ELF64 x86_64; not executed on Windows)"
    if command -v llvm-readelf >/dev/null 2>&1; then
      llvm-readelf -h "$ROOT/build/hello" | sed -n '1,16p'
    fi
    ;;
  Linux*)
    "$CC" -nostdlib -static -fno-pic -no-pie -fno-stack-protector -fno-builtin -O2 \
      "$ROOT/seed/seed.c" -o "$ROOT/seed/seed"
    "$ROOT/seed/seed" "$ROOT/bls/tests/hello.ls" -o "$ROOT/build/hello"
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
    echo "built: $ROOT/build/hello"
    "$ROOT/build/hello"
    ;;
  *)
    echo "unsupported host: $host (use Linux or Windows/MSYS)" >&2
    exit 2
    ;;
esac
