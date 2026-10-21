#!/usr/bin/env bash
# tools/check-docs.sh — local documentation gate.
#
# Mirrors the CI doc-lint step and adds the local-only golden diff:
#   - spec/diagnostics.md must be in sync with 00 §6.4
#     (this comparison cannot run in CI because 00 is not published;
#      tools/diag-extract --check exits 0 with INFO when 00 is absent)
#
# Usage: bash tools/check-docs.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python tools/doc-lint --strict
python tools/diag-extract --check
python tools/freeze-hash --check
python tools/grammar-coverage
