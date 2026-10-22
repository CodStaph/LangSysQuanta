# 档案 B · 设备树递归与有界递归

> 权威描述：[`03-开发与工程实践评审.md`](../../03-开发与工程实践评审.md) §4.1。
> 对应决策：Q3（递归上界/静态栈）；D31；`H-LS-29`。

## 目标

证明 kernel 在「默认禁递归」下仍能表达树遍历，并验证 `#[recursion(bound=N)]` 逃生舱：

- `accept_stack.ls`：显式栈，安全子集，0 unsafe；
- `accept_rec.ls`：有界递归，静态栈上界检查通过；
- `reject.ls`：无 `bound` 的递归、超预算的 `bound` 必须被拒。

## 文件

| 文件 | 内容 |
|---|---|
| `accept_stack.ls` | `walk`：显式 `Array[USize, 64]` |
| `accept_rec.ls` | `walk_rec`：`#[recursion(bound = 8)]` |
| `accept_ai_stack.ls` | B-7：AI 一次生成的显式栈版（未修改即通过检查） |
| `accept_ai_rec.ls` | B-7：AI 一次生成的有界递归版（未修改即通过检查） |
| `reject.ls` | 无 bound、`bound = 64`、深树负例 |

## 验收清单

| # | 检查 | 判据 | 结果 | 证据 |
|---|---|---|---|---|
| B-1 | 显式栈版 | 安全子集接受，0 unsafe | **通过** | `accept_stack.ls`：`diagnostics=0 unsafe=0` |
| B-2 | 无分配 | `walk` 无 `Alloc` 效果 | **通过** | 两份 accept 文件中无 `Alloc`/`alloc` |
| B-3 | 边界 | 深树返回 `Error.TooDeep`，不越界 | **通过** | `accept_stack.ls:36` 的 `Err(Error.TooDeep)` 分支 |
| B-4 | 有界递归 | 静态栈上界 ≤ `stack_bound`（8KB） | **通过** | `accept_rec.ls`：`bound=8` → 8×128 B = 1 KiB ≤ 8 KiB |
| B-5 | 递归负例 | `#[recursion(bound=64)]` 超预算被拒 | **通过** | `reject.ls`：`E-LS-STACK` |
| B-6 | C 移植 | 同一 C 递归 walker 的移植 diff ≤ 50 行且语义等价 | **延后到 S1** | `04 §8` 第 3 条砍单规则 |
| B-7 | 可读性 | 两种版本都能被 AI 一次生成通过检查 | **通过** | `accept_ai_stack.ls` / `accept_ai_rec.ls`：一次生成、未修改、零诊断 |

## 失败后果

- B-1 需要 unsafe：安全子集表达力不足（`LS-01`）；
- B-4/B-5 不成立：把「禁递归」改为「默认禁 + 有界递归默认开启」，重估静态栈分析；
- B-6 不可移植：kernel 迁移成本过高，需在 03 §2 记录。

## 结论

**通过**（B-6 按 `04 §8` 砍单规则延后到 S1）。完整产物见 [`results/B-recursion.md`](../../results/B-recursion.md)；
Q3（有界递归默认值 / 静态栈）已关闭。

语义侧（T4d / UB-13）的运行时预算模型见 [`results/T4d-stack.md`](../../results/T4d-stack.md)：
`lean/LSys/Stack.lean` 证明「预算内不溢出」，并证「静态 `E-LS-STACK` 检查通过 ⇒ 帧预算足够」
（本文 B-4 的 8×128 B ≤ 8 KiB 与该定理的 `bound = 8` 实例对齐）。
