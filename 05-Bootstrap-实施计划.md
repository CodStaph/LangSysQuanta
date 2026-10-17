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
| **M1b-1** | `Array` + 索引（`Slice` 仍待） | **已实现**；`arrays.ls` |
| **M1b-2** | 函数定义/调用（Int 参数/返回） | **已实现**；`funcs.ls` |
| **M1b-3a** | `enum`（单态标签，无负载匹配） | **已实现**；`enums.ls` |
| **M1b-3b** | `struct`（字段偏移 + 点访问） | **已实现**；`structs.ls` |
| **M1b-3c** | `Slice[T]`（局部视图） | **已实现**；`slices.ls` |
| **M1b-4** | `read_file`/`write_file` 内置 | **已实现**；`io.ls` |
| **M1c-0a** | 函数 `Slice[U8]` 参数 | **已实现**；`slice_params.ls` |
| **M1c-0b** | `&&`/`||`、位运算、`break`/`continue` | **已实现**；`ops.ls` |
| **M1c-0c-1** | `match`（tag-only） | **已实现**；`match.ls` |
| **M1c-0c-2** | enum 负载（`Some(Int)` + 绑定） | **已实现**；`payload.ls` |
| **M1c-0d-1** | `argc`/`arg_len`/`arg_byte` | **已实现**；`argv.ls` |
| **M1c-0d-2** | 动态路径（`read_file`/`write_file` 接受 Slice） | **已实现**；`dynpath.ls` |
| **M1c-0** | B-LS 可用性：解释器、Slice 参数、逻辑/位运算/argv | **部分完成** |
| **M1c-1** | stage1 lexer/parser（B-LS，hello 子集） | **已实现** |
| **M1c-2** | stage1 codegen/ELF（B-LS） | **已实现**；输出 hello ELF |
| **M1c-3a** | stage1 编译 `hello` | **已实现** |
| **M1c-3b-1** | stage1 `let`/算术/`return` | **已实现**；`arith.ls`，输出退出码 12 |
| **M1c-3b-2** | stage1 `if/while` + calc | **已实现**；`calc.ls`，退出码 14 |
| **M1d-0a** | stage1 多函数 + `Int` 参数 + 调用 | **已实现**；`funcs.ls` |
| **M1d-0b** | stage1 `Array`/`Slice` 参数与索引 | **已实现**；`slice_stage.ls`，退出码 177 |
| **M1d-0c** | stage1 `struct` / tag-only `enum` + `match` | **已实现**；`struct_stage.ls`，退出码 177 |
| **M1d-0d** | stage1 多字符名字/名字表 | **已实现**；`names_stage.ls`，退出码 177 |
| **M1d** | stage1 自编译 + `stage1 == stage2` | 未开始 |

> stage1 必须使用 M1b 的数组/函数；M1b 已完成，但 M1c 仍缺 5 项可用性/可测试性前提（见 §13）。
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
- 字符串 UTF-8；字符串 `.len` 为字符数（`"你好".len == 2`），`Slice[U8].len` 为字节数；错误列按字符（code point）；
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
| M1c | 名称解析 + 最小类型检查 | 负例报错 |
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
- [x] `arrays.ls` → ELF64；反汇编确认 `Array[Int,4]`/`Array[U8,4]`、索引缩放、字节读写；
- [x] `enums.ls` → ELF64；反汇编确认标签常量与比较；
- [x] `structs.ls` → ELF64；反汇编确认字段偏移、点访问与数据块；
- [x] `slices.ls` → ELF64；反汇编确认 `Slice[U8]` base/len、`.len`、`s[i]`；
- [x] `io.ls` → ELF64；反汇编确认 `openat/read/write/close`；CI 做文件比较；
- [x] Linux 交叉构建通过（`--target=x86_64-unknown-linux-gnu -nostdlib`）；
- [x] GitHub Actions + `bootstrap/ci/run-linux.sh`（执行验证）；
- [x] 函数定义/调用（Int 参数/返回，M1b-2）；
- [x] M1b 全部：Array/函数/enum/struct/Slice/文件 I/O；
- [x] `seed --run` B-LS 解释器（M1c-0e）；所有 B-LS 测试可在宿主执行；
- [x] 函数 `Slice[U8]` 参数（M1c-0a）；`slice_params.ls`；
- [x] `&&`/`||`（短路）、位运算、`break`/`continue`（M1c-0b）；`ops.ls`；
- [x] `match` tag-only（M1c-0c-1）；`match.ls`；
- [x] enum 负载 + `match` 绑定（M1c-0c-2）；`payload.ls`；
- [x] `argc`/`arg_len`/`arg_byte`（M1c-0d-1）；`argv.ls`；
- [x] 动态路径（M1c-0d-2）；`dynpath.ls`；
- [x] M1c-0 前置全部完成；下一步 M1c-1/2/3（stage1）。
- [x] `bootstrap/src/main.ls`（stage1，hello 子集）；M1c-1/2/3 hello 已完成；
- [x] stage1 支持 `let`/算术/`return`（M1c-3b-1）；`arith.ls`；
- [x] stage1 多函数 + `Int` 参数 + 调用（M1d-0a）；`funcs.ls`；
- [x] stage1 `Array`/`Slice` 参数与索引（M1d-0b）；`slice_stage.ls`；
- [x] stage1 `struct` / tag-only `enum` + `match`（M1d-0c）；`struct_stage.ls`；
- [x] stage1 多字符名字/名字表（M1d-0d）；`names_stage.ls`；
- [x] Unicode/UTF-8：源文件校验、Unicode 标识符、UTF-8 字符串、字符列位置；`unicode.ls`、`stage1_unicode_names.ls`；
- [ ] `stage1 == stage2`（M1d）。

