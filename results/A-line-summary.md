# A 线收口 · 非 F0 UB 的运行时模型（T4b / T4c / T4d / T4e）

> 状态：**A 线全部关闭（2026-10-22）**。5 个非 F0 UB 类别各有 Lean 模型 + 证据文档；
> 剩余全部是**显式假设/外部工作**，本文把它们逐条登记，避免「模型齐了 = UB 全解决了」的误读。
> 上位：[`spec/semantics.md`](../spec/semantics.md) 的 T4 拆分表、[`spec/ub.md`](../spec/ub.md) 的 15 条清单、
> [`lean/README.md`](../lean/README.md) 的模块表与建模边界。

## 0. 一页结论

| UB | T | 模型模块 | UB 事件 | 核心定理（公理） | 证据 |
|---|---|---|---|---|---|
| UB-13 栈溢出 | T4d | `lean/LSys/Stack.lean` | `StackEvent … UBCode.stack` | `no_stack_overflow_reachable`（无）、`StackStepCK.wt`（`propext`）、`dossier_bound8_fits`（`propext`） | [`T4d-stack.md`](T4d-stack.md) |
| UB-11 MMIO 重排 | T4b | `lean/LSys/Mmio.lean` | `MmioEvent … UBCode.mmio` | `typed_mmio_no_ub` / `safe_or_ub`（无）、`honors_preserves_volatile`（`propext`） | [`T4b-mmio.md`](T4b-mmio.md) |
| UB-15 FFI unwind | T4c | `lean/LSys/Ffi.lean` | `FfiEvent … UBCode.unwind` | `defined_or_ub`（无）、`trace_no_ub_of_callees`（无）、`abiOk_ret_encodes`（`propext`） | [`T4c-ffi.md`](T4c-ffi.md) |
| UB-8/9/10 provenance | T4b | `lean/LSys/Provenance.lean` | `Verdict.ub` → `rawUnsafe` / `unaligned` / `provenance` | `check_ok_or_ub`（无）、`checkTag'_ok`（`propext`）、RTT-1…RTT-10（无） | [`T4b-provenance.md`](T4b-provenance.md) |
| UB-5 数据竞争 | T4e | `lean/LSys/Threads.lean` | `RaceEvent … UBCode.race` | `pair_class`（无）、`raceB_iff_race`（无）、`shared_atomic_no_race`（`propext`） | [`T4e-races.md`](T4e-races.md) |

规模与公理纪律（2026-10-22，`lean/check.sh`）：

```text
52 个 Lean 模块 PASS；#print axioms 304 条中 219 条「无公理」
0 个 sorry / sorryAx；0 处 Classical.choice
非计算公理只有 propext 与内核 Quot.sound
```

## 1. 共同的建模约定

1. **事件索引 `UBCode`**：每个模型都给一个 `…Event` 归纳，事件码直接取自
   `LSys.UBCode`（15 条），并用 `…_outside : OutsideF0 k` 说明该码在 F0 之外——
   与 `T4a` 的 `F0Event` 分区不重叠。
2. **「要么定义、要么 UB」的 oracle**：`fits_or_overflow`（栈）、`safe_or_ub`（MMIO）、
   `defined_or_ub`（FFI）、`check_ok_or_ub`（provenance）、`pair_class`（race）。
   这比「证一条 UB 不发生的定理」更符合 T4 的拆分口径：模型必须**指出**每条路径的去向。
3. **可执行判定**：`staticBoundOk` / `check` / `raceB` / `Compliant` 都是可计算函数，
   正例/负例用 `decide` 检查；抽象定理再用 `cases` 证。
4. **信任具名化**：凡语言内证不了的，一律登记成 `def … : Prop` + `…_honors`/反例定理，
   写进 `spec/trust.md`：
   - T4b：`HonorsVolatile compile`（后端只保留/删非 volatile/交换非全 volatile 的对），
     反例 `not_every_backend_honors`；
   - T4c：`HonorsNounwind exitOf`（每个可达 callee 只 `ret`/`abort`），
     反例 `not_every_callee_honors`；
   - T4b provenance：`Access.witness` 是**输入**，不是定理；
   - T4d：`kernel` 的静态栈上界（`E-LS-STACK`/`H-LS-29`）是输入，模型只证
     「静态检查通过 ⇒ 帧预算足够」（`static_bound_fits`）。
5. **不引入 `Classical`**：所有二值拆分走构造器/`Bool` 分支；`by_cases` 禁用。
6. **F0 真空性**：F0/route A 没有 `Mmio`/FFI/递归/`rawptr`/线程，因此这些模型的
   「安全子集」结论表现为 vacuity 定理（`no_race_single_thread`、`derefRaw` 不在
   `WTKH`、`StackStepCK` 只在 `callV` 上入帧等），而不是对 F0 的加强。

## 2. 每个模型的关键边界

### UB-13（T4d，栈）

- `budget` 以**帧**计；`frameBudget = stackBytes / frameBytes` 只做算术换算，
  真实帧布局属 `spec/baremetal.md`/`spec/image.md`。
- `callV` 是唯一入帧步（守卫 `depth < budget`），`retV` 是唯一出帧步；
  14 条 `abort*` 中性（`abort` 不 unwind，不弹帧）。
