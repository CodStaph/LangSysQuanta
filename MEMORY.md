# MEMORY · LangSysQuanta 项目记忆

> **用途**：跨会话交接。记录当前基线、已完成能力、待实施任务的**严格顺序**与验收方式。
> **规则**：每完成一个任务，更新本文件并打 tag；不把「计划」写成「已完成」。
> **最近更新**：M1d-2 完成——`stage2 == stage3` 固定点由 GitHub CI 验证（PR #1；根因是元数据偏移只有 20 位，自编译时 `read_file` 拿到被截断的缓冲地址，已扩到 28 位）；本地 QEMU runner 进 main（PR #2）；22 份设计文档/规范迁入 main（PR #3，`eeffad98`）；本地 `master` 与 `main` 已收敛为完全一致。

---

## 0. 当前基线

| 项 | 值 |
|---|---|
| 设计初稿 | `00-LangSysQuanta-设计初稿.md` `0.5.0-draft` |
| 评审 | `01` 语义评审 / `02` 架构+ADR（ADR-1…30）/ `03` 开发工程 / `04` S-1 计划 / `05` Bootstrap 计划 |
| Bootstrap 最新 tag | `bootstrap-m1d-1b` |
| 最新提交 | `eeffad98`（PR #3 文档迁入）；PR #1 固定点修复、PR #2 QEMU runner |
| doc-lint | `python tools/doc-lint --strict` → 23 files, 0 errors, 0 warnings |
| 分支关系 | 本地 `master` 与 `origin/main` 内容完全一致（0 差异）；`backup/master-pre-sync` 为收敛前快照 |
| 构建 | `./bootstrap/build.sh` 通过（Windows/MSYS） |
| 本机限制 | Windows 无 VT-x（VirtualBox/WSL2/Docker 不可用）；用 `bootstrap/ci/run-qemu.sh`（QEMU TCG，真内核）本地执行 Linux ELF，配合 GitHub Actions |

### 已完成的时间线（摘要）

```text
M0            C seed + hello ELF
M1a           let/算术/if/while
M1b-1         Array[Int]/Array[U8]
M1b-2         函数定义/调用
M1b-3a        enum 标签
M1b-3b        struct
M1b-3c        Slice
M1b-4         read_file/write_file
M1c-0e        seed --run B-LS 解释器
M1c-0a        Slice 参数
M1c-0b        &&/||、位运算、break/continue
M1c-0c-1      tag-only match
M1c-0c-2      enum 负载 + match 绑定
M1c-0d-1      argc/arg_len/arg_byte
M1c-0d-2      动态 Slice 路径
M1c-3a        stage1 编译 hello
M1c-3b-1      stage1 let/算术/return
M1c-3b-2      stage1 if/while + calc
M1d-0a        stage1 多函数 + Int 参数 + 调用
M1d-0b        stage1 Array/Slice 参数与索引
M1d-0c        stage1 struct + tag-only enum/match
M1d-0d        stage1 多字符名字/名字表
U-1           Unicode/UTF-8：源码、字符串、标识符、字符列诊断
U-2           stage1 名字表改为变长字节池（256 字节标识符）
M1d-0e        stage1 内置 I/O + 动态 argv 路径
U-3           一般 Str 值：变量/复制/参数/.len/write/I/O 路径
M1d-1a        stage1 if/while/break/continue + write + 表达式实参
M1d-1b        emit_expr 重构 + stage1 自编译 → stage2
M1d-2         固定点 stage2 == stage3（本机 QEMU + GitHub CI 双验证）
```

---

## 1. 当前可用能力（事实）

### 1.1 seed（C）

- 解析/检查/生成 x86_64 Linux ELF；
- 支持 B-LS：函数（Int/Slice 参数）、数组、struct、enum（负载+match）、
  逻辑/位运算、`break`/`continue`、`read_file`/`write_file`（字面量 + Slice 动态路径）、
  `argc`/`arg_len`/`arg_byte`；
- `seed --run <file.ls> [args...]`：宿主解释执行（Windows 可用）；
- Unicode/UTF-8：源文件必须合法 UTF-8；标识符允许非 ASCII Unicode 标量值；
  字符串为 UTF-8 字节；一般 `Str` 值（变量/复制/参数/write/IO 路径）；
  字符串 `.len` 为字符数，`Slice[U8].len` 为字节数；诊断列按字符（code point）计数；
- `data` 段上限 1MB。

