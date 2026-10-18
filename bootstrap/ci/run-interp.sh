#!/usr/bin/env bash
# B-LS interpreter tests (seed --run). Runs on Linux and Windows/MSYS.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
cd "$ROOT"

SEED="./bootstrap/seed/seed"
[ -x "$SEED" ] || SEED="./bootstrap/seed/seed.exe"

check() {
  file="$1"; want_rc="$2"; want_out="$3"
  set +e
  out="$("$SEED" --run "$file")"
  rc=$?
  set -e
  if [ "$rc" -ne "$want_rc" ]; then
    echo "FAIL $file: rc=$rc want=$want_rc" >&2
    exit 1
  fi
  if [ "$out" != "$want_out" ]; then
    echo "FAIL $file: out=[$out] want=[$want_out]" >&2
    exit 1
  fi
  echo "PASS $file (rc=$rc)"
}

check bootstrap/bls/tests/hello.ls   0 "hello from L-Sys bootstrap"
check bootstrap/bls/tests/unicode.ls 42 "你好，L-Sys ✅"
check bootstrap/bls/tests/str.ls 10 "你好, Str ✅"
check bootstrap/bls/tests/calc.ls    14 "calc ok"
check bootstrap/bls/tests/funcs.ls   7  "funcs ok"
check bootstrap/bls/tests/arrays.ls  7  "arr ok"
check bootstrap/bls/tests/enums.ls   1  "enum ok"
check bootstrap/bls/tests/structs.ls 7  "struct ok"
check bootstrap/bls/tests/slices.ls  177 "slice ok"
check bootstrap/bls/tests/slice_params.ls 177 "sparam ok"
check bootstrap/bls/tests/high_offset.ls 177 ""
check bootstrap/bls/tests/logic_ops.ls 202 ""
check bootstrap/bls/tests/break_nested.ls 103 ""
check bootstrap/bls/tests/divmod.ls 132 ""
check bootstrap/bls/tests/ops.ls 12 "ops ok"
check bootstrap/bls/tests/match.ls 1 "green"
check bootstrap/bls/tests/payload.ls 42 "some"

set +e
argv_out="$("$SEED" --run bootstrap/bls/tests/argv.ls foo boo)"
argv_rc=$?
set -e
test "$argv_rc" -eq 0
test "$argv_out" = "argv ok"
echo "PASS argv.ls (rc=$argv_rc, args foo boo)"

set +e
dyn_out="$("$SEED" --run bootstrap/bls/tests/dynpath.ls bootstrap/bls/tests/hello.ls)"
dyn_rc=$?
set -e
test "$dyn_rc" -eq 0
test "$dyn_out" = "dynpath ok"
echo "PASS dynpath.ls (rc=$dyn_rc, Slice path)"

rm -f bootstrap/build/copy.ls
check bootstrap/bls/tests/io.ls 0 "io ok"
cmp bootstrap/bls/tests/hello.ls bootstrap/build/copy.ls
# Unicode diagnostics: columns are Unicode characters, not UTF-8 bytes.
cat > bootstrap/build/unicode_err.ls <<'EOF'
fn main() -> Int {
    let 变量 = 1; @
}
EOF
set +e
unicode_err="$("$SEED" bootstrap/build/unicode_err.ls -o bootstrap/build/unicode_err.out 2>&1)"
unicode_err_rc=$?
set -e
test "$unicode_err_rc" -ne 0
echo "$unicode_err" | grep -q "line 2, column 17 (character)"
echo "PASS Unicode diagnostic column is character-based"

# Invalid UTF-8 is rejected at the input boundary.
printf 'fn main() -> Int {\n    let x = 1; \377\n}\n' > bootstrap/build/bad_utf8.ls
set +e
utf8_err="$("$SEED" bootstrap/build/bad_utf8.ls -o bootstrap/build/bad_utf8.out 2>&1)"
utf8_rc=$?
set -e
test "$utf8_rc" -ne 0
echo "$utf8_err" | grep -q "invalid UTF-8"
echo "PASS invalid UTF-8 rejected"

echo "interp: all B-LS tests passed"
