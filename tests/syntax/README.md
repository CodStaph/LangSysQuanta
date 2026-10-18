# tests/syntax/ · EBNF v2.1 语法冻结语料

> **上位**：[`04-S-1-执行计划.md`](../../04-S-1-执行计划.md) §14.6（语法冻结门）。
> **权威语法**：[`spec/langSysQuanta.ebnf`](../../spec/langSysQuanta.ebnf)。
> **识别器**：[`tools/ebnf-parse`](../../tools/ebnf-parse)（Earley recognizer，测试工具，不是 S0′ parser）。

## 门禁

语法冻结要求：

> EBNF 可解析 `00 §5` 全部代码块 + 全部 B-LS 测试；
> 未过不得导出 GBNF，不得开始 S0′ parser。

## 语料

### `00-s5/`（13 块）

从 `00 §5.1–§5.11` 原样抽取：

| 文件 | 00 小节 |
|---|---|
| `s5-01-module-profile.ls` | §5.1 module/profile/attrs |
| `s5-02-declarations.ls` | §5.2 struct/enum/fn |
| `s5-02-declarations-2.ls` | §5.2 trait/impl |
| `s5-03-region-alloc-borrow.ls` | §5.3 region/alloc/borrow |
| `s5-04-mode-types.ls` | §5.4 mode 类型 |
| `s5-05-unsafe-lowlevel.ls` | §5.5 unsafe/extern/asm/newtype |
| `s5-06-effects.ls` | §5.6 效果/契约 |
| `s5-07-concurrency-irq-dma.ls` | §5.7 spawn/irq/shared |
| `s5-08-panic-error-drop.ls` | §5.8 `?`/defer |
| `s5-09-ring.ls` | §5.9 环形缓冲安全版 |
| `s5-09-ring-2.ls` | §5.9 环形缓冲 unsafe 版 |
| `s5-10-comptime-attrs.ls` | §5.10 comptime/bitfield |
| `s5-11-match-closure.ls` | §5.11 match/closure/for |

说明：`00` 是本地保留文档，不随仓库发布；这里的片段是**语法测试语料**，
以本地 `00` 为准提取。片段中的 `...` 在识别前规范化为 `todo()`。

### B-LS

`bootstrap/bls/tests/*.ls` 全部 31 个 B-LS 测试原样纳入，不复制。

## 运行

```bash
python tests/syntax/run.py
```

或直接：

```bash
python tools/ebnf-parse tests/syntax/00-s5/*.ls bootstrap/bls/tests/*.ls
```

输出每个文件一行 `PASS`/`FAIL`；全部通过退出码为 0。

## 识别器边界

`tools/ebnf-parse`：

- 直接读取 `spec/langSysQuanta.ebnf`，用 Earley 算法做识别；
- 词法产生式折叠为 token 类（`ident`/`int`/`str`/`char`），注释与空白由 lexer 处理；
- 不建 AST、不做名称解析/类型检查；
- `...` 归一化为 `todo()`；
- 语法 v2.1 为解析 00 §5 新增：tuple struct、bitfield 整数字段宽度、
  `ensures ... => ...`、`spawn expr`、`mode expr`、`mode T` 简写、无体 `fn` 声明；
- 这些是**语法层**修复；语义/类型规则仍以 `spec/*.md` 为准。

## 当前结果（2026-10-18）

```text
syntax: 13 00-§5 blocks + 31 B-LS tests = 44 files
PASS ... (all)
```

`00 §5` 块与 B-LS 测试均通过，语法冻结门满足。GBNF 导出的差分仍属 W4 后续。