### 1.2 stage1（B-LS 写）

| 文件 | 能力 | 限制 |
|---|---|---|
| `bootstrap/src/main.ls` | hello 子集 | 仅 `write` + `return` |
| `bootstrap/src/arith.ls` | `let`/算术/比较/`return` | 单字母变量；`write` 未正确接入 |
| `bootstrap/src/calc.ls` | `if/else`、`while`、赋值、`write` | 单字母变量；无函数 |
| `bootstrap/src/funcs.ls` | 多函数、Int 参数、调用、`ret`、trampoline | 函数名 ≤8 字符；参数单字母；实参只支持数字/单字母变量；无嵌套调用/数组/struct/输入 I/O |
| `bootstrap/src/slice_stage.ls` | 多函数、Int/Slice 参数、调用、Array 声明、索引读写、`slice()` | 单字母名字；索引子表达式独立非递归；无 struct/enum/输入 I/O；无边界检查 |
| `bootstrap/src/struct_stage.ls` | 在 slice stage 上加 struct 字段偏移/`.field` 读写、enum 标签、tag-only `match` | match arm 仅 `{ return expr; }`；enum 仅 tag-only；无内置 I/O；单字母名字 |
| `bootstrap/src/names_stage.ls` | 名字表/UTF-8 名字；I/O + argv 路径；目标 `if/else/else-if`、`while`、`break/continue`、`write("...")`、表达式实参 | 名字最长 256；参数 ≤6；match arm 仅 return；实参不支持嵌套调用；目标无一般 `Str` |

### 1.3 工具与 CI

```text
tools/doc-lint                 文档一致性（strict 全绿）
tools/checker-spike            W1：views 档案检查（Rust）
bootstrap/ci/run-interp.sh     所有 B-LS 测试 --run
bootstrap/ci/run-linux.sh      编译产物执行 + interp + stage1
bootstrap/ci/run-stage1.sh     hello/arith/calc/funcs/slice/struct/names/unicode/io stage1
bootstrap/ci/run-qemu.sh       无 VT-x/WSL 时用 QEMU(TCG) 真内核跑完整 run-linux.sh
.github/workflows/bootstrap.yml
```

### 1.4 Unicode / 文本约定

| 项 | 约定 |
|---|---|
| 源文件 | 合法 UTF-8；非法 UTF-8 在输入边界报错；当前不含 BOM |
| 标识符 | ASCII 字母/数字/下划线 + 非 ASCII Unicode 标量值（宽松，不要求 XID） |
| 字符串 | UTF-8 字节，`Slice[U8]`；不规范化、不转码 |
| 字符串 `.len` | 字符数（Unicode 标量值）；`"你好".len == 2` |
| `Slice[U8].len` | 字节数（UTF-8 码元数） |
| 诊断位置 | 1 基行号 + 1 基字符列；按 Unicode 标量值计数 |
| 当前实现 | seed 支持一般 `Str` 值（变量/复制/参数/.len/write/IO 路径）；stage1 待补齐 |
| 测试 | `bootstrap/bls/tests/unicode.ls`、`stage1_unicode_names.ls`、`ci/run-interp.sh` |

---

## 2. 待实施任务（严格顺序）

> 当前主线是 **Bootstrap M1d**；S-1 主线在 §3，二者并行但互不阻塞。
> 每项完成条件必须可执行；未过不得进入下一项。

### M1d-0b · stage1 支持 Array / Slice 参数与索引（已完成）

**实现**：`bootstrap/src/slice_stage.ls`；测试 `bootstrap/bls/tests/stage1_slice.ls`。

- [x] stage1 表达式/语句支持 `Array[T, N]` 声明与索引读写；
- [x] stage1 支持 `Slice[T]` 参数（base+len 两槽）；
- [x] `slice(array, off, len)` 构造；
- [x] 输出 ELF 的数据段数组/变量偏移与补丁；
- [x] 用 `--run` 让 stage1 编译该测试；
- [x] CI 执行 stage1 产物，期望退出码 177。

**验收**：stage1 产物退出码 177（Linux CI）；本机用 `llvm-objdump` 确认数组写入、
Slice base/len 传递、`sum` 取 `s[0]+s[1]`（72+105=177）。

### M1d-0c · stage1 支持 struct / enum（已完成）

**实现**：`bootstrap/src/struct_stage.ls`；测试 `bootstrap/bls/tests/stage1_struct_enum.ls`。

