#!/usr/bin/env bash
# ensure-seed.sh - make sure the seed binary exists; print nothing on success.
#
# S3-1 deseeding: the build main path (bootstrap/build.sh) no longer needs the
# seed - when build/stage2_self exists, every artifact is compiled by it and
# no C compiler is invoked. The seed keeps exactly two roles:
#   1. cold-start bootstrap chain (build.sh: seed -> stage1-names -> stage2_self)
#      for fresh checkouts, audits and reproduction;
#   2. the `seed --run` interpreter used by run-interp.sh and the interpreted
#      half of run-stage1.sh (test infrastructure, not a build path).
# This helper builds the seed only when it is missing, so the interpreter
# role stays available on hosts where build.sh took the selfhost main path.
#
# SKIP_SEED_CC=1 (QEMU guest) requires a prebuilt seed and never invokes the
# C compiler; a missing seed there is an error.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

host="$(uname -s 2>/dev/null || echo unknown)"
case "$host" in
  *MINGW*|*MSYS*|*CYGWIN*|*Windows*)
    SEED="$ROOT/bootstrap/seed/seed.exe"
    BUILD_FLAGS=(-O2 -fno-builtin -D_CRT_SECURE_NO_WARNINGS)
    ;;
  *)
    SEED="$ROOT/bootstrap/seed/seed"
    BUILD_FLAGS=(-nostdlib -static -fno-pic -no-pie -fno-stack-protector -fno-builtin -O2)
    ;;
esac

if [ -x "$SEED" ]; then
  exit 0
fi
if [ "${SKIP_SEED_CC:-0}" = "1" ]; then
  echo "ensure-seed: $SEED missing and SKIP_SEED_CC=1 (prebuilt seed required)" >&2
  exit 3
fi
CC="${CC:-clang}"
command -v "$CC" >/dev/null 2>&1 || {
  echo "ensure-seed: C compiler '$CC' not found (set CC=<path>)" >&2
  exit 3
}
"$CC" "${BUILD_FLAGS[@]}" "$ROOT/bootstrap/seed/seed.c" -o "$SEED"
echo "ensure-seed: built $SEED (interpreter/test tool; the build main path stays seed-free)"
