# spec/gs1-bench.md · G-S1/S2 安全子集验证协议（三层证据链）

> **上位**：[`00`](../00-LangSysQuanta-设计初稿.md) §1.1（G-S1 负例套件全拒 / G-S2 五试金石 ≥3）、
> 00 §8.1（15 条 UB 清单——唯一权威 oracle）、00 §8.2（`Safe(P)` 闭包定义，D24）、
> 00 §8.3（unsafe 审计：CI 统计**原语种类**）、00 §9（S0′/S0″/S1/S2 试金石交付线）、
> 00 §10.1（系统基准集与 Rust 对照实现要求）、00 §12（`LS-01/LS-04/LS-07/LS-15/LS-16`）；
> [`spec/ub.md`](ub.md)（15 条清单展开）、[`spec/test-matrix.md`](test-matrix.md)（双例规则，TM-0）。
> **工具**：[`tools/unsafe-surface`](../tools/unsafe-surface)（类目计数器）；
> [`tools/corpus-coverage`](../tools/corpus-coverage)（UB 矩阵断言，第二张表）。
> **状态**：`冻结（裁定点，2026-11-28；四项裁定见 §2）`。修订走本文档 Change Log（只增不减）。

---

## 1. 问题定义：三层证据链

「安全子集无 UB」不是一条测试，是**三面墙同时闭合**的正确性论证：

```
L1 静态墙    UB 触发形态进不了安全子集
             （检查器拒绝；负例套件全拒，00 §1.1 G-S1 判据）

L2 形式层    良型程序在操作语义模型中无 UB 事件
             （Lean 机械化定理；模型 judgment ⇔ 检查器判定对齐）

L3 运行时    解释器 / fuzz 实跑无 UB 痕迹
             （RTT v1 oracle；差分与反例重放）
```

G-S2 为配套度量：5 个系统试金石中 **≥3 个全程安全子集表达**；其余
`unsafe_surface`（**原语种类**，非行数/块数）≤ 5 且逐个带契约与审计条目
（00 §9 S0″ DoD；`LS-07` 超 Rust 同任务即无安全优势）。

三层相互独立、缺一即伪：L1 过但 L2 无 ⇒ 检查器在乱拒（sound 但不
complete 的代价不可知）；L2 过但 L1 弱 ⇒ 模型≠实现；L1/L2 过但 L3 无 ⇒
两边各自对、合起来错的缝隙敞开（解释器对齐缺陷、codegen 漂移）。

## 2. 冻结裁定（2026-11-28，仓库所有者）

| # | 自由度 | 裁定 | 语义 |
|---|---|---|---|
| D-GS1-1 | UB 矩阵断言位置 | **折叠进 `tools/corpus-coverage` 第二张表**，不新增门禁 | 十门结构不变；UB 行断言与双例断言同进程执行，一处豁免基线两表共用 |
| D-GS1-2 | unsafe_surface 计数口径 | **语法层类目枚举 v1**：类目表冻结于本文 §5；块内语句按类目归类计数**种类**（每类 1，不论次数）；未匹配形态按新种类计并强制登记 | `audited primitive` 注释解析留 v2（注释是档案约定非语法属性，不宜作机器口径） |
| D-GS1-3 | Rust 对照臂范围 | **阶段 0 仅 slab 一件**（`tests/gs1/rust-ref/slab.rs`） | 五试金石 Rust 参照随 S0″ 交付补齐（00 §10.1 对照实现分阶段） |
| D-GS1-4 | 判决时点 | **`LS-01` 判决绑 S0″（5/5 试金石齐）**；阶段 0/1 只出基线与进展，不出判决 | 中期 2/5 不满足判决统计口径（00 §9 S0″ DoD 以全集计） |

## 3. UB 矩阵（L1 静态墙的总账）

00 §8.1 的 15 行逐行登记三列状态；**机器断言面**（corpus-coverage 第二张表）：

