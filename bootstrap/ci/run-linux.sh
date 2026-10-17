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
./bootstrap/build/funcs > /tmp/funcs.out
funcs_rc=$?
./bootstrap/build/arrays > /tmp/arrays.out
arrays_rc=$?
./bootstrap/build/enums > /tmp/enums.out
enums_rc=$?
set -e
test "$calc_rc" -eq 14
test "$funcs_rc" -eq 7
test "$arrays_rc" -eq 7
test "$enums_rc" -eq 1
grep -q "calc ok" /tmp/calc.out
grep -q "funcs ok" /tmp/funcs.out
grep -q "arr ok" /tmp/arrays.out
grep -q "enum ok" /tmp/enums.out
echo "bootstrap CI: hello + calc + funcs + arrays + enums OK"
