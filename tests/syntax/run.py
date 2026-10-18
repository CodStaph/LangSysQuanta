#!/usr/bin/env python3
"""Run the EBNF v2.1 syntax corpus.

Evidence for the syntax-freeze gate (04 §14.6):
  - all 00 §5 code blocks (committed excerpts under tests/syntax/00-s5/)
  - all B-LS tests under bootstrap/bls/tests/*.ls

The recognizer is tools/ebnf-parse, a generic Earley recognizer driven by
spec/langSysQuanta.ebnf.  It is a test harness, not the S0' parser.
"""
from __future__ import annotations

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent


def main() -> int:
    corpus = sorted((ROOT / "tests" / "syntax" / "00-s5").glob("*.ls"))
    bls = sorted((ROOT / "bootstrap" / "bls" / "tests").glob("*.ls"))
    files = corpus + bls
    if not files:
        print("syntax: no files found", file=sys.stderr)
        return 2
    print(f"syntax: {len(corpus)} 00-s5 blocks + {len(bls)} B-LS tests = {len(files)} files")
    cmd = [sys.executable, str(ROOT / "tools" / "ebnf-parse")] + [str(p) for p in files]
    return subprocess.run(cmd).returncode


if __name__ == "__main__":
    raise SystemExit(main())