| UB | 诊断码 | 安全子集可达 | 负例语料（现值 2026-11-28） | 状态 |
|---|---|---|---|---|
| UB-1 越界 | `E-LS-BOUNDS` | 否 | —（缺） | **缺口** |
| UB-2 悬垂引用 | `E-LS-ESCAPE` / `E-LS-REGION-ESCAPE` | 否 | `E-LS-REGION-ESCAPE-a5-ref-field.ls` | 已盖（子集） |
| UB-3 重复 drop | `E-LS-DROP` | 否 | —（缺） | **缺口** |
| UB-4 未初始化 | `E-LS-INIT` | 否 | `checker-spike: E-LS-INIT-read-uninitialized.ls` | 已盖 |
| UB-5 数据竞争 | `E-LS-RACE` | 否 | 5 条（r6-rw×2、r8×3） | 已盖 |
| UB-6 整数溢出 | `E-LS-OVERFLOW` | 否（定义 wrapping） | —（缺；非 UB 语义，负例为 checked trap 形态） | **缺口** |
| UB-7 除零/移位 | —（定义 abort） | 硬件 trap | 不适用（定义行为） | N/A |
| UB-8 null/野指针 | `E-LS-PROV` | 仅 unsafe | —（缺；unsafe 侧由 RTT 契约承担） | 缺口（unsafe 界） |
| UB-9 未对齐 | `E-LS-PROV` | 仅 unsafe | —（缺） | 缺口（unsafe 界） |
| UB-10 provenance | `E-LS-PROV` | 仅 unsafe | —（缺） | 缺口（unsafe 界） |
| UB-11 MMIO 重排 | `E-LS-PROV` + `Mmio[T]` | 否（安全 API） | —（缺；等 S0″ MMIO 驱动试金石） | 缺口（待 S0″） |
| UB-12 求值顺序 | —（规范定义） | 定义行为 | 不适用 | N/A |
| UB-13 栈溢出 | `W-LS-STACK`/`E-LS-RECURSION` | agent 可达 | `checker-spike`（recursion 档案） | 已盖（spike 界） |
| UB-14 drop 期间使用 | `E-LS-DROP` | 否 | —（缺） | **缺口** |
| UB-15 FFI unwind | `E-LS-ABI` | 否 | —（缺） | **缺口** |

断言规则（corpus-coverage 实装口径）：

1. 「安全子集可达＝否」且诊断码**已被实现面实发**的 UB 行 ⇒ 必须有负例，
   否则 FAIL——与双例门同一「实现面即语料面」哲学；
2. 未实现码自动豁免（现有 EXEMPT_BASELINE 机制覆盖，不双簿登记）；
3. **unsafe 界四行（UB-8/9/10/11）单独标注**：其负例属 RTT/Witness 契约
   面而非安全子集拒绝面，缺口登记不算 L1 失守——但 S0″ 起必须随
   `Mmio[T]`/审计原语落地补齐；
4. 缺口清单只减不增（与 TM-0 豁免基线同一治理：新增 UB 行必须同批带负例）。

## 4. 阶段 0 基线（本协议首个交付）

### 4.1 unsafe_surface 基线

`tools/unsafe-surface` 对全部现存 L-Sys 程序资产跑类目计数，产出
`results/gs1-baseline-<date>.md`：三档案（slab/views/recursion）＋
conformance 全语料;每程序一行 `{category-set, block-count, primitive-kinds}`。

### 4.2 Rust 对照首件（D-GS1-3）

`tests/gs1/rust-ref/slab.rs`：slab 分配器 Rust 参照实现（unsafe 逻辑上
对齐 dossiers/slab 的 `accept.ls`：build_free_list / ptr_read / ptr_write
三原语），量其 unsafe 种类数与块数；报告记入基线文档，作为 `LS-07`
对照臂 y 轴首点。**实现须 `cargo check` 通过**（功能等价性由人审对照
accept.ls，不设机器断言——参照实现不是被测物）。

### 4.3 基线报告内容

1. UB 矩阵现值快照（§3 表原样 + 六族缺口清单）；
2. unsafe_surface 基线表；
3. Rust 参照首件度量；
4. 三层证据链现状声明（L1 部分 / L2 已收口 / L3 待 SP4）；
5. 假设与外部依赖显式登记（模型公理、RTT 输入、M4 未建）。

