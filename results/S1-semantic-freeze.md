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
| **L1 规范冻结** | **通过（2026-10-19）** | R1–R8 均可执行（R2/R5/R6/R8 由 `ls-sem`；R1/R3/R4/R7 由 checker-spike/dossiers）；`pending/` 为空；最小核样例与 fix-it 负例均有测试 |
| **L2 定理冻结（T4a）** | **通过（纸面，2026-10-19）** | L-Term/L-Block/L-Progress/L-NoStuck 完成；T1a-mono + `Rgn*`；T4a 相对 `CAP_ALLOC_OK`/`CAPS(f)` 成立 |
| **L3 机械化** | **通过（F0 核心，2026-10-20）** | `lean/LSys/{Term,State,Adequacy,Progress,Block,T4a}.lean` 全部机器检查（无 `sorryAx`；仅 `propext`/内核 `Quot.sound`）；边界见 `lean/README.md` |

**L1 与 L2 均通过（纸面，2026-10-19）**；T4a 条件成立；**L3 F0 核心已于 2026-10-20 机械化**。仍不得把 T4b–T4e 或完整语言写成「已机械化」。

## 门禁条件

| 条件 | 状态 | 证据/缺口 |
|---|---|---|
| `Σ=(Γ,Λ,M,H)` + `⊣ Σ'` | **通过** | `spec/semantics.md` §2 |
| M2 L-Adequacy | **条件通过** | `t4-proof.md` 的 M2 章节；S10/S11 依赖 `CAP_ALLOC_OK` / T1a |
| M2 Preservation / L4 | **条件通过** | M2 Preservation 章节；I1–I8 对 S2–S12 |
| M3 core（call/return/frame/drop） | **条件通过** | M3 章节；`CAPS` / T1a |
| M3 完整（泛型/区域多态/递归/动态分派/跨模块） | **不在 L1** | `F0` 已排除；登记 `H-LS-18` / `H-LS-29` / `H-LS-5` / ADR-17 |
| Progress / `L-NoStuck` | **通过（纸面）** | `t4-proof.md` 的 L-Redex 分类表 + L-Term/L-Block/L-Progress/L-NoStuck 小节 |
| R1–R8 正负例可执行 | **通过** | `ls-sem`：accept 6 / reject 9；checker-spike：accept 4 / reject 7（Q4/Q9）；`pending/` 为空 |
| 最小不可满足核样例 | **通过** | `tools/ls-sem/tests/fixtures/unsat_core_escape.ls`；`escape_reports_minimal_core_and_safe_fixit` |
| fix-it 禁止 `unsafe` 负例 | **通过** | 同一测试断言 fixit 不含 `unsafe`/`rawptr`/`Ffi`/`Cap[` |
| T4a | **未证明** | L2 门 |

## R1–R8 覆盖

| 规则 | 正例 | 负例 | 状态 |
|---|---|---|---|
| R1 | `dossiers/slab/accept.ls` | `reject/E-LS-MOVE-use-after-move.ls` | 可执行（checker-spike） |
| R2 | `accept/accept-r2-borrow-then-write.ls` | `reject/E-LS-ALIAS-r2-write-during-borrow.ls` | 可执行（ls-sem） |
| R3 | `accept/accept-unsafe-termination.ls` | `reject/E-LS-UNIQ-val-alias-field.ls` | 可执行（checker-spike） |
| R4 | `dossiers/views/accept.ls` | `dossiers/views/reject.ls` 的 `ref` 逃逸 | 可执行（checker-spike） |
| R5 | `accept/accept-r5-two-regions-disjoint.ls`、`accept/accept-r5-sibling-index-write.ls` | `reject/E-LS-ALIAS-r5-nested-write-site.ls`、`reject/E-LS-ALIAS-r5-frozen-place-write.ls` | 可执行（ls-sem） |
| R6 | `accept/accept-r6-atomic-fetch-add.ls` | `reject/E-LS-RACE-r6-shared-plain-{write,read}.ls`、`reject/E-LS-IRQ-r6-lock-rank.ls` | 可执行（ls-sem） |
| R7 | `accept/accept-unsafe-termination.ls` | `E-LS-CAP` / `E-LS-EFFECT-*` | 可执行（spike） |
| R8 | `accept/accept-r8-iso-spawn.ls`、`accept/accept-r8-val-static-spawn.ls` | `reject/E-LS-RACE-r8-{box,ref,val-local-region}-across-spawn.ls` | 可执行（ls-sem） |

> **可执行性缺口已关闭（2026-10-19）**：`ls-sem` 已加入 `borrow`/`freeze`/
> `spawn`/`shared`/`atom`/`Lock`/`Order` 与 `Guard`，`pending/` 已清空。

> `checker-spike` 当前对 `accept/`（4 条）与 `reject/`（7 条）全绿；
> `pending/` 为空；Q4/Q9 的 11 条在 `tests/conformance/checker-spike/`。
> 见 `tests/conformance/pending/README.md`。

## 最小核样例（可复现）

```bash
cargo run --quiet --manifest-path tools/ls-sem/Cargo.toml --   check tools/ls-sem/tests/fixtures/unsat_core_escape.ls
```

期望输出（节选）：

```text
E-LS-REGION-ESCAPE: return value escapes region `R#1` (function ambient is `fn@make#0`);
  core (1 minimal): [return: `fn@make#0` ⊑ `R#1`];
  witness: `R#1` ⊑ `fn@make#0` (region nesting)
  [fix-it: copy the value, allocate it in `heap`, or narrow the returned region]
```

- core 是**删除可约简**的 1 条必需约束（`fn ⊑ R`），`fn` 是 site-bound 固定区域，不能再提升；
- witness 是区域树的结构事实（`R` 嵌套在 `fn` 内），用来说明冲突；
- fix-it 只给 `copy` / `heap` / 缩小返回区域，**不含** `unsafe`/`rawptr`/`Ffi`/`Cap[`（LS-P17）。

## 条件前提

- `CAP_ALLOC_OK`：gate matrix allocator 假设（`L-AllocCap`），不在语言内核证明；
- `T1a-mono`：site-bound + `ceil` 截断已证；`Rgn*` 逐字段覆盖 A-5；区域多态不在 `F0`；
- `CAPS(f)`：gate matrix/模块 cap 入口检查；
- S12：`iso` 与 `box` 共用 core mode `uniq`，已收口；域转移由 R8。

## 下一步（按顺序）

1. **L1**：已通过（2026-10-19）；tag 条件见 `spec/freeze-manifest.md`。
2. **检查器门**：`python tools/conformance-run`（accept 6 / reject 9）；
   checker-spike 的 Q4/Q9 子集保持全绿。
3. **L2**：已通过（纸面）；T4a 相对 `CAP_ALLOC_OK`/`CAPS(f)` 成立。
   L3 的 L-Adequacy/T4a（F0 核心）已于 2026-10-20 机械化；下一步是 M4（参考解释器）/M5（T4b–T4e）。
4. 复核 `CAP_ALLOC_OK` / `T1a-mono` / `CAPS` 前提。
5. 重新跑本审计；L2 全绿后才可标记「T4a 已证」。

> 本文件不是 T4a 的证明；它只固定「哪些门过了、哪些没过」，避免把计划写成结论。
