# S-1 语义冻结审计

日期：2026-10-19
上位：[`04 §14.6`](../04-S-1-执行计划.md)、[`spec/f0.md`](../spec/f0.md)、
[`spec/feature-coverage.md`](../spec/feature-coverage.md)、
[`spec/t4-proof.md`](../spec/t4-proof.md) 的语义冻结审计。

> **口径（W0）**：R1–R8 的正负例覆盖**全语言**（含 `shared`/`atom`/`spawn`）；
> **T4a 只覆盖 `F0`**。两者不是同一个范围，见 [`spec/f0.md`](../spec/f0.md) §5。

## 结论

| 层 | 判定 | 说明 |
|---|---|---|
| **L1 规范冻结** | **文档就绪，门禁未通过** | 规则、`F0`、语料矩阵、`Σ'` 都在；缺口是**可执行性**：R2/R5/R6/R8 的 14 条语料仍在 `pending/`，检查器未实现 |
| **L2 定理冻结（T4a）** | **未通过** | Progress / `L-NoStuck` 未证；完整 M3 不在本门（见 `f0.md` §2） |
| **L3 机械化** | **未开始** | 本机 Lean 工具链网络阻塞；不排期 |

**不得**把本文件写成「语义冻结通过」或「T4a 已证」。

## 门禁条件

| 条件 | 状态 | 证据/缺口 |
|---|---|---|
| `Σ=(Γ,Λ,M,H)` + `⊣ Σ'` | **通过** | `spec/semantics.md` §2 |
| M2 L-Adequacy | **条件通过** | `t4-proof.md` 的 M2 章节；S10/S11 依赖 `CAP_ALLOC_OK` / T1a |
| M2 Preservation / L4 | **条件通过** | M2 Preservation 章节；I1–I8 对 S2–S12 |
| M3 core（call/return/frame/drop） | **条件通过** | M3 章节；`CAPS` / T1a |
| M3 完整（泛型/区域多态/递归/动态分派/跨模块） | **不在 L1** | `F0` 已排除；登记 `H-LS-18` / `H-LS-29` / `H-LS-5` / ADR-17 |
| Progress / `L-NoStuck` | **未通过（L2）** | 块闭包归纳未写；`t4-proof.md` 的 Progress 骨架 |
| R1–R8 正负例可执行 | **未通过** | 语料齐备；R2/R5/R6/R8 在 `pending/`，检查器未实现 |
| T4a | **未证明** | L2 门 |

## R1–R8 覆盖

| 规则 | 正例 | 负例 | 状态 |
|---|---|---|---|
| R1 | `dossiers/slab/accept.ls` | `reject/E-LS-MOVE-use-after-move.ls` | 可执行（checker-spike） |
| R2 | `pending/accept-r2-borrow-then-write.ls` | `pending/E-LS-ALIAS-r2-write-during-borrow.ls` | 语料已写，待检查器 |
| R3 | `accept/accept-unsafe-termination.ls` | `reject/E-LS-UNIQ-val-alias-field.ls` | 可执行（checker-spike） |
| R4 | `dossiers/views/accept.ls` | `dossiers/views/reject.ls` 的 `ref` 逃逸 | 可执行（checker-spike） |
| R5 | `pending/accept-r5-two-regions-disjoint.ls`、`pending/accept-r5-sibling-index-write.ls` | `pending/E-LS-ALIAS-r5-nested-write-site.ls`、`pending/E-LS-ALIAS-r5-frozen-place-write.ls` | 语料已写，待检查器 |
| R6 | `pending/accept-r6-atomic-fetch-add.ls` | `pending/E-LS-RACE-r6-shared-plain-{write,read}.ls`、`pending/E-LS-IRQ-r6-lock-rank.ls` | 语料已写，待检查器 |
| R7 | `accept/accept-unsafe-termination.ls` | `E-LS-CAP` / `E-LS-EFFECT-*` | 可执行（spike） |
| R8 | `pending/accept-r8-iso-spawn.ls`、`pending/accept-r8-val-static-spawn.ls` | `pending/E-LS-RACE-r8-{box,ref,val-local-region}-across-spawn.ls` | 语料已写，待检查器 |

> `checker-spike` 当前对 `accept/`（4 条）与 `reject/`（7 条）全绿；
> `pending/`（15 条）已通过 EBNF 解析，但不在检查器门内。
> 见 `tests/conformance/pending/README.md`。

## 条件前提

- `CAP_ALLOC_OK`：gate matrix allocator 假设（`L-AllocCap`），不在语言内核证明；
- `T1a-mono`：区域变量 site-bound；区域多态/高阶未形式化（`F0` 外）；
- `CAPS(f)`：gate matrix/模块 cap 入口检查；
- S12：`iso` 与 `box` 共用 core mode `uniq`，已收口；域转移由 R8。

## 下一步（按顺序）

1. **L1 可执行性**：
   - `ls-sem` 实现 R2/R5（区域级 `Aliases*`/`H` + 写权限），迁移 4 条；
   - `ls-sem` 实现 R6/R8（`atomicOp`/域模型）与 `Guard` 活跃集（`rankOk`），迁移 11 条；
   - 每次迁移后跑 `tests/conformance/{accept,reject}` 与 `pending/` 抽查。
2. **检查器门**：`ls-sem` 对 `reject/` 零漏过（`04 §14.6`）。
3. **L2**：`L-NoStuck` 的块闭包归纳（S9/S11/S14 的 `→*`）。
4. 复核 `CAP_ALLOC_OK` / `T1a-mono` / `CAPS` 前提。
5. 重新跑本审计；L1 全绿后才可标记「语义冻结（L1）」。

> 本文件不是 T4a 的证明；它只固定「哪些门过了、哪些没过」，避免把计划写成结论。
