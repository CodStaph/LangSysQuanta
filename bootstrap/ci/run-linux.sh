#!/usr/bin/env bash
# Linux CI: build seed, compile B-LS tests, execute them.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

./bootstrap/build.sh

hello_out="$(./bootstrap/build/hello)"
test "$hello_out" = "hello from L-Sys bootstrap"

set +e
./bootstrap/build/calc > /tmp/calc.out
calc_rc=$?
set -e
test "$calc_rc" -eq 14
grep -q "calc ok" /tmp/calc.out
echo "bootstrap CI: hello + calc OK (calc exit=$calc_rc)"
