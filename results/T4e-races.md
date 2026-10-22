# T4e · UB-5 数据竞争（事件 / 交错模型）

> 状态：**race 判定与 R6/R8 类型片段保证已机械化**（Lean 4.6.0，`lean/LSys/Threads.lean`）；
> Iris 级并发定理（`H-LS-3`/`H-LS-16`）仍是外部工作。
> 日期：2026-10-22
> 上位：[`spec/ub.md`](../spec/ub.md) 的 UB-5 条目、[`spec/semantics.md`](../spec/semantics.md) 的 T4 拆分表与 T2 小节、
> [`spec/modes.md`](../spec/modes.md) 的 R6/R8、`H-LS-3`/`H-LS-16`。

## 目标与边界

UB-5（数据竞争）在 F0/route A 里是 **vacuous** 的：`ConfE` 没有线程分量，
`EffHStepEvalCK` 是单线程。T4e 的模型回答两类问题：

1. **什么算 race**：两条访问同位置、至少一个写、来自**不同线程**、非双 atomic、
   且两个方向都没有 happens-before ⇒ UB-5；
2. **类型片段为什么没有 race**：R6（`shared` 必须 `atom`）、R8（`iso`/`val` 转移后
   只有一个线程拥有该位置）分别对应两条无 race 定理。

**不做**：Iris 级的并发分离逻辑、HB 的硬件内存模型（`Order × 架构 → 指令` 属
`spec/cost.md`）、中断/DMA 域（`H-LS-16`）、`Trusted` 闭包（`H-LS-24`）。

## 模型（`lean/LSys/Threads.lean`）

| 层 | 内容 |
|---|---|
| 事件 | `Event { tid, pos, loc, kind(read|write), atomic, sync }`；`Machine = { events : List Event }`（所有线程的事件平铺） |
| happens-before | `programBefore`（同线程 `pos` 递增）∪ `syncEdge`（`Sync.rel k` → `Sync.acq k`），`hbFuel` 带 fuel 做传递闭包，`hb` 以事件数 + 1 为 fuel |
| 冲突/竞争 | `conflict`（同位置 ∧ 至少一个写 ∧ 不同线程）、`atomicPair`、`racePair = conflict ∧ ¬atomicPair ∧ ¬hb(a,b) ∧ ¬hb(b,a)` |
| UB-5 | `Race m := ∃ a ∈ events, ∃ b ∈ events, racePair … = true`；`RaceEvent m UBCode.race`；`raceEvent_outside` |
| 检测器 | `raceB`（可执行）+ `raceB_iff_race`（`Bool` ↔ `Prop`，无公理） |
| 二分 oracle | `pair_class`：冲突对 ⇒ 双 atomic ∨ `hb` 正向 ∨ `hb` 反向 ∨ race |
| R6 | `shared_atomic_no_race`：同位置跨线程访问都是 atomic ⇒ 无 race |
| R8 | `SingleOwner` + `no_race_if_single_owner`：转移后只有一个线程碰该位置 ⇒ 无 race |
| 其它 | `no_race_if_atomic`、`no_race_single_thread`（F0 vacuity）、`race_needs_two_threads` |

`hb` 的 fuel 取事件数 + 1：任何简单链都不会更长；模型是**保守**的（少判 race），
这一点在文档里明确，不声称与硬件内存模型等价。

## 与 `E-LS-RACE` 语料对齐

| 语料 | 模型实例 |
|---|---|
| `E-LS-RACE-r6-shared-plain-read` / `-write` | `mSharedPlainWrite`（plain 写 vs atomic 读）⇒ `race_shared_plain_write : raceB = true` |
| 普通两线程冲突 | `mRace` ⇒ `race_witness`，并由 `raceB_iff_race` 得到 `race_implies_race_event` |
| 双 atomic | `mAtomic` ⇒ `atomic_no_race` |
| release/acquire 同 token | `mSynced` ⇒ `synced_no_race` |
| 同线程两次访问 | `mSameThread` ⇒ `same_thread_no_race` |
| 不同位置 | `mDisjoint` ⇒ `disjoint_no_race` |
| 两条普通读 | `mBothRead` ⇒ `both_read_no_race` |
| R8 `iso` 转移（单拥有） | `mSingleOwner` ⇒ `single_owner_no_race` |

## 公理

```text
any_eq_true / raceB_iff_race / pair_class / raceEvent_outside
race_witness / race_shared_plain_write / atomic_no_race / synced_no_race
same_thread_no_race / disjoint_no_race / both_read_no_race
single_owner_no_race / race_implies_race_event                 无公理
race_needs_two_threads / no_race_if_atomic / shared_atomic_no_race
no_race_if_single_owner / no_race_single_thread                propext
```

**没有 `sorryAx`，没有 `Classical.choice`。**

## 验证

```text
rm -f lean/LSys/*.olean && bash lean/check.sh
  → PASS lean: L3 + T4a foundation（52 模块，0 sorry，0 sorryAx）

grep -c Classical.choice .temp/lean-axioms.txt
  → 0

# 回归（本轮只加 Lean 模型 + 文档）
cargo test --quiet --manifest-path tools/ls-sem/Cargo.toml   → 64 passed
python tools/conformance-run                                 → SUMMARY PASS (accept=6, reject=10)
cd tools/checker-spike && cargo run --quiet -- ../../tests/conformance → SUMMARY PASS

bash tools/check-docs.sh
  → doc-lint 55 files / 0 errors、diag 40、freeze 18、grammar 21/21
```

## 边界（不要当成已完成）

- **hb 不是硬件内存模型**：`Order` 到指令的映射（`spec/cost.md`）与 fence 语义未建模；
  fuel 上限使判定保守（可能漏判长链上的 HB，从而**多**报 race，不会少报）。
- **不是 Iris**：没有并发分离逻辑证明，`H-LS-3`/`H-LS-16` 仍开。
- **`Trusted`/跨 crate**：R8 的 `iso` 转移只以 `SingleOwner` 形式出现；
  真正的 `spawn`/`join` 语义（S15/S16）仍未进模型。
- **中断/DMA 域**：不在本模型（`Irq`/`Dma` 仍是 `H-LS-16`）。

## A 线收口

UB-13（T4d）、UB-11（T4b）、UB-15（T4c）、UB-8/9/10（T4b RTT v1）、UB-5（T4e）
全部有 Lean 模型与证据文档；**A 线的「非 F0 UB 运行时模型」清单到此关闭**。
剩下的都是显式外部工作：`H-LS-3`/`H-LS-16`（Iris/中断域）、`H-LS-4`（`unsafe` 深层
soundness）、`H-LS-5`（FFI 外部行为）、`H-LS-29`（静态栈上界）与 S5（RTT ⊆ TB）。
