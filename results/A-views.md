# A · 零拷贝视图（dossiers/views）

状态：未评审
负责人：—
复核：—
commit：—
命令：`python tools/checker-spike/run.py dossiers/views`（计划）
证据：—

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| A-1 | `parse` 被接受 | 未评审 | — |
| A-2 | `parse` 无 `memcpy` | 未评审 | — |
| A-3 | `Cursor` 可返回 | 未评审 | — |
| A-4 | `IoVec` 无复制 | 未评审 | — |
| A-5 | 源区域结束后使用被拒 | 未评审 | — |
| A-6 | `BadCursor` 被拒 | 未评审 | — |
| A-7 | 跨模块 `recover` 被拒 | 未评审 | — |
| A-8 | unsafe ≤ 1 | 未评审 | — |

## 结论

- 对 LS-P10 的影响：
- 需要修订的文档/ADR：
- 后续动作：
