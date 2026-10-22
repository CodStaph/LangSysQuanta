# T4c · UB-15 跨 FFI 的 unwind

> 状态：**语言侧模型已机械化 + callee 义务已登记为显式信任**
> （Lean 4.6.0，`lean/LSys/Ffi.lean`；`spec/trust.md` 的 `HonorsNounwind`）
> 日期：2026-10-22
> 上位：[`spec/semantics.md`](../spec/semantics.md) 的 T4 拆分表、[`spec/ub.md`](../spec/ub.md) 的 UB-15 条目、
> [`spec/baremetal.md`](../spec/baremetal.md) 的 C ABI 映射、[`spec/trust.md`](../spec/trust.md) 的显式信任小节。

## 目标

UB-15 的义务拆成三份：

1. **退出分类**（语言侧，可证）：跨界退出只有 `ret` / `abort` / `unwind`，
   只有 `unwind` 是未定义；`panic` 走 `abort`，**不 unwind**；
2. **静态 ABI gate**（可证）：`?` 越过边界要求返回类型能编码错误、无 varargs，
   否则 `E-LS-ABI`；
3. **callee 行为**（不可证）：`extern "C"` 声明 `nounwind`，但 callee 在语言之外
   （`H-LS-5`），只能按具名信任处理。

## 模型（`lean/LSys/Ffi.lean`）

| 层 | 内容 | 定理 |
|---|---|---|
| 退出 | `Exit = ret w | abort | unwind`；`isDefined`（ret/abort 为真） | `ret_defined`/`abort_defined`/`defined_or_unwind`（无公理） |
| 边界 | `Boundary { nounwind : Bool }`、`cBoundary`（`extern "C"`） | `cBoundary_nounwind`（rfl） |
| UB-15 事件 | `FfiEvent b x UBCode.unwind`（unwind 穿过 nounwind 边界） | `ffiEvent_outside`、`ret_not_unwind`、`abort_not_unwind`、`defined_or_ub`（无公理） |
| ABI gate | `AbiSig { externC, retEncodesError, varargs }`、`abiOk` | `abiOk_extern_c`/`abiOk_ret_encodes`/`abiOk_no_varargs`（`propext`）；`abi_rejects_unencodable_error`/`abi_accepts_encodable`/`abi_rejects_varargs`（无公理） |
| 显式信任 | `HonorsNounwind exitOf ≜ ∀ f, isDefined (exitOf f) = true` | `honors_no_ub`（无公理）、`well_behaved_honors`（无公理）、`not_every_callee_honors`（无公理） |
| 轨迹 | `Crossing`、`FfiUB`、`NounwindTrace`、`DefinedTrace` | `defined_trace_no_ub`、`ub_trace_witness`、`abort_trace_no_ub`（无公理）；`nounwind_trace_not_enough`（无公理）；`trace_no_ub_of_callees`（无公理） |

关键点：

- **`panic` 不是 UB-15**：`abort_not_unwind`；LSys 的 `panic`/`abort` 不 unwind（`00 §6.6`）。
- **`?` 不是 UB-15**：它是静态 ABI 问题（返回类型必须能编码错误），
  `abi_rejects_unencodable_error` 给出 `E-LS-ABI` 的判定位置。
- **声明本身不够**：`nounwind_trace_not_enough` —— 全是 `extern "C"` 的轨迹仍可能
  含 UB-15；必须叠加 `HonorsNounwind`（`trace_no_ub_of_callees`）。
- **可证伪**：`not_every_callee_honors`（`unwindingCallee` 恒 unwind，违反信任）。

## 公理

```text
ret_defined / abort_defined / defined_or_unwind / defined_or_ub
ret_not_unwind / abort_not_unwind / ffiEvent_outside / cBoundary_nounwind
abi_rejects_unencodable_error / abi_accepts_encodable / abi_rejects_varargs
honors_no_ub / not_every_callee_honors / well_behaved_honors
defined_trace_no_ub / ub_trace_witness / abort_trace_no_ub
nounwind_trace_not_enough / trace_no_ub_of_callees              无公理
abiOk_extern_c / abiOk_ret_encodes / abiOk_no_varargs            propext
```

**没有 `sorryAx`，没有 `Classical.choice`。**

## 与 Q6 / 既有证据的关系

| 层 | 现有证据 | 与 T4c 模型的关系 |
|---|---|---|
| C 标量映射 | `tools/ls-sem/src/abi.rs` 的 `map_scalar`/`check_signature`（`results/Q2-Q6-Q7-implementation.md`） | 静态 gate 的 Rust 实现；Lean 只抽象成 `AbiSig`/`abiOk` |
| `extern "C"` 语法 | `tests/syntax/00-s5/s5-05-unsafe-lowlevel.ls`、`dossiers/slab/accept.ls`（`extern`/`#[boundary]`） | surface 证据，不是语义证明 |
| `#[boundary]` 效果并集 | `tools/checker-spike`（`E-LS-EFFECT-boundary-drops-unsafe.ls` 等） | T4c 之外的效果门 |
| 无 unwind 的 runtime | `Expr.abort` + `EffHStepEvalCK` 的 14 条 `abort*` 规则（abort 传播、不弹帧） | `abort` 是程序终点；模型与此一致 |

## 验证

```text
rm -f lean/LSys/*.olean && bash lean/check.sh
  → PASS lean: L3 + T4a foundation（50 模块，0 sorry，0 sorryAx）

grep -c Classical.choice .temp/lean-axioms.txt
  → 0

# 回归（本轮只加 Lean 模型 + 文档）
cargo test --quiet --manifest-path tools/ls-sem/Cargo.toml   → 64 passed
python tools/conformance-run                                 → SUMMARY PASS (accept=6, reject=10)
cd tools/checker-spike && cargo run --quiet -- ../../tests/conformance → SUMMARY PASS

bash tools/check-docs.sh
  → doc-lint 52 files / 0 errors、diag 40、freeze 18、grammar 21/21
```

## 边界（不要当成已完成）

- **callee 未验证**：`HonorsNounwind` 是假设，不是定理；没有形式化 C 侧行为，
  也没有把 `setjmp`/`longjmp`、信号、语言异常纳入模型（由 `H-LS-5` 的审计承担）。
- **不覆盖**：`extern "C-unwind"` 不存在（v0 只有 `extern "C"`）；ABI 布局/字段级
  一致性的完整形式化（`ls abi-check` 仍未实现）。
- **不替代**：`Cap[Ffi]`/`eff(Ffi)` 的静态检查、`#[boundary]` 效果并集、
  指针 `rawptr` 的规则。

## 下一步

按 `MEMORY.md` 的 A 线顺序：**UB-8/9/10（T4b，`Cell`/`RVal` 加 RTT v1 tag）** →
UB-5（T4e，线程/交错模型）。
