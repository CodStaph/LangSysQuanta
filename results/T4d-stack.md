# T4d · UB-13 栈溢出（运行时 depth 预算）

> 状态：**模型已机械化**（Lean 4.6.0，`lean/LSys/Stack.lean`）；`kernel` 静态栈上界
> （`E-LS-STACK` / `H-LS-29`）仍由 `tools/checker-spike` 与档案 B 承担。
> 日期：2026-10-22
> 上位：[`spec/semantics.md`](../spec/semantics.md) 的 T4 拆分表、[`spec/ub.md`](../spec/ub.md) 的 UB-13 条目、
> [`spec/t4-proof.md`](../spec/t4-proof.md) 的 M3 完整性表、[`dossiers/recursion/README.md`](../dossiers/recursion/README.md)。

## 目标

`spec/ub.md` 对 UB-13 的处置是「`agent` depth 预算 + `kernel` 静态栈上界」。
T4d 要回答的问题是：**给定预算，栈溢出还是不是未定义行为？**

答案分两半：

1. **运行时**：预算内不溢出（本文交付）；
2. **静态**：`kernel` 的程序都能落入预算（`H-LS-29`，外部义务）。

## 模型（`lean/LSys/Stack.lean`）

| 层 | 内容 |
|---|---|
| 记账 | `StackConf = (depth, budget)`；`Fits s ⇔ s.depth ≤ s.budget`；`push`/`pop`（`depth` 以帧计，入口帧为 1） |
| 事件 | `StackEvent s UBCode.stack`（`budget < depth`）——UB-13 的运行时事件 |
| oracle | `fits_or_overflow`：`Fits s ∨ StackEvent s UBCode.stack`（检查是全的）；`no_overflow_within`：`Fits s → ¬ StackEvent …` |
| 守卫运行 | `StackStar`（只含通过守卫的入帧/出帧）；`StackStar.fits`（从合预算的起点出发，全程合预算）；`no_overflow_reachable` |
| 核心步 | `StackStepCK`：把每个 `EffHStepEvalCK` 步标注为 `push`（`callV`）/ `pop`（`retV`）/ `neutral`（其余，**含 14 条 `abort*`**：LSys 的 `abort` 不 unwind，所以不弹帧） |
| 核心性质 | `StackStepCK.fits`（保预算）、`StackStepCK.depth_le`（每步至多 +1）、`StackStepCK.wt`（保 `WTKH`，经 `WTKH.preserved`） |
| 多步 | `StackedStep` / `StackedStar`；`StackedStar.toStack`、`StackedStar.fits`、`no_stack_overflow_reachable` |
| 静态↔运行时 | `staticBoundOk bound stack frame := bound * frame < stack`；`bound_le_of_mul_lt` → `static_bound_fits`（静态检查通过 ⇒ 帧预算足够） |
| profile | `profileBudget`：`kernel` 用静态上界，`agent` 用 depth 预算（`kernel_budget_is_static`、`agent_budget_is_depth`） |

`StackStepCK` 的标注是**关系**（同一步也可记为 `neutral`），所以抽象不会人为阻断步进；
守卫只在 `push` 上生效，这正是「预算用尽」的语义位置。

## 与档案 B 的数值对齐

| 项 | 值 | 定理 |
|---|---|---|
| 8 KiB 栈、128 B 帧 ⇒ 帧预算 | 64 帧 | `frameBudget 8192 128`（`Nat.div`） |
| `#[recursion(bound = 8)]`（`accept_rec.ls`） | 8 × 128 = 1 KiB < 8 KiB，通过 | `bound8_ok`、`dossier_bound8_fits` |
| `#[recursion(bound = 64)]`（`reject.ls`） | 64 × 128 = 8 KiB，**被拒**（`E-LS-STACK`） | `bound64_rejected` |
| 静态通过 ⇒ 预算足够 | `bound * frame < stack → bound ≤ stack / frame` | `static_bound_fits` |

静态检查刻意比运行时预算更保守（`>=` 即拒），所以 `bound = 63` 是 8 KiB/128 B 下的最大通过值；
`reject.ls` 的 64 正是被这条严格不等号拒掉。

## 公理

```text
fits_or_overflow                    无公理
no_overflow_within                  无公理
fits_of_not_overflow                无公理
StackStar.fits                      无公理
no_overflow_reachable               无公理
no_stack_overflow_reachable         无公理
StackStepCK.toCK / fits / depth_le  无公理
StackedStar.fits / toStack          无公理
bound64_rejected                    无公理
StackStepCK.wt / StackedStep.wt     propext（经 WTKH.preserved）
static_bound_fits / dossier_bound8_fits  propext
```

**没有 `sorryAx`，也没有 `Classical.choice`**（所有二值拆分走 `Nat.lt_or_ge`）。

## 验证

```text
rm -f lean/LSys/*.olean && bash lean/check.sh
  → PASS lean: L3 + T4a foundation（48 模块，0 sorry，0 sorryAx）

grep -c Classical.choice .temp/lean-axioms.txt
  → 0

# 静态侧（E-LS-STACK）仍与 Lean 的 bound8/bound64 实例逐字对齐
cd tools/checker-spike && cargo run --quiet -- ../../dossiers/recursion
  → E-LS-STACK: fn too_deep recursion bound 64 exceeds the 8192-byte static stack budget
  → SUMMARY PASS

# 回归（本轮改动不动 B-LS / ls-sem）
cargo test --quiet --manifest-path tools/ls-sem/Cargo.toml   → 49 passed
python tools/conformance-run                                 → SUMMARY PASS (accept=6, reject=10)

bash tools/check-docs.sh
  → doc-lint 51 files / 0 errors、diag 40、freeze 18、grammar 21/21
```

## 边界（不要当成已完成）

- **不是**「任意程序都在预算内」：预算从哪来（`kernel` 的静态分析、`agent` 的 profile
  参数）不在 T4d 的 Lean 模型里；
- **不是**栈帧布局/对齐的 ABI 证明：`frameBudget` 只用帧大小做算术换算，
  真实帧大小由 `spec/baremetal.md` / `spec/image.md` 与后端决定；
- **不是**编译器正确性：栈上界检查不被优化破坏属于 T4b 风格的后端信任（`spec/trust.md`）；
- `spawn` 不在 F0，`spawnV` 在标注里按 `neutral` 处理（线程/域模型属于 T4e）。

## 下一步

按 `MEMORY.md` 的 A 线顺序：**UB-11（T4b，`Mmio`/volatile）** → UB-15（T4c）→
UB-8/9/10（T4b，`Cell`/`RVal` 加 RTT v1 tag）→ UB-5（T4e）。
