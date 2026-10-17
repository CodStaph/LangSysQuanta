# LangSysQuanta

[中文](#langsysquanta-中文) | [English](#langsysquanta-english)

---

## LangSysQuanta（中文）

LangSysQuanta 是一个面向 **AI 生成与自动修复** 的系统编程语言项目，目标是在保持底层控制能力的同时，提供更可检查、更可复现、更适合机器生成的安全子集。

项目采用 **三阶段自举路线**：

```text
C seed → B-LS stage1 → stage2 → 固定点 stage3
```

最终目标是不依赖 LLVM、Rust 或大型工具链即可构建编译器自身。

### 当前状态

- C seed：已实现
- B-LS 解释器：已实现（`seed --run`）
- stage1（B-LS 编写）：已实现
  - 多函数、Int/Slice 参数、数组、struct、enum、match
  - 变长名字表、UTF-8 标识符
  - 控制流、`write`、表达式实参
  - 内置 I/O：`read_file`/`write_file`、`argc`/`arg_len`/`arg_byte`
  - 动态 argv 路径，支持最多 256 字节
  - **stage1 自编译到 stage2**：解释执行路径已通过
- 固定点 `stage2 == stage3`：CI 已接入，等待 Linux 实测
- 尚未声称完整 L-Sys 自举或固定点成立

### 设计目标

- 值语义与显式区域/借用
- mode / capability / effect 检查
- 确定性构建
- 无隐式分配、无隐式析构
- 可审计的 `unsafe` 边界
- 面向 AI 的结构化诊断与 fix-it
- 编译器自身可自举、可复现

### 仓库结构

```text
bootstrap/
  seed/        C seed（生成 x86_64 Linux ELF）
  seed/        B-LS 解释器（interp.inc）
  src/         stage1（B-LS 编写）
  bls/tests/   B-LS 测试程序
  ci/          Linux / 解释器 / stage1 / 固定点 CI 脚本
  build.sh     唯一构建入口

spec/          B-LS 与语言规范
dossiers/      语义试点档案
results/       评审与试点结果
tools/         doc-lint、checker-spike
tests/         conformance 测试
```

### 构建

依赖：

- C 编译器（默认 `clang`）
- Bash
- Linux 下运行生成的 ELF
- Python（仅 `doc-lint` 需要）

```bash
./bootstrap/build.sh
```

Windows / MSYS 下会构建 `seed.exe` 和 Linux ELF，但不执行 ELF。

### 测试

```bash
# B-LS 解释器测试（Windows / Linux 均可）
./bootstrap/ci/run-interp.sh

# Linux：编译产物执行 + 解释器 + stage1
./bootstrap/ci/run-linux.sh

# stage1、自编译、固定点检查
./bootstrap/ci/run-stage1.sh

# 文档一致性
python tools/doc-lint --strict
```

### 固定点验证

在 Linux 上：

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

只有 `cmp` 真实通过后，才记录固定点成立。

### 限制

- 当前主要目标为 x86_64 Linux ELF
- Windows 只能构建和做解释器测试，不能执行 Linux ELF
- 尚未实现完整 L-Sys 类型系统、region/mode/cap/effect 检查
- 固定点仍待 Linux CI 实测
- 编译器仍有静态数组容量和语法子集限制

### 许可证

见 `LICENSE`。

---

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
  - **stage1 self-compiles to stage2**: interpreted path passes
- Fixed point `stage2 == stage3`: CI wired, awaiting real Linux verification
- Full L-Sys self-hosting and fixed point are **not yet claimed**

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

The fixed point must only be recorded after a real `cmp` passes.

### Limitations

- Current target is mainly x86_64 Linux ELF
- Windows can build and run interpreter tests, but cannot execute Linux ELF
- Full L-Sys type system, region/mode/cap/effect checking are not implemented yet
- Fixed point still needs real Linux CI verification
- The compiler still has static-array capacity and language-subset limits

### License

See `LICENSE`.