## 5. unsafe_surface 类目表（v1，冻结）

| 类目 | 语法形态（unsafe 块内） |
|---|---|
| `deref-read` | `(*p)` / `*p` 作为右值（读经 rawptr） |
| `deref-write` | `(*p) = e` / `*p = e` |
| `ptr-cast` | `as rawptr[...]`（含反向） |
| `field-access-raw` | 经 rawptr 的字段访问 `(*p).f` |
| `extern-call` | `extern` 函数调用 |
| `asm` | `asm!` / 内联汇编形态 |
| `mmio-volatile` | `Mmio[T]` 底层 volatile 读写原语 |
| `null-check-manual` | `is_null()` / 手工判空分支 |

- 计数口径：**种类数 = 不同类目的基数**（D-GS1-2）；块数另计（次要指标）；
- `Mmio[T]`/`DmaToken` 出现在 unsafe 块外时按 00 §8.2「允许的安全 API」不计入；
- 未匹配语句 ⇒ `unknown` 类目，**按新种类计**且必须在基线报告登记
  （驱动类目表 v2 扩充——类目表变更走本文档 Change Log）；
- `unsafe_count`（checker-spike 现有块计数）保留为兼容指标，不替代种类数。

## 6. 阶段与判决

| 阶段 | 时机 | 内容 | 判据 |
|---|---|---|---|
| 0（本批） | S0′ 并行（任务号 `GS1-0`） | 协议冻结 + 矩阵断言接入 corpus-coverage + unsafe-surface 工具 + 基线报告 + Rust 参照首件 | 无判决：基线产出；六族缺口如实登记 |
| 1 | SP1 后（ls-sem 完整） | `ls audit` / `Safe(P)` 可执行判定；六族负例随检查器接管补齐（TM-0 收 1 强制）；环形缓冲升级为可执行组合正例 | 矩阵「否」行负例覆盖已实现码 100% |
| 2 | S0″（五试金石齐） | 无锁队列/中断/MMIO 落解释器模拟；**`LS-01` 判决 run**：`results/gs1-<run-id>.json`（5 试金石 × safe_subset / unsafe_surface / 审计完整性） | **≥3/5 全程安全子集 ⇒ 进 S1**；否则内存模型重设计（`LS-01`）；MMIO 必须 unsafe ⇒ `LS-15` |
| 3 | S1 末（M4 后） | L3 运行时墙：解释器差分 + RTT 反例重放 + fuzz 无崩溃 | 差分不一致即缺陷单；fuzz 崩溃冻结发布（`LS-04`） |

## 7. 与既有门禁/协议的关系

- TM-0 双例门是本协议 L1 墙的实现面粒度（按诊断码）；本矩阵是 UB 粒度
  （按 UB 行）——两表在 corpus-coverage 内同进程输出，豁免基线共享；
- G-S3/G-S5 的 run-id 判决纪律（00 §10.4）同样适用：`results/gs1-*.json`
  产出前禁止引用判决结论；
- Lean A 线（L2）不因本协议改动——它的边界与假设已在
  `results/A-line-summary.md` 逐条登记，本协议引用不重述。

## Change Log

| 版本 | 日期 | 变更摘要 |
|---|---|---|
| 1.0.0 | 2026-11-28 | 首次冻结：三层证据链定义（L1 静态墙/L2 形式层/L3 运行时）；四项裁定（D-GS1-1 矩阵断言折叠进 corpus-coverage 第二表 / D-GS1-2 类目枚举 v1 口径 / D-GS1-3 Rust 对照首件仅 slab / D-GS1-4 判决绑 S0″）；UB 矩阵 15 行三列登记与断言规则（unsafe 界四行单独标注）；unsafe_surface 类目表 v1（8 类目 + unknown 强制登记）；阶段 0–3 承接与 LS-01 判决 schema；任务号 GS1-0（工程先导，不入 06 里程碑表） |

> AI生成
