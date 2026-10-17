# 05 · Bootstrap 实施计划（无 LLVM / 无 Rust 依赖链）

> **上位**：[`00`](00-LangSysQuanta-设计初稿.md)（§3.2 实现策略）、[`02`](02-架构评审与ADR.md)（ADR-2/28–30）、
> [`04`](04-S-1-执行计划.md)。
> **状态**：`0.1.0`，与 S-1 并行的 bootstrap 线；**不是 S-1 的出口条件**。
> **目标**：用尽可能少的外部工具，按经典三阶段自举，得到可复现的 L-Sys 编译器。

---

## 0. 目标与非目标

### 0.1 依赖最小化

| 依赖 | 阶段 | 是否可去掉 |
|---|---|---|
| CPU / 操作系统 syscall | 始终 | 否 |
| C 编译器（仅构建 seed） | Stage 0 | 构建后不再需要 |
| libc / 汇编器 / 链接器 | Stage 0 之后 | **是**（seed 直接 emit ELF） |
| LLVM / Cranelift | 始终 | **是** |
| Rust / Cargo / CMake | 始终 | **是** |
| 外部库 / 包管理器 | 始终 | **是**（全部 in-tree） |

**最终构建链**：

```text
[一次性] C 编译器
   └─ seed (freestanding C)
        └─ stage1 (B-LS)
             └─ stage2 (B-LS)
                  └─ stage3 (验证：与 stage2 逐位比较)
```

### 0.2 非目标

- 不用汇编写完整编译器（只写 seed/运行时极小片段，见 ADR-29）；
- 不引入 LLVM/Cranelift；
- 不实现跨平台宿主（第一阶段只做 x86_64 Linux 目标）；
- 不在 bootstrap 阶段追求优化/增量编译；
- 不把 bootstrap 线塞进 S-1 出口条件。

---

## 1. 三个阶段的定义

| 阶段 | 产物 | 由谁编译 | 作用 |
|---|---|---|---|
| **0** | seed（C） | 一次性 C 编译器 | 能编译 B-LS 子集，直接 emit ELF |
| **1** | stage1（B-LS） | seed | 第一个 L-Sys 编译器，能自编译 |
| **2** | stage2（B-LS） | stage1 | 自举固定点；逐步实现完整 L-Sys |
| **3** | stage3 | stage2 | 验证 `stage2 == stage3`；去种子 |

> 经典三阶段 = 0→1→2；stage3 是固定点验证，不是新语言阶段。

---

## 2. Stage 0：C seed（M0 已落地）

### 2.1 范围

- **M0**：`fn main() -> Int { write("..."); return N; }`
- **M1a（已实现）**：`let` / 赋值、整数算术与比较、`if/else`、`while`、`write(string)`、`return(expr)`
- 输出：x86_64 Linux 静态 ELF（`write(2)` + `exit(2)`）
- 不依赖：libc（Linux 路径用 raw syscall）、`as`、`ld`、LLVM、Rust
- Windows 只是开发宿主（CRT 文件 I/O），**不是目标**

### 2.2 交付物（当前仓库）

```text
bootstrap/
  seed/seed.c              # M0 seed
  bls/tests/hello.ls       # 第一个程序
  build.sh                 # 唯一构建脚本
  build/                   # 产物（git 忽略）
```

### 2.3 构建

```bash
# Windows（开发宿主）
./bootstrap/build.sh
# Linux（目标/CI）
./bootstrap/build.sh
```

### 2.4 退出判据（M0/M1a）

- [x] seed 可编译 `hello.ls`；
- [x] seed 可编译 `calc.ls`（let/算术/if/while，返回 14）；
- [x] 输出 ELF64，`e_machine=x86_64`，entry 指向代码；
- [x] 反汇编确认 `write`/`exit`、算术、比较、循环与变量槽；
- [ ] 在 Linux 上实际运行（GitHub Actions 已配置，本地无 WSL/QEMU）；
- [x] seed 源码 ≤ 15k 行（当前约 900 行）。

> 当前状态：Windows 宿主上可构建并生成 ELF；Linux 交叉构建通过；
> **执行验证由 `bootstrap/ci/run-linux.sh` 在 CI 完成**。

