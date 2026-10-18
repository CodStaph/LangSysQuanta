#!/usr/bin/env bash
# guest-run.sh — drives the real CI scripts inside the QEMU guest.
#
# This is a thin wrapper, not a replacement: it runs the same
# bootstrap/ci/run-linux.sh that GitHub Actions runs, so any assertion added
# there is exercised here too. run-linux.sh already chains run-interp.sh and
# run-stage1.sh (whose Linux branch covers stage2 == stage3).
# The only difference is the host-prepared seed (SKIP_SEED_CC=1), see
# bootstrap/ci/run-qemu.sh.
set -uo pipefail

export SKIP_SEED_CC=1
fail=0


step() {
    echo ""
    echo "===== guest: $* ====="
    if ! "$@"; then
        echo "QEMU-GUEST: STEP FAILED: $*"
        fail=1
    fi
}

step bash bootstrap/ci/run-linux.sh

echo ""
if [ "$fail" -eq 0 ]; then
    echo "QEMU-GUEST: RESULT=PASS"
else
    echo "QEMU-GUEST: RESULT=FAIL"
fi
exit "$fail"
