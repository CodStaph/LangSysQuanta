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
./bootstrap/build/structs > /tmp/structs.out
structs_rc=$?
./bootstrap/build/slices > /tmp/slices.out
slices_rc=$?
./bootstrap/build/io > /tmp/io.out
io_rc=$?
./bootstrap/build/slice_params > /tmp/sparam.out
sparam_rc=$?
./bootstrap/build/ops > /tmp/ops.out
ops_rc=$?
./bootstrap/build/match > /tmp/match.out
match_rc=$?
./bootstrap/build/payload > /tmp/payload.out
payload_rc=$?
./bootstrap/build/argv foo boo > /tmp/argv.out
argv_rc=$?
./bootstrap/build/dynpath bootstrap/bls/tests/hello.ls > /tmp/dynpath.out
dynpath_rc=$?
set -e
test "$calc_rc" -eq 14
test "$funcs_rc" -eq 7
test "$arrays_rc" -eq 7
test "$enums_rc" -eq 1
test "$structs_rc" -eq 7
test "$slices_rc" -eq 177
test "$io_rc" -eq 0
test "$sparam_rc" -eq 177
test "$ops_rc" -eq 12
test "$match_rc" -eq 1
test "$payload_rc" -eq 42
test "$argv_rc" -eq 0
test "$dynpath_rc" -eq 0
cmp bootstrap/bls/tests/hello.ls bootstrap/build/copy.ls
grep -q "sparam ok" /tmp/sparam.out
grep -q "ops ok" /tmp/ops.out
grep -q "green" /tmp/match.out
grep -q "some" /tmp/payload.out
grep -q "argv ok" /tmp/argv.out
grep -q "dynpath ok" /tmp/dynpath.out
grep -q "calc ok" /tmp/calc.out
grep -q "funcs ok" /tmp/funcs.out
grep -q "arr ok" /tmp/arrays.out
grep -q "enum ok" /tmp/enums.out
grep -q "struct ok" /tmp/structs.out
grep -q "slice ok" /tmp/slices.out
grep -q "io ok" /tmp/io.out
echo "bootstrap CI: M0/M1a/M1b (arrays/functions/enums/structs/slices/io) OK"
./bootstrap/ci/run-interp.sh