- [x] stage1 解析 `struct`/字段访问/字段赋值；
- [x] stage1 解析 `enum` 标签与（至少 tag-only）`match`；
- [x] 输出布局：字段偏移、tag 槽；
- [x] 测试：struct 点访问、enum match 分支。

**验收**：测试程序 `p.x=3; p.y=4; c=Color.Green; match c { Green => return p.x+p.y+170; }`
→ 退出码 177；本机 `llvm-objdump` 确认字段地址、tag 比较和返回路径。

### M1d-0d · stage1 多字符变量/名字表（已完成）

**实现**：`bootstrap/src/names_stage.ls`；测试 `bootstrap/bls/tests/stage1_names.ls`。

- [x] 用变长字节池名字表（`{byte_off, byte_len}` + 字节池）替换单字母变量；
- [x] 变量名长度 > 8 也能解析；
- [x] 函数名表同样去 8 字符限制；
- [x] stage1 自身源码中的 `parse_expr`/`emit_expr` 等名字可被解析。

**验收**：测试程序含 `first_value`/`second_value`/`sum_value`/`add_values`/
`x_coord`/`y_coord`/`view` 等名字 → 退出码 177；`stage1_long_name.ls`
含 256 字节函数名/变量名 → 退出码 177；本机 `llvm-objdump` 确认
函数调用、struct 字段、数组/切片索引与 match 分支均正确。

### M1d-0e · stage1 侧内置 I/O 与动态路径（已完成）

**实现**：`bootstrap/src/names_stage.ls`；测试 `bootstrap/bls/tests/stage1_io.ls`。

- [x] stage1 解析 `read_file`/`write_file`（Slice 路径）；
- [x] stage1 解析 `argc`/`arg_len`/`arg_byte`；
- [x] 输出 ELF 的 runtime 块（argc/argv/路径缓冲）；
- [x] 测试：stage1 用 argv 路径读取输入并写出输出。

**验收**：`stage1_io.ls` 使用 argv[1]/argv[2] 作为输入/输出路径；Linux CI 执行
stage1 产物后 `cmp` 输入/输出文件通过。产物 `PT_LOAD` 修正为 R|W|X。
支持最多 256 字节的 argv 路径复制（测试展开 256 次）；一般 `Str` 值已在 seed 实现。

### M1d-1a · stage1 控制流与表达式实参（已完成）

**实现**：`bootstrap/src/names_stage.ls`；测试 `bootstrap/bls/tests/stage1_control.ls`。

- [x] 目标语言 `if/else/else-if`、`while`、`break`、`continue`；
- [x] `write("...")` 字面量输出；
- [x] 函数实参支持非递归表达式（`add(s, i * 2)`）；
- [x] CI 解释执行 + Linux 执行产物，期望输出 `ctl ok`、退出码 14；
- [ ] 嵌套调用实参、一般 `Str` 变量（留待 M1d-1b）。

### M1d-1 · stage1 自编译（stage1 → stage2）（已实现）

**实现**：`bootstrap/src/names_stage.ls`；`emit_expr` 重构为 a/b1..b3/io/c。

- [x] seed 编译 `bootstrap/src/names_stage.ls` → `stage1`；
- [x] `stage1 --run` 编译自身 → `stage2_selfhost_interpreted`；
- [x] CI：compiled stage1 编译自身 → stage2，再由 stage2 编译 `calc.ls`；
- [x] 修复自身源码子集：嵌套索引、表达式语句、完整关键字匹配、BSS 输出、容量扩容。

**验收**：本机 `seed --run names_stage names_stage` 成功生成 stage2 ELF；
但 compiled stage1 生成的 stage2 入口错误，尚不能执行 `calc.ls`。M1d-1 只能算“生成成功”，
不能算“stage2 可用”。

### M1d-2 · 固定点 `stage2 == stage3`（已完成：本机 QEMU + GitHub CI）

**已完成**：

- [x] 本机验证解释执行 stage1 两次输出逐字节相同；
- [x] Linux CI：compiled stage1 编译自身 → `stage2_self`；
- [x] CI：`stage2_self` 编译自身 → `stage3_self`、`cmp`、`sha256sum` 已接入；
- [x] 本地 Unicorn 模拟器可运行 Linux ELF，用于调试；
- [x] 修复 Array/Slice 元数据偏移 20 位截断；
- [x] 修复 `&&` / `||` 忽略右操作数；
- [x] 修复嵌套循环 `break` 补丁复用；
- [x] 修复除法重复发射 `cqo/idiv`；
- [x] 本机 `stage1 -> stage2 -> stage3`，`cmp stage2 stage3` 返回 0；
- [x] Linux CI 固定点（2026-10-18，PR #1；run 39081629717）：`stage2_self` 与 `stage3_self` SHA-256 均为 `ac6d1344…a1de`。

