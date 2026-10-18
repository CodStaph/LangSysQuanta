#!/usr/bin/env python3
"""Run the EBNF v2.1 syntax corpus with the hybrid normalization policy.

Formal grammar (spec/langSysQuanta.ebnf):
  tuple struct, bitfield widths, `ensures ... => ...`, `spawn expr`,
  empty tuple, `requires = ...` attribute argument.

Test-only normalization (this file, never part of the grammar):
  - `...` -> `todo()`
  - `iso Queue` -> `iso[Queue]`
  - `iso Queue.new()` -> `Queue.new()`
  - bodyless top-level `fn` -> append `{ todo() }` unless a `{` body follows
  - missing `;` on trait methods / declarations -> append

Evidence for the syntax-freeze gate (04 §14.6):
  - all 00 §5 code blocks (committed excerpts under tests/syntax/00-s5/)
  - all B-LS tests under bootstrap/bls/tests/*.ls

The recognizer is tools/ebnf-parse, a generic Earley recognizer driven by
spec/langSysQuanta.ebnf.  It is a test harness, not the S0' parser.
"""
from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
TMP = ROOT / ".temp" / "syntax-norm"


def split_comment(line: str) -> tuple[str, str]:
    i = line.find("//")
    if i < 0:
        return line, ""
    return line[:i], line[i:]


def normalize_shorthand(code: str) -> str:
    # Drop mode on constructor calls, then bracket only the type form.
    # `iso Ring { ... }` is a struct literal (`[mode] path { ... }`) and stays.
    code = re.sub(r"\biso\s+([A-Z][A-Za-z0-9_]*)\s*\.", r"\1.", code)
    code = re.sub(r"\biso\s+([A-Z][A-Za-z0-9_]*)\b(?!\s*[.{])", r"iso[\1]", code)
    return code


def brace_delta(code: str) -> int:
    return code.count("{") - code.count("}")


def next_code(lines: list[str], j: int) -> int | None:
    k = j + 1
    while k < len(lines):
        c, _ = split_comment(lines[k])
        if c.strip() != "":
            return k
        k += 1
    return None


def normalize_fn_decls(src: str) -> str:
    lines = src.splitlines()
    out: list[str] = []
    depth = 0
    i = 0
    while i < len(lines):
        code, comment = split_comment(lines[i])
        stripped = code.strip()

        if stripped.startswith("fn ") and "{" not in code and not code.rstrip().endswith(";"):
            if depth > 0:
                # Trait/impl method declaration without a body.
                code = code.rstrip() + ";"
            else:
                # Top-level bodyless declaration: collect a multi-line
                # signature, but do not add a placeholder body if a `{`
                # body follows on the next non-comment line.
                j = i
                body_follows = False
                while True:
                    k = next_code(lines, j)
                    if k is None:
                        break
                    nxt, _ = split_comment(lines[k])
                    n = nxt.strip()
                    if n.startswith("{"):
                        body_follows = True
                        break
                    if "{" in nxt or ";" in nxt or n == "}":
                        break
                    if re.match(
                        r"(fn|struct|enum|union|trait|impl|static|const|module|profile|comptime)\b",
                        n,
                    ):
                        break
                    j = k
                if not body_follows:
                    tail_code, tail_comment = split_comment(lines[j])
                    tail_code = tail_code.rstrip() + " { todo() }"
                    lines[j] = tail_code + ((" " + tail_comment) if tail_comment else "")
                for k in range(i, j + 1):
                    c, cm = split_comment(lines[k])
                    c = normalize_shorthand(c)
                    out.append(c + ((" " + cm) if cm else ""))
                depth += brace_delta(
                    "".join(split_comment(x)[0] for x in lines[i : j + 1])
                )
                i = j + 1
                continue

        code = normalize_shorthand(code)
        out.append(code + ((" " + comment) if comment else ""))
        depth += brace_delta(code)
        i += 1
    return "\n".join(out) + "\n"


def normalize_00(src: str) -> str:
    src = src.replace("...", "todo()")
    return normalize_fn_decls(src)


def main() -> int:
    corpus = sorted((ROOT / "tests" / "syntax" / "00-s5").glob("*.ls"))
    bls = sorted((ROOT / "bootstrap" / "bls" / "tests").glob("*.ls"))
    if not corpus or not bls:
        print("syntax: missing corpus or B-LS tests", file=sys.stderr)
        return 2

    TMP.mkdir(parents=True, exist_ok=True)
    normalized: list[Path] = []
    for p in corpus:
        dst = TMP / p.name
        dst.write_text(normalize_00(p.read_text(encoding="utf-8")), encoding="utf-8")
        normalized.append(dst)

    files = normalized + bls
    print(
        f"syntax: {len(corpus)} 00-s5 blocks (normalized) + {len(bls)} B-LS tests"
        f" = {len(files)} files"
    )
    cmd = [sys.executable, str(ROOT / "tools" / "ebnf-parse")] + [str(p) for p in files]
    return subprocess.run(cmd).returncode


if __name__ == "__main__":
    raise SystemExit(main())
