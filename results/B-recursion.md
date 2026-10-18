# B · 递归与有界递归（dossiers/recursion）

```text
状态：通过（B-6 按 04 §8 砍单规则延后到 S1）
负责人：—
复核：— / 2026-10-18
commit：本轮 PR（checker-spike dossier B + 本文件）
命令：cargo run --quiet -- dossiers/recursion
证据：见下表
```

## 逐项

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| B-1 | 显式栈版 0 unsafe | 通过 | `accept_stack.ls`：`PASS … diagnostics=0 unsafe=0`；源码中 `unsafe` 出现 0 次 |
| B-2 | 无 `Alloc` | 通过 | `accept_stack.ls` / `accept_rec.ls` 中无 `Alloc` / `alloc` |
| B-3 | 深树返回 `Error.TooDeep` | 通过 | `accept_stack.ls:36`：`if sp == DT_MAX_DEPTH { return Err(Error.TooDeep); }` |
| B-4 | 有界递归静态栈 ≤ 8KB | 通过 | `accept_rec.ls`：`#[recursion(bound = 8)]` → 8 × 128 B = 1 KiB ≤ 8 KiB，`diagnostics=0` |
| B-5 | `bound=64` 被拒 | 通过 | `reject.ls`：`E-LS-STACK: fn too_deep recursion bound 64 exceeds the 8192-byte static stack budget` |
| B-6 | C walker 移植 diff ≤ 50 行 | **延后到 S1** | `04 §8` 第 3 条砍单规则；已登记到 `results/s1-review.md` |
| B-7 | AI 一次生成通过检查 | 通过 | `accept_ai_stack.ls` / `accept_ai_rec.ls`：一次生成、未修改，`diagnostics=0`（下节） |

原始输出：

```text
PASS dossiers/recursion\accept_ai_rec.ls   diagnostics=0 unsafe=0 zero_copy_source=true
PASS dossiers/recursion\accept_ai_stack.ls diagnostics=0 unsafe=0 zero_copy_source=true
PASS dossiers/recursion\accept_rec.ls      diagnostics=0 unsafe=0 zero_copy_source=true
PASS dossiers/recursion\accept_stack.ls    diagnostics=0 unsafe=0 zero_copy_source=true
  OK       E-LS-DIAL / E-LS-RECURSION / E-LS-STACK
PASS dossiers/recursion\reject.ls expected=3 actual=3
SUMMARY PASS
```

## B-7 的生成记录

- 输入：`dossiers/recursion/README.md` 的「目标」与「文件」两节（设备树遍历 + 两种方案）；
- 过程：**一次**生成两个文件，未做任何修改或重试；
- 产物：`accept_ai_stack.ls`（显式 `Array[USize, 32]` 栈，`Err(Error.TooDeep)` 越界保护）、
  `accept_ai_rec.ls`（`#[recursion(bound = 8)]` + `requires depth < 8`）；
- 校验：`tools/checker-spike` 对两者均为 `diagnostics=0 unsafe=0`；
- 局限：检查器目前只做子集检查（不含完整类型检查），因此「通过」≠ 可编译；
  这一局限本身已记入 `spec/ub.md` / `tools/checker-spike/README.md` 的「边界」节。

## 本轮新增的检查（checker-spike）

| 错误码 | 语义 | 实现要点 |
| --- | --- | --- |
| `E-LS-RECURSION` | 函数直接调用自身且没有 `#[recursion(bound = N)]` | `analyze`：扫描函数体中 `name` 紧跟 `(` 的相邻 token |
| `E-LS-STACK` | `bound × 128 B ≥ 8 KiB`（保守帧模型，`03 §4.1`） | `analyze`：`FRAME_BYTES = 128`、`STACK_BUDGET = 8192` |
| `E-LS-DIAL` | 使用 `#[bounds(off)]` 却缺少 `requires` / `ensures` | `analyze`：`FnDef.has_contract` 标记（由 `parse_fn` 置位） |

配套改动：

- `parse_attrs` 现在保留**完整属性文本**（`recursion( bound = 64 )`、`bounds(off)`），此前只保留属性名，参数被丢弃；
- `FnDef` 增加 `attrs` / `has_contract` 字段；
- 目录扫描从固定 `accept.ls` / `reject.ls` 改为按前缀匹配 —— 否则 `accept_rec.ls`、`accept_stack.ls` 永远不会被检查。

## 结论

- 对设计的影响：kernel 的「默认禁递归 + `#[recursion(bound)]` 逃生舱」**可执行**。
  在 8 KiB 栈预算与 128 B/帧的保守模型下，`bound ≤ 63` 通过、`bound = 64` 被拒（B-4 / B-5）。
- 需要修订的文档/ADR：
  - `00 §6.7` 补 `E-LS-DIAL`（`#[bounds(off)]` 必须有 contract）的条文；
  - `03 §4.1` 注明「spike 用 128 B/帧常量占位，正式实现按真实帧布局计算」。
- 后续动作：
  1. **B-6** 按 `04 §8` 第 3 条延后到 S1（已登记到 `results/s1-review.md` 砍单记录）；
  2. **Q3 关闭**：有界递归默认值 + 静态栈预算已有可执行证据（B-4/B-5）；
  3. 进入档案 C（W2，slab）：还缺 `E-LS-PROV` / `E-LS-MOVE` / `E-LS-LEAK` / `E-LS-CAPCTX` 触发路径。