**最终根因（除法）**：

- `emit_expr_c` 中 `val == 4` 的除法原先发射了两遍 `cqo; idiv rcx`：
  第一遍得到商，第二遍再把商除以除数。`8 / 8` 因此变成 0。
- 这直接破坏了 `name_id` 的 `idx / 8`，导致名字字节池跨 word 写入错位、
  同名 `st` 被重复 intern，最终 `sl_find` 失败并报 `ctl: bad while expr`。
- 已改为只发射一次 `cqo; idiv rcx`；
  `divmod.ls` 回归（`8/8`、`8%8`、`17/5`、`17%5`）预期退出码 132。

**已修复的真实问题汇总**：

- Array/Slice 元数据原布局为 `off:20 | elem:4 | fn:8 | len:32`，偏移被截断到 1MB；
  现布局 `off:28 | elem:4 | fn:6 | len:38`，掩码 `268435455`（256MB），
  `arr_find`/`sl_find` 的 fn 比较改为 `(meta >> 32) & 63`。
- `&&`/`||` 原先只归一化 `rax`、忽略 `rcx`；现分别归一化后 `and`/`or` 合并。
- 循环关闭后移除已补丁的 `break`，避免同深度后续循环重复补丁旧 break。
- 除法 `cqo/idiv` 只发射一次。

**本机验证结果**：

- stage2 成功编译 `hello.ls`、`arr_dbg.ls`、`calc.ls`；
- stage2 生成的 calc 输出 `calc ok`、退出 14；
- `stage1 -> stage2` 与 `stage2 -> stage3` 均成功，`cmp stage2 stage3` 返回 0。
- 按 CI 相同命令用 Unicorn 复验：
  `stage2_self` 与 `stage3_self` 的 SHA-256 均为
  `ac6d13443c657362b7919f8ac773d4e4317b607f2a3c9cd709737556e2f1a1de`；
- GitHub-hosted Linux CI 本次未执行：当前环境无 WSL/Docker/`gh`，且
  `git ls-remote origin` 连接被重置。

**收尾（已完成）**：

- 已推送并合并（PR #1，rebase merge，main `3833800`），GitHub Actions 的固定点与 `sha256sum` 已通过；
- `H-LS-8` 可以更新为 Enforced（依据即本次 CI 结论）。

**补充验证**：

- stage2/stage3 都能编译 `high_offset.ls`，生成程序退出码 177；
- `off:28` 后 16/17/32/64 MB 数据偏移目标均能由 stage1/stage2 编译，
  生成程序退出码 177/178；旧 16 MB 边界已消除；
- 增加编译期守卫：`dlen > 268435455` 时明确报
  `stage1: data layout exceeds 256MB` 并退出 4，不再静默截断；
- `big_offset.ls`（17×1 MB padding，超过旧 16 MB 限制）加入 stage1/2 回归。

**回归测试**：

- `bootstrap/bls/tests/high_offset.ls`：>1 MB 数据偏移；退出码 177。
- `bootstrap/bls/tests/big_offset.ls`：>16 MB 数据偏移（stage1/2 编译）；退出码 177。
- `bootstrap/bls/tests/logic_ops.ls`：`&&`/`||` + 嵌套 Slice 索引；退出码 202。
- `bootstrap/bls/tests/break_nested.ls`：嵌套循环中的 `break`；退出码 103。
- `bootstrap/bls/tests/divmod.ls`：除法/取模；退出码 132。

**验收**：本机 `cmp stage2 stage3` 与 GitHub CI 均已通过（同一 SHA-256），固定点成立。

> **纪律**：不把「本机 cmp 通过」写成「Linux CI 已通过」；不提前更新 `H-LS-8`。

---

## 3. S-1 主线待办（与 Bootstrap 并行）

当前只完成 W1 的档案 A（条件通过）与 `spec/modes.md` 草稿。

### 3.1 档案

- [ ] **档案 C（slab/list/refcount/C 驱动）**：扩展 checker-spike 支持 `#[cap]`/`defer`/unsafe；
      跑 `dossiers/slab/reject.ls` 的 8 个预期错误；写 `results/C-slab.md`；关闭 Q2。
