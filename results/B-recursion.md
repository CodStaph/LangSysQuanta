# B · 递归与有界递归（dossiers/recursion）

```text
状态：条件通过（B-1..B-5 通过；B-6/B-7 缺证据）
负责人：—
复核：— / 2026-10-18
commit：a47437e（评审基线；本轮改动见 PR）
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
| B-6 | C walker 移植 diff ≤ 50 行 | 未评审 | 缺 C 参考实现与 diff 记录 |
| B-7 | AI 一次生成通过 | 未评审 | 缺 §10 四臂评测的生成记录 |

原始输出：

```text
PASS dossiers/recursion\accept_rec.ls diagnostics=0 unsafe=0 zero_copy_source=true
PASS dossiers/recursion\accept_stack.ls diagnostics=0 unsafe=0 zero_copy_source=true
  OK       E-LS-DIAL
  OK       E-LS-RECURSION
  OK       E-LS-STACK
PASS dossiers/recursion\reject.ls expected=3 actual=3
SUMMARY PASS
```

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
  1. 补 B-6（C walker diff）与 B-7（AI 生成记录）证据，之后可转「通过」；
  2. 两项齐备后再关闭 **Q3**（有界递归默认值 / 静态栈），本文件暂不宣称关闭；
  3. 进入档案 C（W2，slab）：还缺 `E-LS-PROV` / `E-LS-MOVE` / `E-LS-LEAK` / `E-LS-CAPCTX` / `E-LS-DIAL` 触发路径。
