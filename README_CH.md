# LangSysQuanta

[中文](README_CH.md) | [English](README.md)

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
  - **stage1 自编译到 stage2**：解释执行与编译产物均已通过
- 固定点 `stage2 == stage3`：**已成立**（GitHub Actions 实测，两文件 SHA-256 一致）
- 尚未声称完整 L-Sys 自举（仅 B-LS 子集的固定点成立）

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

# 无 Linux / 无 VT-x 时：用 QEMU(TCG) 在真内核里跑同一套 CI
./bootstrap/ci/run-qemu.sh

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

固定点已成立：CI 实测 `stage2` 与 `stage3` 逐字节相同，
SHA-256 均为 `ac6d13443c657362b7919f8ac773d4e4317b607f2a3c9cd709737556e2f1a1de`。

### 限制

- 当前主要目标为 x86_64 Linux ELF
- 无 VT-x 的 Windows 可用 `bootstrap/ci/run-qemu.sh`（QEMU TCG，真内核）在本地执行 Linux ELF
- 尚未实现完整 L-Sys 类型系统、region/mode/cap/effect 检查
- 编译器仍有静态数组容量和语法子集限制

### 许可证

见 `LICENSE`。