### 2.5 M1 拆分（重要）

原 M1 一次列出「结构/控制流/函数/数组」+「stage1 自编译」，实际是数月工作量。拆为：

| 子阶段 | 内容 | 状态 |
|---|---|---|
| **M1a** | `let`/算术/比较/`if`/`while`/`write`/`return` | **已实现** |
| **M1b-1** | `Array`/`Slice` + 索引 | 未开始 |
| **M1b-2** | 函数定义/调用（Int 参数/返回） | **已实现**；`funcs.ls` |
| **M1b-3** | `struct`/`enum`（单态） | 未开始 |
| **M1b-4** | `read_file`/`write_file` 内置 | 未开始 |
| **M1c** | stage1（B-LS）编译 `hello`/`calc` | 未开始 |
| **M1d** | stage1 自编译 + `stage1 == stage2` | 未开始 |

> stage1 必须使用 M1b 的数组/函数；在 M1b 完成前，M1c/M1d 不可能成立。
> 本阶段不伪造固定点。

---

## 3. B-LS：Bootstrap 方言

> 权威：[`spec/bls.md`](spec/bls.md)。B-LS 是 L-Sys 的**严格子集**，不是第二门语言。

### 3.1 设计约束

| 约束 | 原因 |
|---|---|
| 无 region 推断 / 无 `ref` | 种子不必实现 region；编译器用 arena + 索引 |
| 无泛型/trait/闭包 | 种子小；用单态容器 + 函数指针 |
| 允许 `rawptr` + `unsafe` | 编译器内部需要；TCB 审计 |
| 无契约/效果/comptime | 编译器**检查**它们，但自身不使用 |
| 整程序编译 | 不需要链接器/目标文件 |

### 3.2 编译器自身的内存模型

- 全程 arena（bump allocator），不释放；
- AST/IR/符号表用 `u32` 索引；
- 容器单态：`VecU8`/`VecU32`/`VecPtr`；
- 字符串 `Slice[U8]`，不校验 UTF-8；
- 错误：`ErrorCode` + 全局 `last_error`，不依赖 `Result` 泛型。

---

## 4. Stage 1：stage1（B-LS 编写）

### 4.1 目录（计划）

```text
bootstrap/src/
  main.ls
  lexer.ls
  parser.ls
  ast.ls
  resolve.ls
  types.ls
  ir.ls
  codegen_x86_64.ls
  elf.ls
  arena.ls
  vec.ls
  map.ls
  diag.ls
```

### 4.2 里程碑

| 里程碑 | 内容 | 退出判据 |
|---|---|---|
| M1a | 能解析 B-LS 的 `struct`/`fn`/`if`/`while` | 编译 3 个测试程序 |
| M1b | 名称解析 + 最小类型检查 | 负例报错 |
| M1c | x86_64 codegen（自写） | 与 seed 产物语义一致 |
| M1d | stage1 自编译 | `stage1 == stage2` |

### 4.3 固定点脚本

```bash
./bootstrap/seed/seed bootstrap/src -o bootstrap/build/stage1
./bootstrap/build/stage1 bootstrap/src -o bootstrap/build/stage2
cmp bootstrap/build/stage1 bootstrap/build/stage2
```

---

## 5. Stage 2：语言扩展（保持固定点）

按顺序加入，每加一项都重新验证 `stage2 == stage3`：

1. `Result`/`Option`/`?`；
2. 泛型（单态化）；
3. `val`/`ref` + 区域约束（先检查，不优化）；
4. `mode`/cap/效果；
5. 契约/`comptime`；
6. 诊断/fix-it（对齐 00 §6.4）。

**不要求**编译器自身使用这些特性；它可以用 B-LS 写，但实现完整语言。
这避免了「种子必须实现完整 L-Sys」的死锁。

---

## 6. Stage 3：去种子与目标扩展

### 6.1 去种子

```bash
./bootstrap/build/stage2 bootstrap/src -o bootstrap/build/stage3
cmp bootstrap/build/stage2 bootstrap/build/stage3
```

之后 `build.sh` 只依赖 `stage2` 二进制 + 源码；seed 源码保留用于审计/复现，但不在构建路径。

### 6.2 目标

