# C · slab / 侵入式链表 / refcount / C 驱动（dossiers/slab）

状态：未评审
负责人：—
复核：—
commit：—
命令：`python tools/checker-spike/run.py dossiers/slab`（计划）
证据：—

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| C-1 | slab 安全 API；unsafe ≤ 3 | 未评审 | — |
| C-2 | 无隐藏分配 / O(1) | 未评审 | — |
| C-3 | 双重释放被拒 | 未评审 | — |
| C-4 | 越界/对齐负例被拒 | 未评审 | — |
| C-5 | fuzz 10^6 无 UAF | 未评审 | — |
| C-6 | refcount/RCU 测试 | 未评审 | — |
| C-7 | C 移植 ≤ 5 unsafe | 未评审 | — |
| C-8 | `defer` 无泄漏 | 未评审 | — |
| C-9 | ISR 预算 | 未评审 | — |
| C-10 | C 互操作 | 未评审 | — |

## 结论

- unsafe 原语清单与总数：
- 是否需要 `LS-25`：
- 后续动作：
