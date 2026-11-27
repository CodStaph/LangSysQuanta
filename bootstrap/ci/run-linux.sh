#!/usr/bin/env bash
# Linux CI: build seed, compile B-LS tests, execute them.
set -euo pipefail
trap 'echo "run-linux FAILED at line $LINENO"' ERR
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

./bootstrap/build.sh

# S3-1: build.sh now produces the selfhost compiler chain + src baselines
# only. The 16 bls/tests/* artifacts below are the seed's M0/M1a/M1b
# milestone programs - the seed compiles them here as test infrastructure
# (same as the historical build.sh Linux branch), so every exit-code/stdout
# assertion below keeps its original semantics. names_stage has narrower
# surfaces on 4 of these (unicode/match/payload/io), which is exactly why
# they stay on the seed side.
bash ./bootstrap/ci/ensure-seed.sh
SEED_BIN="./bootstrap/seed/seed"
[ -x "$SEED_BIN" ] || SEED_BIN="./bootstrap/seed/seed.exe"
"$SEED_BIN" bootstrap/bls/tests/hello.ls -o bootstrap/build/hello
"$SEED_BIN" bootstrap/bls/tests/unicode.ls -o bootstrap/build/unicode
"$SEED_BIN" bootstrap/bls/tests/str.ls -o bootstrap/build/str
"$SEED_BIN" bootstrap/bls/tests/calc.ls -o bootstrap/build/calc
"$SEED_BIN" bootstrap/bls/tests/funcs.ls -o bootstrap/build/funcs
"$SEED_BIN" bootstrap/bls/tests/arrays.ls -o bootstrap/build/arrays
"$SEED_BIN" bootstrap/bls/tests/enums.ls -o bootstrap/build/enums
"$SEED_BIN" bootstrap/bls/tests/structs.ls -o bootstrap/build/structs
"$SEED_BIN" bootstrap/bls/tests/slices.ls -o bootstrap/build/slices
"$SEED_BIN" bootstrap/bls/tests/io.ls -o bootstrap/build/io
"$SEED_BIN" bootstrap/bls/tests/slice_params.ls -o bootstrap/build/slice_params
"$SEED_BIN" bootstrap/bls/tests/ops.ls -o bootstrap/build/ops
"$SEED_BIN" bootstrap/bls/tests/match.ls -o bootstrap/build/match
"$SEED_BIN" bootstrap/bls/tests/payload.ls -o bootstrap/build/payload
"$SEED_BIN" bootstrap/bls/tests/argv.ls -o bootstrap/build/argv
"$SEED_BIN" bootstrap/bls/tests/dynpath.ls -o bootstrap/build/dynpath

hello_out="$(./bootstrap/build/hello)"
test "$hello_out" = "hello from L-Sys bootstrap"

set +e
unicode_out="$(./bootstrap/build/unicode)"
unicode_rc=$?
set -e
test "$unicode_rc" -eq 42
test "$unicode_out" = "你好，L-Sys ✅"

set +e
str_out="$(./bootstrap/build/str)"
str_rc=$?
set -e
test "$str_rc" -eq 10
test "$str_out" = "你好, Str ✅"

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
echo "bootstrap CI: M0/M1a/M1b + Unicode (UTF-8) OK"
./bootstrap/ci/run-interp.sh
./bootstrap/ci/run-stage1.sh
