# MEMORY · LangSysQuanta 项目记忆

> **用途**：跨会话交接。记录当前基线、已完成能力、待实施任务的**严格顺序**与验收方式。
> **规则**：每完成一个任务，更新本文件并打 tag；不把「计划」写成「已完成」。
> **最近更新**：`bootstrap` 到 M1d-0a 完成。

---

## 0. 当前基线

| 项 | 值 |
|---|---|
| 设计初稿 | `00-LangSysQuanta-设计初稿.md` `0.5.0-draft` |
| 评审 | `01` 语义评审 / `02` 架构+ADR（ADR-1…30）/ `03` 开发工程 / `04` S-1 计划 / `05` Bootstrap 计划 |
| Bootstrap 最新 tag | `bootstrap-m1d-0a` |
| 最新提交 | `7c3703d feat(bootstrap): M1d-0a stage1 multi-function + Int params + calls` |
| doc-lint | `python tools/doc-lint --strict` → 21 files, 0 errors, 0 warnings |
| 构建 | `./bootstrap/build.sh` 通过（Windows/MSYS） |
| 本机限制 | Windows，不能执行 Linux ELF；执行验证交给 Linux CI |

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
```

---

## 1. 当前可用能力（事实）

### 1.1 seed（C）

- 解析/检查/生成 x86_64 Linux ELF；
- 支持 B-LS：函数（Int/Slice 参数）、数组、struct、enum（负载+match）、
  逻辑/位运算、`break`/`continue`、`read_file`/`write_file`（字面量 + Slice 动态路径）、
  `argc`/`arg_len`/`arg_byte`；
- `seed --run <file.ls> [args...]`：宿主解释执行（Windows 可用）；
- `data` 段上限 1MB。

### 1.2 stage1（B-LS 写）

| 文件 | 能力 | 限制 |
|---|---|---|
| `bootstrap/src/main.ls` | hello 子集 | 仅 `write` + `return` |
| `bootstrap/src/arith.ls` | `let`/算术/比较/`return` | 单字母变量；`write` 未正确接入 |
| `bootstrap/src/calc.ls` | `if/else`、`while`、赋值、`write` | 单字母变量；无函数 |
| `bootstrap/src/funcs.ls` | 多函数、Int 参数、调用、`ret`、trampoline | 函数名 ≤8 字符；参数单字母；实参只支持数字/单字母变量；无嵌套调用/数组/struct/输入 I/O |

### 1.3 工具与 CI

```text
tools/doc-lint                 文档一致性（strict 全绿）
tools/checker-spike            W1：views 档案检查（Rust）
bootstrap/ci/run-interp.sh     所有 B-LS 测试 --run
bootstrap/ci/run-linux.sh      编译产物执行 + interp + stage1
bootstrap/ci/run-stage1.sh     hello/arith/calc/funcs stage1
.github/workflows/bootstrap.yml
```

---

## 2. 待实施任务（严格顺序）

> 当前主线是 **Bootstrap M1d**；S-1 主线在 §3，二者并行但互不阻塞。
> 每项完成条件必须可执行；未过不得进入下一项。

### M1d-0b · stage1 支持 Array / Slice 参数与索引

**目标**：stage1 能编译如下程序：

```ls
fn sum(s: Slice[U8]) -> Int {
    return s[0] + s[1];
}
fn main() -> Int {
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = 72;
    buf[1] = 105;
    let s: Slice[U8] = slice(buf, 0, 2);
    return sum(s);
}
```

**工作项**：

- [ ] stage1 表达式/语句支持 `Array[T, N]` 声明与索引读写；
- [ ] stage1 支持 `Slice[T]` 参数（base+len 两槽）；
- [ ] `slice(array, off, len)` 构造；
- [ ] 输出 ELF 的数据段数组/变量偏移与补丁；
- [ ] 用 `--run` 让 stage1 编译该测试；
- [ ] CI 执行 stage1 产物，期望退出码 177。

**验收**：`bootstrap/bls/tests/stage1_slice.ls` → 退出码 177；`run-stage1.sh` 新增用例。

### M1d-0c · stage1 支持 struct / enum

**工作项**：

- [ ] stage1 解析 `struct`/字段访问/字段赋值；
- [ ] stage1 解析 `enum` 标签与（至少 tag-only）`match`；
- [ ] 输出布局：字段偏移、tag 槽；
- [ ] 测试：struct 点访问、enum match 分支。

**验收**：stage1 编译一个 struct+enum 测试，退出码与输出符合预期；CI 执行。

### M1d-0d · stage1 多字符变量/名字表

**工作项**：

- [ ] 用名字表（`Array[U8]` + 偏移/长度）替换单字母变量；
- [ ] 变量名长度 > 8 也能解析；
- [ ] 函数名表同样去 8 字符限制；
- [ ] stage1 自身源码中的 `parse_expr`/`emit_expr` 等名字可被解析。

**验收**：stage1 编译含多字符变量/函数名的测试，退出码正确。

### M1d-0e · stage1 侧内置 I/O 与动态路径

**工作项**：

- [ ] stage1 解析 `read_file`/`write_file`（Slice 路径）；
- [ ] stage1 解析 `argc`/`arg_len`/`arg_byte`；
- [ ] 输出 ELF 的 runtime 块（argc/argv/路径缓冲）；
- [ ] 测试：stage1 用 argv 路径读取输入并写出输出。

**验收**：stage1 产物可读 `argv[0]`、写 `argv[1]`；CI 验证文件内容。

### M1d-1 · stage1 自编译（stage1 → stage2）

**前置**：M1d-0a…0e 全部完成。

**工作项**：

- [ ] seed 编译 `bootstrap/src/*.ls` → `stage1`；
- [ ] `stage1` 编译 `bootstrap/src/*.ls` → `stage2`；
- [ ] 用 stage2 编译 hello/calc，产物可运行；
- [ ] 修复 stage1 自身源码只用其支持子集的问题。

**验收**：`stage2` 可执行；`stage2` 能编译 `calc.ls` 且退出码 14。

### M1d-2 · 固定点 `stage2 == stage3`

**工作项**：

- [ ] `stage2` 编译自身 → `stage3`；
- [ ] 逐位比较 `stage2` 与 `stage3`；
- [ ] 记录构建指纹；
- [ ] 更新 `05` 与 `H-LS-8` 证据。

**验收**：`cmp stage2 stage3` 通过；CI 固化。

> **禁止**：在 M1d-1 未真实通过前，把 M1d-2 写成「固定点成立」或更新 `H-LS-8` 为 Enforced。

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
| 2 | stage1 函数名 ≤8 字符、参数单字母 | 不能解析 stage1 自身源码 |
| 3 | stage1 无 Array/Slice/struct/enum/内置 I/O | 自编译被阻塞 |
| 4 | B-LS 解释器递归会覆盖全局局部槽 | 编译器代码必须避免递归 |
| 5 | 动态路径缓冲 255 字节、无截断检查 | 长路径可能越界 |
| 6 | `arith.ls` 的 `write` 发射顺序不完整 | 不作为最终 stage1 |
| 7 | 本机不能执行 Linux ELF | 执行验证依赖 CI |
| 8 | M1d-1/2 未开始 | 禁止声称已自举 |

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

# 手工运行解释器
./bootstrap/seed/seed.exe --run bootstrap/bls/tests/calc.ls

# 手工运行 stage1（解释）
./bootstrap/seed/seed.exe --run bootstrap/src/calc.ls \
  bootstrap/bls/tests/calc.ls bootstrap/build/calc_stage1
```

---

## 6. 下次从这里开始

**下一任务**：`M1d-0b`。

建议第一步：

1. 复制 `bootstrap/src/funcs.ls` → `bootstrap/src/slice_stage.ls`；
2. 在 stage1 中加 `Array`/`Slice` 声明与索引（复用 seed 的 codegen 逻辑）；
3. 用 `--run` 编译 `bootstrap/bls/tests/stage1_slice.ls`；
4. CI 执行 stage1 产物，期望 177；
5. 完成后更新本文件与 `05`，打 tag `bootstrap-m1d-0b`。

> 纪律：不把「代码能编译」写成「自举完成」；任何 `stage2 == stage3` 必须来自真实 `cmp`。
