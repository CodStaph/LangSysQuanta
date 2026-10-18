# B · 递归与有界递归（dossiers/recursion）

状态：未评审
负责人：—
复核：—
commit：—
命令：`python tools/checker-spike/run.py dossiers/recursion`（计划）
证据：—

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| B-1 | 显式栈版 0 unsafe | 未评审 | — |
| B-2 | 无 `Alloc` | 未评审 | — |
| B-3 | 深树返回 `Error.TooDeep` | 未评审 | — |
| B-4 | 有界递归静态栈 ≤ 8KB | 未评审 | — |
| B-5 | `bound=64` 被拒 | 未评审 | — |
| B-6 | C walker 移植 diff ≤ 50 行 | 未评审 | — |
| B-7 | AI 一次生成通过 | 未评审 | — |

## 结论

- 对 kernel 递归默认值的影响：
- 需要修订的文档/ADR：
- 后续动作：
