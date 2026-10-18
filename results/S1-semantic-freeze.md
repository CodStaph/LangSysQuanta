# S-1 语义冻结审计

日期：2026-10-18
上位：[`04 §14.6`](../04-S-1-执行计划.md)、[`spec/t4-proof.md`](../spec/t4-proof.md) 的语义冻结审计
结论：**语义冻结门未通过**（可作为后续评审基线，不能宣称冻结）

## 门禁条件

| 条件 | 状态 | 证据/缺口 |
|---|---|---|
| `Σ=(Γ,Λ,M,H)` + `⊣ Σ'` | **通过** | `spec/semantics.md` §2、`t4-proof.md` 的静态规则章节 |
| M2 L-Adequacy | **条件通过** | `t4-proof.md` 的 M2 章节；S10 依赖 `CAP_ALLOC_OK`、S11 依赖 T1a |
| M2 Preservation / L4 | **条件通过** | M2 Preservation 章节；I1–I8 对 S2–S12 |
| M3 core（call/return/frame/drop） | **条件通过** | M3 章节；`CAPS`/T1a |
| M3 完整（泛型/区域多态/递归/动态分派/跨模块） | **未通过** | 语义冻结章节的 M3 完整性 |
| Progress / `L-NoStuck` | **未通过** | 语义冻结章节的 Progress 骨架 |
| R1–R8 正负例 | **未通过** | R5/R6/R8 缺；语义冻结章节的覆盖表 |
| T4a | **未证明** | Progress/完整 M3/M4-M5 缺 |

## R1–R8 覆盖

| 规则 | 正例 | 负例 | 状态 |
|---|---|---|---|
| R1 | `dossiers/slab/accept.ls` | `E-LS-MOVE-use-after-move.ls` | 有 |
| R2 | 借用代理（部分） | `dossiers/views/reject.ls` | 部分 |
| R3 | `accept-unsafe-termination.ls` | `E-LS-UNIQ-val-alias-field.ls` | 有 |
| R4 | `dossiers/views/accept.ls` | region escape 负例 | 有 |
| R5 | — | — | **缺** |
| R6 | — | — | **缺** |
| R7 | `accept-unsafe-termination.ls` | `E-LS-CAPCTX`/`E-LS-EFFECT-*` | 有（spike） |
| R8 | — | — | **缺** |

## 条件前提

- `CAP_ALLOC_OK`：gate matrix allocator 假设（`L-AllocCap`），不在语言内核证明；
- `T1a-mono`：区域变量 site-bound；区域多态/高阶未形式化；
- `CAPS(f)`：gate matrix/模块 cap 入口检查；
- S12：`iso` 与 `box` 共用 core mode `uniq`，已收口；域转移仍由 R8。

## 下一步（按顺序）

1. 补 R5/R6/R8 的正负例（先在 `ls-sem` 或 checker-spike 可执行）；
2. 写 `L-NoStuck` 的块闭包归纳（S9/S11/S14 的 `→*`）；
3. M3 完整：单态化、区域多态、递归、`ref[Trait]`、跨模块；
4. 复核 `CAP_ALLOC_OK`/`T1a-mono`/`CAPS` 前提；
5. 重新跑本审计；全绿后才可标记“语义冻结”。

> 本文件不是 T4a 的证明；它只是把“冻结门未过”的原因固定下来，避免把计划写成结论。
