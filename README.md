# LangSysQuanta

[中文](README_CH.md) | [English](README.md)

## LangSysQuanta (English)

LangSysQuanta is a systems programming language project designed for **AI-assisted generation and automatic repair**, while keeping low-level control, auditability, and reproducible builds.

The project follows a **three-stage bootstrap path**:

```text
C seed → B-LS stage1 → stage2 → fixed point stage3
```

The long-term goal is to build the compiler without LLVM, Rust, or a large toolchain dependency chain.

### Current Status

- C seed: implemented
- B-LS interpreter: implemented (`seed --run`)
- stage1 (written in B-LS): implemented
  - multiple functions, Int/Slice parameters, arrays, structs, enums, match
  - variable-length name pool, UTF-8 identifiers
  - control flow, `write`, expression arguments
  - built-in I/O: `read_file`/`write_file`, `argc`/`arg_len`/`arg_byte`
  - dynamic argv paths up to 256 bytes
  - **stage1 self-compiles to stage2**: both the interpreted and the compiled path pass
- Fixed point `stage2 == stage3`: **established** (verified on GitHub Actions; `stage2` and `stage3` share the same SHA-256)
- Full L-Sys self-hosting is **not yet claimed** (only the B-LS subset reaches a fixed point)

### Design Goals

- value semantics with explicit regions and borrowing
- mode / capability / effect checking
- deterministic builds
- no implicit allocation or implicit destruction
- auditable `unsafe` boundaries
- structured diagnostics and fix-its for AI workflows
- self-hosted and reproducible compiler

### Repository Layout

```text
bootstrap/
  seed/       C seed (emits x86_64 Linux ELF)
  seed/       B-LS interpreter (interp.inc)
  src/        stage1 (written in B-LS)
  bls/tests/  B-LS test programs
  ci/         Linux / interpreter / stage1 / fixed-point CI scripts
  build.sh    single build entry point

spec/         B-LS and language specifications
dossiers/     semantic pilot dossiers
results/      review and pilot results
tools/        doc-lint, checker-spike
tests/        conformance tests
```

### Build

Requirements:

- C compiler (default: `clang`)
- Bash
- Linux to execute generated ELF files
- Python only for `doc-lint`

```bash
./bootstrap/build.sh
```

On Windows / MSYS, the build produces `seed.exe` and Linux ELF files, but does not execute the ELF files.

### Tests

```bash
# B-LS interpreter tests (Windows / Linux)
./bootstrap/ci/run-interp.sh

# Linux: execute compiled programs + interpreter + stage1
./bootstrap/ci/run-linux.sh

# No Linux / no VT-x: run the same CI on a real kernel via QEMU (TCG)
./bootstrap/ci/run-qemu.sh

# stage1, self-compile and fixed-point checks
./bootstrap/ci/run-stage1.sh

# Documentation consistency
python tools/doc-lint --strict
```

### Fixed-Point Verification

On Linux:

```bash
./bootstrap/build.sh

./bootstrap/build/stage1-names \
  bootstrap/src/names_stage.ls \
  bootstrap/build/stage2

./bootstrap/build/stage2 \
  bootstrap/src/names_stage.ls \
  bootstrap/build/stage3

cmp bootstrap/build/stage2 bootstrap/build/stage3
sha256sum bootstrap/build/stage2 bootstrap/build/stage3
```

The fixed point holds: CI measured `stage2` and `stage3` byte-identical, both with
SHA-256 `ac6d13443c657362b7919f8ac773d4e4317b607f2a3c9cd709737556e2f1a1de`.

### Limitations

- Current target is mainly x86_64 Linux ELF
- Without VT-x, Windows can still execute the Linux ELF locally via `bootstrap/ci/run-qemu.sh` (QEMU TCG, real kernel)
- Full L-Sys type system, region/mode/cap/effect checking are not implemented yet
- The compiler still has static-array capacity and language-subset limits

### License

See `LICENSE`.
