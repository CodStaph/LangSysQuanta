#!/usr/bin/env python3
"""EBNF -> GBNF golden-file differential.

The EBNF is the sole authority.  The committed spec/langSysQuanta.gbnf is a
mechanically generated artifact; this script regenerates it and fails on any
drift.  It does not parse input with a GBNF engine (that is a later W4 step).
"""
from __future__ import annotations

import difflib
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
GOLDEN = ROOT / "spec" / "langSysQuanta.gbnf"
TMP = ROOT / ".temp" / "langSysQuanta.gbnf"


def main() -> int:
    proc = subprocess.run(
        [sys.executable, str(ROOT / "tools" / "ebnf-parse"), "--gbnf"],
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        return proc.returncode
    generated = proc.stdout.replace("\r\n", "\n")
    expected = GOLDEN.read_text(encoding="utf-8").replace("\r\n", "\n")
    if generated == expected:
        rules = sum(1 for line in generated.splitlines() if line and not line.startswith("#"))
        print(f"GBNF PASS: {rules} rules, generated == {GOLDEN.relative_to(ROOT)}")
        return 0

    TMP.parent.mkdir(parents=True, exist_ok=True)
    TMP.write_text(generated, encoding="utf-8")
    print("GBNF FAIL: generated output differs from the golden file")
    print(f"generated: {TMP}")
    print(f"golden:    {GOLDEN}")
    diff = list(
        difflib.unified_diff(
            expected.splitlines(),
            generated.splitlines(),
            fromfile=str(GOLDEN.relative_to(ROOT)),
            tofile=str(TMP.relative_to(ROOT)),
            lineterm="",
        )
    )
    for line in diff[:120]:
        print(line)
    if len(diff) > 120:
        print(f"... {len(diff) - 120} more diff lines")
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