- [ ] **档案 B（递归）**：跑 `dossiers/recursion`；写 `results/B-recursion.md`；关闭 Q3。
- [ ] 档案 A 的 A-2（IR/汇编无 memcpy）、A-5（区域作用域）待 S0′/S1。

### 3.2 规范（S-1 必须）

- [ ] `spec/ub.md`（15 条 UB + oracle + provenance）
- [ ] `spec/effects.md`（效果集 + gate matrix + `Unsafe` 终止）
- [ ] `spec/image.md`（header/段/cap 表/验签/防回滚/loader）
- [ ] `spec/baremetal.md`（属性/asm/link/入口/C 类型映射）
- [ ] `spec/resource.md`（`defer`/泄漏）
- [ ] `spec/cap-context.md`（模块 `#[cap]` + 每模块旋钮）
- [ ] `spec/toolchain.md`（target/SVD/bindgen）
- [ ] `spec/langSysQuanta.ebnf` 最小子集
- [ ] `spec/cost.md`、`spec/trust.md`、`spec/coherence.md` 至少 skeleton

### 3.3 决策队列

- [ ] Q1 视图规则（已关闭，A-views 条件通过）
- [ ] Q2 模块 cap 词法/隔离
- [ ] Q3 有界递归默认值/静态栈
- [ ] Q4 `Unsafe` 终止规则
- [ ] Q5 provenance 模型
- [ ] Q6 C ABI 类型映射
- [ ] Q7 target 矩阵

### 3.4 Go/No-Go

- [ ] 5 条出口条件；见 `04 §7`
- [ ] 三份档案结论
- [ ] 检查器 spike 对 reject 零漏过
- [ ] `doc-lint --strict` 全绿

---

## 4. 已知限制 / 风险（不要遗忘）

| # | 限制 | 影响 |
|---|---|---|
| 1 | stage1 funcs 实参只支持数字/单字母变量 | 不能编译 `add(x+1, y)` 或嵌套调用 |
| 2 | stage1 名字表最长 256 字节、参数最多 6 个 | 超长名字会截断/无法解析 |
| 3 | stage1 已具备 Array/Slice/struct/enum/名字表/内置 I/O | 自编译主要剩控制流/字符串值等缺口 |
| 4 | B-LS 解释器递归会覆盖全局局部槽 | 编译器代码必须避免递归 |
| 5 | 动态路径缓冲 255 字节、无截断检查 | 长路径可能越界 |
| 6 | `arith.ls` 的 `write` 发射顺序不完整 | 不作为最终 stage1 |
| 7 | 本机无 VT-x，不能跑 VirtualBox/WSL2/Docker | 改用 `bootstrap/ci/run-qemu.sh`（QEMU TCG）本地执行 Linux ELF |
| 8 | M1d-2 固定点已由 GitHub CI 验证（PR #1，run 39081629717） | 已关闭 |
| 13 | `high_offset.ls`/`big_offset.ls` 在 stage2/stage3 下已能编译并退出 177 | 已修复 |
| 14 | Array/Slice 元数据偏移 `off:28`（256MB）；超过时编译期报错；struct 字段偏移仍为 20 位 | 更大需改元数据与寻址方式 |
| 9 | 标识符宽松接受非 ASCII 标量值，未实现完整 Unicode XID；不做 NFC/NFD 规范化 | 可能与未来 L-Sys 标识符规则不一致 |
| 10 | 当前不支持 UTF-8 BOM、反斜杠 u/x 转义、grapheme cluster 计数 | 需在规范扩展时补齐 |
| 11 | stage1 尚未实现一般 `Str` 值 | M1d-1 自编译前需补齐 |
| 12 | `Str` 不可变、不可索引/切片/比较/返回；不做 Unicode 规范化 | 语言能力仍为最小集 |

---

## 5. 常用命令

```bash
# 文档一致性
python tools/doc-lint --strict

# 构建 seed + 所有 B-LS 测试 + stage1 二进制
./bootstrap/build.sh

# B-LS 解释器测试（Windows 可用）
./bootstrap/ci/run-interp.sh

# stage1 测试（解释执行 + Linux 编译执行）
./bootstrap/ci/run-stage1.sh

# 本地 QEMU 真内核 CI（无 VT-x/WSL/Docker 时使用；含 stage2 == stage3 固定点）
./bootstrap/ci/run-qemu.sh

# 手工运行解释器
./bootstrap/seed/seed.exe --run bootstrap/bls/tests/calc.ls

# 手工运行 stage1（解释）
./bootstrap/seed/seed.exe --run bootstrap/src/calc.ls \
  bootstrap/bls/tests/calc.ls bootstrap/build/calc_stage1
```

