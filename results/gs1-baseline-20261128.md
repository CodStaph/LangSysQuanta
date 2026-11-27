# G-S1/S2 基线锚点（阶段 0，任务号 GS1-0）

> 状态：**基线（2026-11-28）**。协议：[`spec/gs1-bench.md`](../spec/gs1-bench.md)（冻结 1.0.0）。
> commit：`<本文件首次入库提交>`
> 本报告为**基线产出，非判决**（D-GS1-4：LS-01 判决绑 S0″，5/5 试金石齐）。
> 采集：`python tools/unsafe-surface`（2026-11-28 实跑）。

## 1. 三层证据链现状

| 层 | 状态 | 依据 |
|---|---|---|
| L1 静态墙 | **部分**：15 UB 行中 3 行负例已盖（UB-2/4/5），其余依赖豁免基线（实现面未接管处自动豁免）；双例门（TM-0）已强制新增码即刻双例 | `tools/corpus-coverage` 第二表实跑 PASS（covered: UB-2/4/5） |
| L2 形式层 | **已收口**：52 Lean 模块 0 sorry，UB-5/8/9/10/11/13/15 全机械化，"要么定义要么 UB" oracle 可计算 | [`results/A-line-summary.md`](A-line-summary.md)（2026-10-22） |
| L3 运行时 | **未建**：M4 解释器是 SP4 交付；差分/反例重放/fuzz 全部挂起 | 阶段 3 承接（spec/gs1-bench.md §6） |

## 2. unsafe_surface 基线（tools/unsafe-surface 实测，类目表 v1）

| 程序 | 块数 | **原语种类** | 类目 |
|---|---|---|---|
| `dossiers/slab/accept.ls` | 5 | **3** | deref-write / ptr-cast / field-access-raw |
| `dossiers/slab/reject.ls` | 1 | 1 | deref-read |
| `checker-spike` 语料（4 文件） | 4 | 0–1 | 纯值 unsafe / deref-read |
| 全库合计 | 11 | — | 上限 3（slab） |

要点：

- slab 的 3 类目与档案内 `audited primitive 1/2/3` 注释**一一对应**
  （build_free_list=块内写、`(*head).next`=经 rawptr 字段读、
  `(*f).next = s.free`=经 rawptr 字段写）——机器类目与人工审计锚点
  第一次交叉验证成立；
- 语义正确性说明：`is_null()` 出现在 safe 代码区（循环内判空），非
  unsafe 原语，不计入（类目表 `null-check-manual` 定义为块内手工判空）；
- checker-spike 的 `unsafe { x }` 纯值表达式零类目——kinds=0 是正确答案
  （无原语，只是效果标记）；
- `Mmio[T]`/`DmaToken` 按安全 API 不计入（00 §8.2）。

## 3. Rust 对照首件（D-GS1-3）

`tests/gs1/rust-ref/slab.rs`（编译验证 rc=0：`rustc --edition 2021
--crate-type lib`）：同一 slab 逻辑的 Rust 表达——
**unsafe 原语种类 3**（`(*slot).next` 写 / `(*head).next` 读 /
`(*f).next` 写，外加 `mem.add` 指针算术，按类目表并入 deref-write 族），
块数 3。

**LS-07 首个数据点：L-Sys slab（3 种 / 5 块）≈ Rust slab（3 种 / 3 块）——
不劣于 Rust。** 单点无统计力（如实：n=1，对照臂其余 4 试金石随 S0″ 补齐）。

## 4. 六族负例缺口（诚实登记，豁免基线覆盖）

| UB | 码 | 现状 | 归宿 |
|---|---|---|---|
| UB-1 越界 | E-LS-BOUNDS | 零负例（码未实现） | SP1 检查器落地时随双例门强制 |
| UB-3/14 drop 族 | E-LS-DROP | 零负例（码未实现） | 同上 |
| UB-6 溢出 | E-LS-OVERFLOW | 零负例（定义 wrapping 语义，负例为 checked trap 形态） | SP1，口径按 §8.1 行注 |
| UB-8/9/10 provenance | E-LS-PROV | checker-spike 实发、零负例（**已入豁免基线**） | unsafe 界四行：RTT/Witness 契约面，S0″ 审计原语落地时补 |
| UB-11 MMIO | E-LS-PROV | 零负例 | 等 S0″ MMIO 驱动试金石（Mmio[T] 安全 API 路径） |
| UB-15 FFI unwind | E-LS-ABI | 零负例（码未实现） | S1（FFI 面随 SVD/bindgen） |

矩阵机器断言已接入 corpus-coverage 第二表（D-GS1-1）；上表缺口全部落在
豁免基线内，**只减不增**：新增 UB 行或新实现码必须同批带负例，否则 FAIL。

## 5. 假设与外部依赖（显式登记）

1. 类目表 v1 为**语法层近似**：`unknown` 强制登记机制兜底；本基线 run
   全库零 unknown；
2. L2 的模型公理与信任具名化（HonorsVolatile/HonorsNounwind/Access.witness
   输入性）维持 A 线登记原状，本协议不重述、不增强；
3. Rust 参照的"逻辑等价"为人审结论（对照 accept.ls），无机器断言——
   参照非被测物；
4. `unsafe_count`（checker-spike 块计数）保留兼容，不作为种类口径。

## 6. 下一步（阶段 1/2 触发条件）

- 阶段 1（SP1 后）：六族负例随检查器接管补齐；环形缓冲组合正例；`ls audit`；
- 阶段 2（S0″）：无锁队列/中断/MMIO 试金石 + Rust 参照补齐 →
  `results/gs1-<run-id>.json` LS-01 判决（≥3/5 进 S1）。

> AI生成
