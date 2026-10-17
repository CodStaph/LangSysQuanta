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

# 2) compiled stage1 (Linux only)
if [ "$(uname -s)" = "Linux" ]; then
  ./bootstrap/build/stage1 bootstrap/bls/tests/hello.ls bootstrap/build/hello_stage1b
  out="$(./bootstrap/build/hello_stage1b)"
  test "$out" = "hello from L-Sys bootstrap"
  echo "PASS compiled stage1 -> hello runs"
else
  echo "SKIP compiled stage1 execution on $(uname -s)"
fi