- **静态分析不做**：`kernel` 程序是否都能落进预算，仍由 `#[stack]`/`#[recursion(bound)]`
  与 `H-LS-29` 承担。

### UB-11（T4b，MMIO）

- 语言侧只证「typed `Mmio[T]` 访问固定 volatile、普通访问即 UB-11」；
  **后端不重排**是 `HonorsVolatile` 假设。
- 不覆盖 `fence(Order)` → 指令映射（`spec/cost.md`）、`asm`、缓存一致性/总线。

### UB-15（T4c，FFI）

- `Exit = ret | abort | unwind`，只有 `unwind` 未定义；`panic` 走 `abort`。
- `?` 越过边界是**静态** ABI 问题（`AbiSig`/`abiOk` ⇒ `E-LS-ABI`），不是 UB-15 的运行时分支。
- `nounwind_trace_not_enough` 明确「只有 `extern "C"` 声明不够」，必须有 callee 信任。
- 不覆盖 C 的 `setjmp`/`longjmp`、信号、异常；`ls abi-check`/布局哈希未做。

### UB-8/9/10（T4b，RTT v1）

- A1–A6 判定机械化；A2 越界归 UB-10（`spec/ub.md` §2.4），UB-1 的边界检查是另一回事。
- `Witness` 是输入（`H-LS-4` 不回补）；`int → raw` 无 `Witness` ⇒ UB-10（RTT-4）。
- **tag 树独立于 `Cell`/`RVal`**：安全子集无 `rawptr`、tag 编译期擦除，桥接用
  `ProvWF`/`check_ok_live`（通过检查的访问触碰活 cell）。
- RTT v1 ⊆ Tree Borrows（S5）**未证**；`derefRaw` 仍不在 `WTKH` 中。

### UB-5（T4e，race）

- `hb` = 程序序 ∪ release→acquire 同 token，fuel = 事件数 + 1（保守：可能漏判长链 HB，
  从而**多**报 race，不会少报）。
- 类型片段保证：R6 `shared_atomic_no_race`、R8 `SingleOwner`/`no_race_if_single_owner`。
- **不是 Iris**：`H-LS-3`/`H-LS-16`（中断/DMA 域）仍是外部工作；`spawn`/`join` 的实义未建模。

## 3. 仍然开着的显式假设（A 线之外）

| 假设 | 归属 | 谁承担 |
|---|---|---|
| `HonorsVolatile`（后端不重排/不删 volatile） | T4b | `spec/trust.md`；后端测试/形式化后端模型进 `ls audit`（未做） |
| `HonorsNounwind`（callee 不 unwind） | T4c | `spec/trust.md`；`H-LS-5` |
| `Witness` 有效（`unsafe` 契约） | T4b | `H-LS-4`（仍 `Out-of-scope`） |
| `kernel` 静态栈上界 | T4d | `E-LS-STACK`/`H-LS-29` + `spec/baremetal.md` |
| RTT v1 ⊆ Tree Borrows | T4b | S5（未机械化） |
| 线程/中断域并发定理 | T4e | `H-LS-3`/`H-LS-16`（Iris） |
| 内存序/`fence` → 指令 | T4b | `spec/cost.md`（未实现） |
| C ABI 布局/字段一致性 | T4c | `spec/baremetal.md` 的 `ls abi-check`（未做） |

## 4. 验收（当前基线）

```text
rm -f lean/LSys/*.olean && bash lean/check.sh    → PASS（52 模块，0 sorryAx，0 Classical.choice）
bash tools/check-docs.sh                         → PASS（56 files / 0 errors，freeze 18，grammar 21/21）
cargo test --manifest-path tools/ls-sem/Cargo.toml → 64 passed
python tools/conformance-run                     → SUMMARY PASS (accept=6, reject=10)
cd tools/checker-spike && cargo run -- ../../dossiers/recursion|slab|tests/conformance → SUMMARY PASS
```

## 5. 索引

- 规范：`spec/ub.md`（15 条 + RTT v1 + 各 UB 的运行时模型段）、`spec/semantics.md`
  （T4 拆分表、UB 覆盖映射、`F0` 真空性）、`spec/trust.md`（两类显式信任）、
  `spec/modes.md`（R6/R8）、`spec/baremetal.md`（`extern "C"`/`nounwind`）、
  `spec/cost.md`（1 volatile 与内存序，未实现）。
- 代码：`lean/LSys/{Stack,Mmio,Ffi,Provenance,Threads}.lean`；`lean/check.sh`；
  `lean/verify_axioms.lean`（全部定理的 `#print axioms`）。
- 证据：`results/T4d-stack.md`、`results/T4b-mmio.md`、`results/T4c-ffi.md`、
  `results/T4b-provenance.md`、`results/T4e-races.md`、本文。

## 6. 不做的（明确排除）

- 不把 5 个模型合并成「T4 定理」：`spec/semantics.md` 已说明 T4 混了语言语义/编译器正确性/
  平台 ABI/信任闭包四类义务，合在一个命题里必然在边界上失败。
- 不声称「安全子集无 UB」的完整证明：`unsafe`（`H-LS-4`）、FFI 外部行为（`H-LS-5`）、
  静态栈（`H-LS-29`）与并发（`H-LS-3`/`H-LS-16`）仍是假设。
- 不用测试替代证明：`checker-spike`/`conformance`/`dossiers` 只能证伪。