## 12. CI

```bash
./bootstrap/ci/run-linux.sh
```

在 Ubuntu 上：构建 seed → 编译 `hello`/`calc` → 执行 → 校验输出与退出码（calc=14）。
Windows 本地只构建 + 反汇编；不执行 Linux ELF。

---

## 13. M1c 前置条件（为什么不能直接写 stage1）

M1b 已提供 Array/Slice/struct/enum/函数/文件 I/O，但 stage1 是**编译器**，还缺：

| # | 缺口 | 影响 |
|---|---|---|
| 1 | 函数参数/返回值只支持 Int | 不能把缓冲区/节点传给函数；只能靠全局变量 |
| 2 | 无 `&&`/`||`、位运算、`break`/`continue` | 词法/解析/ELF 代码非常难写 |
| 3 | 无 `match`/enum 负载 | 错误处理与 token 分类困难 |
| 4 | 路径只能是字符串字面量 | stage1 不能接受 `argv`/`-o` |
| 5 | 无 B-LS 解释器或宿主执行路径 | stage1 是 Linux ELF，本机（Windows）无法运行/调试 |

### 13.1 建议顺序

1. **M1c-0a**：函数支持 `Slice[U8]` 参数（或 `(ptr,len)` 显式参数）；
2. **M1c-0b**：`&&`/`||`、`&`/`|`/`^`/`<<`/`>>`、`break`/`continue`；
3. **M1c-0c**：`enum` 负载 + `match`（至少 tag 分支）；
4. **M1c-0d**：`argv`/动态路径（或先用固定路径）；
5. **M1c-0e**：`seed --run` B-LS 解释器（本机调试 stage1，强烈建议）；
6. **M1c-1/2/3**：写 stage1，先 hello，再 calc。

> 没有第 5 项，stage1 只能盲写 + CI 验证；这是当前最大的工程风险。

### 13.2 当前状态

- M1b：完成；
- M1c：完成；
- M1d-0a/0b：完成；
- M1d-1/2（自编译与固定点）：未开始。

---

## 14. M1c-0e 记录（B-LS 解释器）

- 命令：`seed --run <file.ls>`；
- 覆盖：let/算术/if/while、函数、数组、enum、struct、Slice、read_file/write_file；
- 验证：`bootstrap/ci/run-interp.sh` 在宿主执行全部 B-LS 测试并校验 stdout/退出码；
- 限制：函数局部变量是全局槽，递归会覆盖；数组/Slice 无边界检查；无错误恢复。

> 这是 stage1 的本地调试路径：先让 stage1 在解释器下跑通，再编译成 ELF。

---

## 15. M1c-1/2/3 记录（hello 子集）

- `bootstrap/src/main.ls`：B-LS 写成的 stage1；
- 支持 `fn main() -> Int { write("..."); return N; }`；
- 用 `--run` 运行 stage1，读 `hello.ls`，生成 ELF；
- seed 编译 stage1 为 ELF；Linux CI 执行 stage1 并用其产物运行 hello；
- `calc`（let/arith/if/while）尚未进入 stage1，属 M1c-3 剩余项。

---

## 16. M1c-3b-1 记录（arith stage1）