| 目标 | 方式 |
|---|---|
| x86_64 Linux | 直接 ELF（当前） |
| ARM64 Linux | 新后端 + ELF |
| Cortex-M / RISC-V 裸机 | flat binary / ELF，固定加载地址；不依赖链接器 |
| 多目标 | `Target` 抽象；先整程序编译 |

### 6.3 信任与可复现

1. seed 用两个 C 编译器（gcc/clang）构建，比较；
2. DDC：不同 seed 构建 stage1，比较；
3. `stage2 == stage3`；
4. 固定时间戳/布局/无随机；
5. 可选：汇编写第二个极小 seed（仅 x86_64 Linux）作为信任锚点。

---

## 7. 依赖与产物矩阵

| 阶段 | 需要 | 不需要 |
|---|---|---|
| 构建 seed | 一个 C 编译器 | Rust/LLVM/CMake |
| 构建 stage1 | seed 二进制 | C 编译器、as/ld、libc |
| 构建 stage2 | stage1 | seed、C 编译器 |
| 构建 stage3 | stage2 | 一切外部构建工具 |

---

## 8. 时间与人力（1–2 人）

| 阶段 | 时间 | 产出 |
|---|---|---|
| 0（M0） | 2–4 周 | seed + hello ELF（已落地） |
| 0（M1） | 2–3 个月 | B-LS 结构/控制流/函数 |
| 1 | 4–6 个月 | stage1 自举 |
| 2 | 6–12 个月 | 完整 L-Sys 子集 + stage2 |
| 3 | 3–6 个月 | 去种子 + ARM64/裸机 + 可复现 |

> 只做 B-LS 自举：约 9–12 个月。完整 L-Sys 的长尾在 region/诊断。

---

## 9. 风险与对策

| 风险 | 对策 |
|---|---|
| B-LS 太弱，种子膨胀 | 只保留编译器必需特性；arena + 索引 |
| B-LS 太强，stage1 难写 | 单文件、单态容器、无泛型；逐步加 |
| 自写后端工作量大 | 先 x86_64 栈式后端；ARM64 后置 |
| 无链接器，无法分离编译 | 先整程序；S1 后加 `.o` + 自带静态链接 |
| C 种子信任 | 小种子 + 双编译器 + DDC + 可选汇编 seed |
| 编译器性能差 | 先正确；固定点后 profile |
| 与 00 的 Rust 参考实现冲突 | ADR-29：Rust 为参考实现，C seed/B-LS 为无依赖链 |

---

## 10. 文档与 ADR

| 文档 | 作用 |
|---|---|
| `05`（本文） | 计划、阶段、判据 |
| [`spec/bls.md`](spec/bls.md) | B-LS 子集规范 |
| `02 ADR-28` | 自举：S5 前不做，之后按 readiness |
| `02 ADR-29` | 实现语言：Rust 参考 + C seed/B-LS 无依赖链 |
| `02 ADR-30` | 第一阶段整程序编译、直接 ELF、不引入链接器 |

---

## 11. 当前状态

- [x] `bootstrap/seed/seed.c` 可构建（Windows 宿主）；
- [x] `hello.ls` → ELF64，`llvm-readelf`/`llvm-objdump` 验证通过；
- [x] `calc.ls` → ELF64；反汇编确认算术/比较/循环/变量槽；
- [x] `funcs.ls` → ELF64；反汇编确认函数入口/参数槽/`call`/`ret`；
- [x] Linux 交叉构建通过（`--target=x86_64-unknown-linux-gnu -nostdlib`）；
- [x] GitHub Actions + `bootstrap/ci/run-linux.sh`（执行验证）；
- [x] 函数定义/调用（Int 参数/返回，M1b-2）；
- [ ] `Array`/`Slice`（M1b-1）、`struct`/`enum`（M1b-3）、文件 I/O（M1b-4）；
- [ ] `bootstrap/src`（stage1，M1c）；
- [ ] `stage1 == stage2`（M1d）。

## 12. CI

```bash
./bootstrap/ci/run-linux.sh
```

在 Ubuntu 上：构建 seed → 编译 `hello`/`calc` → 执行 → 校验输出与退出码（calc=14）。
Windows 本地只构建 + 反汇编；不执行 Linux ELF。
