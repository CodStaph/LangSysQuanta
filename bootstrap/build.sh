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
    echo "built: $ROOT/build/hello (ELF64 x86_64; not executed on Windows)"
    if command -v llvm-readelf >/dev/null 2>&1; then
      llvm-readelf -h "$ROOT/build/hello" | sed -n '1,16p'
    fi
    ;;
  Linux*)
    "$CC" -nostdlib -static -fno-pic -no-pie -fno-stack-protector -fno-builtin -O2 \
      "$ROOT/seed/seed.c" -o "$ROOT/seed/seed"
    "$ROOT/seed/seed" "$ROOT/bls/tests/hello.ls" -o "$ROOT/build/hello"
    echo "built: $ROOT/build/hello"
    "$ROOT/build/hello"
    ;;
  *)
    echo "unsupported host: $host (use Linux or Windows/MSYS)" >&2
    exit 2
    ;;
esac