- `bootstrap/src/arith.ls`：单字母变量、`let`、算术/比较/括号、`return`；
- 表达式用 shunting-yard 转后缀，再生成 push/pop 指令；
- 变量槽在输出 ELF 数据段，`[rip+disp]` 回填；
- `arith.ls` 输出退出码 12；
- 限制：单字母变量；`write` 路径尚未在 arith stage1 中正确实现；`if/while` 待 3b-2。

---

## 17. M1d-0a 记录（stage1 多函数）

- `bootstrap/src/funcs.ls`：多函数、`Int` 参数、调用补丁、`ret`、末尾 trampoline；
- 测试 `funcs2.ls`：`add(1,2)` → 退出码 3；
- 修复变量槽使用字母索引（`char-97`），不再混用 ASCII 值；调用结果补 `push rax`。

---

## 18. M1d-0b 记录（stage1 Array/Slice）

- `bootstrap/src/slice_stage.ls`：在 funcs 基础上加数组声明、索引读写、
  `Slice[U8/Int]` 参数与 `slice(array, off, len)`；
- 测试 `bootstrap/bls/tests/stage1_slice.ls` → 退出码 177；
- `slice_stage.ls` 的数组/切片元数据放在 `post` 表高段（4096/4608），
  避免增加函数参数槽；索引子表达式用独立的非递归 `parse_index`；
- seed 的 `MAX_EXPR`/`MAX_STMT` 上调到 16384/8192，以便解释执行更大的 stage1 源码；
- 限制：仍为单字母名字；实参只支持数字/单字母变量；数组/Slice 无边界检查。

---

## 19. M1d-0c 记录（stage1 struct / enum）

- `bootstrap/src/struct_stage.ls`：在 slice stage 基础上加 `struct` 声明、字段偏移、
  `.field` 读写、`enum` 标签与 tag-only `match`；
- 测试 `bootstrap/bls/tests/stage1_struct_enum.ls` → 退出码 177；
- 元数据表：struct 定义 5120、struct 变量 6400、enum 定义 7000（均在 `post` 高段）；
- 字段布局按声明顺序累加（`Int`=8、`U8`=1），字段读/写用绝对数据偏移回填；
- `let c = Color.Green;` 作为普通 `Int` 槽存储，`match` 逐 arm `cmp/jne`，
  arm 目前限定为 `{ return <expr>; }`；
- seed 的 `MAX_STRS` 上调到 512，支持更大的 stage1 源码；
- 限制：enum 仅 tag-only；match arm 尚无通用语句块；仍为单字母名字。

---

## 20. M1d-0d 记录（stage1 名字表）

- `bootstrap/src/names_stage.ls`：以名字表取代单字母变量/8 字节打包名；
- 测试 `bootstrap/bls/tests/stage1_names.ls` → 退出码 177；
- 名字表改为**变长字节池**：`post[10000]` 计数、`post[10001]` 已用字节；
  条目 `post[10002+i*2] = {byte_off, byte_len}`；字节池从 `post[12000]` 开始，容量约 166 KiB；
- Int 变量表：`post[9000]` 计数，条目 `{name_id, fn, off}`；变量槽按需从 `dlen` 分配；
- 函数名、参数名、struct/enum 名与字段/变体名全部使用 name id；
- 变量/函数/字段名超过 8 字符可解析；256 字节标识符测试 `stage1_long_name.ls` 通过；
- stage1 自身的 `parse_expr`/`emit_expr` 等名字可解析；
- 限制：名字最长 256 字节；参数最多 6 个；match arm 仍仅 `{ return <expr>; }`。

---

## 21. Unicode / UTF-8 记录

- 源文件按 UTF-8 校验；非法 UTF-8 在读取边界报错；
- seed 标识符允许 ASCII 字母/数字/下划线与非 ASCII Unicode 标量值（宽松规则，不要求完整 XID）；
- 字符串保持 `Slice[U8]` UTF-8 字节，不做规范化/转码；
- 字符串 `.len` 为字符数（Unicode 标量值），例如 `"你好".len == 2`；`Slice[U8].len` 为字节数；
- 当前仅字符串字面量 `.len` 常量折叠，一般 `Str` 值待扩展；
- 诊断位置为 1 基行号 + 1 基字符列，按 Unicode 标量值计数；
- 测试：`bootstrap/bls/tests/unicode.ls`（输出 `你好，L-Sys ✅`，退出码 42）；
  `stage1_unicode_names.ls`（stage1 解析 Unicode 名字，退出码 177）；
  `ci/run-interp.sh` 校验字符列与非法 UTF-8。
