#!/usr/bin/env python3
"""Assemble genop_str.asm and embed the flat binary into stage1's source.

Usage: python bootstrap/helper/embed_genop.py [--nasm PATH]

The helper is a hand-written flat binary (`bits 64`, no ELF). stage1 copies it
into the generated code and calls it for generic Str/Slice operations, and for
the R4.6 general free list. The byte array and the blob length constant in
`bootstrap/src/names_stage.ls` must be regenerated whenever the assembly changes:

    python bootstrap/helper/embed_genop.py
"""
from __future__ import annotations

import re
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent.parent
ASM = ROOT / "bootstrap" / "helper" / "genop_str.asm"
SRC = ROOT / "bootstrap" / "src" / "names_stage.ls"


def main() -> int:
    nasm = shutil.which("nasm") or shutil.which("nasm.exe")
    if "--nasm" in sys.argv:
        nasm = sys.argv[sys.argv.index("--nasm") + 1]
    if not nasm:
        print("embed_genop: nasm not found (use --nasm PATH)", file=sys.stderr)
        return 2
    tmp = ROOT / ".qemu-cache"
    tmp.mkdir(exist_ok=True)
    out = tmp / "genop_str.bin"
    subprocess.run([nasm, "-f", "bin", str(ASM), "-o", str(out)], check=True)
    data = out.read_bytes()

    s = SRC.read_text(encoding="utf-8")
    # 1) declaration length
    s, n = re.subn(r"    let genop_str: Array\[U8, \d+\] = Array\.zeroed\(\);",
                   f"    let genop_str: Array[U8, {len(data)}] = Array.zeroed();", s)
    if n != 1:
        print("embed_genop: array declaration not found", file=sys.stderr)
        return 3

    # 2) blob length constant (main reads the free-list vector from the tail)
    length_line = f"    let genop_bytes = {len(data)};"
    if re.search(r"    let genop_bytes = \d+;", s):
        s, n = re.subn(r"    let genop_bytes = \d+;", length_line, s)
    else:
        s, n = re.subn(r"(    let genop_str: Array\[U8, \d+\] = Array\.zeroed\(\);\n)",
                       lambda m: m.group(1) + length_line + "\n", s)
    if n != 1:
        print("embed_genop: length constant not found", file=sys.stderr)
        return 6

    # 3) assignment block
    assign = "".join(f"    genop_str[{i}] = {b};\n" for i, b in enumerate(data))
    s, n = re.subn(r"(    genop_str\[0\] = \d+;\n)(?:    genop_str\[\d+\] = \d+;\n)*",
                   lambda _m: assign, s, count=1)
    if n != 1:
        print("embed_genop: assignment block not found", file=sys.stderr)
        return 4

    # 4) copy loop bound
    s, n = re.subn(r"(    while genop_i < )\d+( \{\n        emit1\(c, cs, genop_str\[genop_i\]\);)",
                   lambda m: f"{m.group(1)}{len(data)}{m.group(2)}", s, count=1)
    if n != 1:
        print("embed_genop: copy loop bound not found", file=sys.stderr)
        return 5
    SRC.write_text(s, encoding="utf-8", newline="")
    print(f"embed_genop: embedded {len(data)} bytes from {ASM.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
