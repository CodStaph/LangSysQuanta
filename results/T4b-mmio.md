# T4b · UB-11 MMIO 非 volatile 访问 / 后端重排

> 状态：**语言侧模型已机械化 + 后端义务已登记为显式信任**
> （Lean 4.6.0，`lean/LSys/Mmio.lean`；`spec/trust.md` 的 `HonorsVolatile`）
> 日期：2026-10-22
> 上位：[`spec/semantics.md`](../spec/semantics.md) 的 T4 拆分表与「MMIO / volatile」小节、
> [`spec/ub.md`](../spec/ub.md) 的 UB-11 条目、[`spec/effects.md`](../spec/effects.md) 的 gate matrix、
> [`spec/trust.md`](../spec/trust.md) 的显式信任小节。

## 目标

UB-11 有两个不同的义务，不能混在一个定理里：

1. **语言侧**：`Mmio[T]` 的访问必须是 volatile（类型固定），否则就是 UB-11；
2. **编译侧**：后端不得重排/删除 volatile 访问。

第 1 条能证；第 2 条**不能**在语言语义里证（`F0` 无 `Mmio/Hw`），
所以按 T4b 的口径写成具名假设，并要求可证伪。

## 模型（`lean/LSys/Mmio.lean`）

| 层 | 内容 | 定理 |
|---|---|---|
| 访问分类 | `PlaceSpace = plain | mmio`、`AccessMode = ordinary | volatile`、`MemAccess` | — |
| UB-11 事件 | `MmioEvent a UBCode.mmio`（MMIO 地址 + plain 访问） | `mmioEvent_outside`（无公理） |
| 类型固定 volatile | `mmioAccess : MemAccess`（mmio + volatile） | `typed_mmio_no_ub`、`plain_mmio_is_ub`、`safe_or_ub`（无公理） |
| MMIO store | `MmioStore = MmioAddr → Option Word`（`semantics.md` 4.4 的 `M`，独立于 `σ`） | `mmioWrite_read_same`、`mmioWrite_read_other`（无公理） |
| 轨迹 | `Trace = List TraceEv`、`volatileOnly`、`volatileCount`（`ls cost` 的 1 volatile） | — |
| 允许的后端行为 | `Compliant`：保留 / 删除非 volatile / 交换**非全 volatile** 的相邻访问 / 传递闭包 | `Compliant.volatileOnly_eq`、`Compliant.volatileCount_eq`（`propext`） |
| 显式信任 | `HonorsVolatile compile ≜ ∀ t, Compliant t (compile t)` | `honors_preserves_volatile`、`honors_preserves_volatile_count`（`propext`） |
| 可证伪 | 无条件交换前两条访问的后端 | `not_every_backend_honors`（`propext`） |
| 轨迹级 UB-11 | `TypedTrace`（所有 MMIO 访问 volatile）无 UB-11 | `typed_trace_no_ub`（无公理）、`typed_mmio_trace_no_ub`、`untyped_mmio_has_ub`（无公理） |

要点：

- `Compliant` **不允许**删除 volatile 访问，**不允许**交换两个都 volatile 的访问；
  其余（保留、删 plain、swap plain/volatile 或 plain/plain）都可以。
  于是在信任下 volatile 子序列完全不变 —— 相对顺序与计数都不变。
- 这不是「后端自动正确」：`not_every_backend_honors` 给出反例后端，
  所以 `spec/trust.md` 必须显式登记 `HonorsVolatile`，`ls audit` 应能追溯证据。

## 公理

```text
typed_mmio_no_ub / plain_mmio_is_ub / safe_or_ub / mmioEvent_outside
mmioWrite_read_same / mmioWrite_read_other
typed_trace_no_ub / typed_mmio_trace_no_ub / untyped_mmio_has_ub   无公理
Compliant.volatileOnly_eq / Compliant.volatileCount_eq
honors_preserves_volatile / honors_preserves_volatile_count
not_every_backend_honors                                          propext
```

**没有 `sorryAx`，没有 `Classical.choice`。**

## 与既有实现/证据的关系

| 层 | 现有证据 | 与 T4b 模型的关系 |
|---|---|---|
| `Mmio` cap 范围 | `tools/ls-sem` 的 `cap_context`（`Capability::Mmio{lo,hi}` 与地址包含） | 静态门；模型假设地址已通过该门 |
| `Mmio[T]` 用法 | `tests/syntax/00-s5/s5-01-module-profile.ls`、`s5-05-unsafe-lowlevel.ls`、`s5-07-concurrency-irq-dma.ls`、`dossiers/slab/accept.ls`（`ref[Mmio[IntRegs]]`） | surface 证据，不是语义证明 |
| affine `Mmio`（不可 Copy） | `tools/checker-spike`：`dossiers/slab/reject.ls` 的 `copy_mmio` 报 `E-LS-MOVE` | UB-11 之外的类型约束 |
| `Hw` 效果 | `spec/effects.md` gate matrix（cap + `Hw`） | 模型不重做 cap/效果检查 |
| `ls cost` 的 1 volatile | `spec/cost.md`（尚未实现） | 模型侧 `volatileCount` 在信任下不变 |

## 验证

```text
rm -f lean/LSys/*.olean && bash lean/check.sh
  → PASS lean: L3 + T4a foundation（49 模块，0 sorry，0 sorryAx）

grep -c Classical.choice .temp/lean-axioms.txt
  → 0

# 回归（本轮只加 Lean 模型 + 文档）
cargo test --quiet --manifest-path tools/ls-sem/Cargo.toml   → 64 passed
python tools/conformance-run                                 → SUMMARY PASS (accept=6, reject=10)
cd tools/checker-spike && cargo run --quiet -- ../../dossiers/slab   → SUMMARY PASS

bash tools/check-docs.sh
  → doc-lint 51 files / 0 errors、diag 40、freeze 18、grammar 21/21
```

## 边界（不要当成已完成）

- **后端未验证**：`HonorsVolatile` 是假设，不是定理；没有形式化后端/代码生成，
  也没有把 `Order × 架构 → 指令` 的映射机械化（属 `spec/cost.md`）。
- **不覆盖硬件后果**：缓存一致性、总线宽度/对齐、寄存器副作用由硬件手册与
  `spec/baremetal.md` 承担。
- **不背书 `unsafe` 深层 soundness**（`H-LS-4` 仍 `Out-of-scope`），也不替代
  `Mmio` cap 范围检查（`E-LS-PROV` 的静态部分）。
- **不是 `asm` 的模型**：`asm` 的 volatile 语义同属 T4b，但本轮只做 `Mmio`；
  `asm` 仍按 `spec/baremetal.md` 的约定（不参与常量折叠/重排）。

## 下一步

按 `MEMORY.md` 的 A 线顺序：**UB-15（T4c，`extern "C"` nounwind 边界）** →
UB-8/9/10（T4b，`Cell`/`RVal` 加 RTT v1 tag）→ UB-5（T4e）。