---

## 6. 下次从这里开始

**M1d-2 已收尾**：`stage2 == stage3` 已由本机 QEMU（真内核）与 GitHub CI（PR #1，
run 39081629717）双重验证，main 上的 `3833800` 跑完整 CI 全绿；两处 SHA-256 与 Unicorn
复验结果一致（`ac6d1344…a1de`）。

**已完成修复（已合并到 main `3833800`）**：

- Array/Slice 元数据偏移从 20 位扩到 28 位（`names_stage.ls`），支持 256MB；
  超过 256MB 时编译期报错（不静默截断）。
- `&&` / `||` 改为归一化左右操作数后 `and`/`or` 合并。
- 循环关闭后压缩并移除已补丁的 `break`，避免同深度重复补丁。
- 除法 `cqo; idiv rcx` 只发射一次；原先重复发射导致 `8/8 == 0`，
  进而破坏 `name_id` 的 `idx/8` 与字节池。

**CI 实测结果**（run 39081629717）：

- `bootstrap CI: M0/M1a/M1b + Unicode (UTF-8) OK`；`interp: all B-LS tests passed`；
- `PASS fixed point: stage2 == stage3`，两文件 SHA-256 均为 `ac6d1344…a1de`；
- stage2 编译 `high_offset.ls` / `big_offset.ls` → 退出 177；
- `logic_ops` 202、`break_nested` 103、`divmod` 132。

**下一步（按顺序）**：

1. 把 `H-LS-8` 更新为 Enforced（依据 run 39081629717 的 `cmp` + `sha256sum`）；
2. 回到 L-Sys 主线（§3 S-1）。

**已完成：分叉收敛（2026-10-18）**

`master` 与 `origin/main` 原本是**无共同祖先**的两条历史（`git merge-base` 为空），
所以之前的“领先 83 / 落后 32”只是两个无关谱系的相对计数。收敛步骤：

- PR #3 把 master 独有的 22 份文档（00–05、`spec/`、`dossiers/`、`results/`、4 份 README）
  按字节原样迁入 main（合并点 `eeffad98`），`doc-lint` 23 files / 0 errors；
- 本地用 `git merge --allow-unrelated-histories -X theirs origin/main` 收敛；
  5 个 add/add 冲突（`build.sh`、`ci/{run-interp,run-linux,run-stage1}.sh`、`tools/doc-lint`）
  逐个取 main 版本，并补回 `100755` 执行位；
- 结果：`git diff origin/main master` 为 **0 行差异**、mode 一致、工作区干净；
- `backup/master-pre-sync`（`b1e835a`）保留收敛前的完整历史，可随时回退；
- 收敛后重跑 `bootstrap/ci/run-qemu.sh` → PASS（含固定点）。

**本轮新增资产（由 PR #2 引入）**：

- `bootstrap/ci/run-qemu.sh`、`bootstrap/ci/qemu/{mkinitramfs.py,init,guest-run.sh,readelf-shim}`；
- `bootstrap/README.md` 的 QEMU 章节；`bootstrap/build.sh` 的 `SKIP_SEED_CC=1` 开关。

**超过 256MB 的后续路线（未实现）**：

- 当前 `off:28` 只是元数据打包上限；stage1 生成的数据引用使用 RIP-relative
  `disp32`，实际可寻址范围约 ±2GB。
- 阶段 1（可到约 2GB）：把 Array/Slice 表改成独立 64 位 `off` 槽（或 `off:31`），
  不再把 offset 与 elem/fn/len 打进同一个 Int；代码生成可保持不变。
- 阶段 2（>2GB）：RIP-relative `disp32` 不够，需要改用基址寄存器
  （如 r15=数据基址，`[r15+off32]`）、`movabs` 绝对地址，或拆分多个数据段/
  多个 PT_LOAD；同时调整 loader/runtime 与 ABI。
- 在需要之前保持 256MB 编译期守卫，避免静默生成错误 ELF。

> 纪律（历史）：本机 `cmp` 已通过但 CI 未复验时，不得写成「CI 固定点通过」；
> 本次已由 run 39081629717 复验，纪律已满足。
