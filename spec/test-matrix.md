# spec/test-matrix.md · 测试设计规范与语料矩阵（双例规则）

> **上位**：[`00`](../00-LangSysQuanta-设计初稿.md) §1.1（G-S1：负例套件全拒）、00 §4.9/§6.4（20 条负例清单）、
> 00 §8.1（UB 清单）；[`AGENTS.md`](../AGENTS.md) 核心原则 3（一文件一错误、目录即注册）与原则 6（G4-07 RED 时序）；
> [`tests/conformance/README.md`](../tests/conformance/README.md)（约定 4：每码至少一正一负——本规范给出其机读形态与收紧节奏）；
> [`spec/REQ-registry.md`](REQ-registry.md) §1（追溯主键表，矩阵的数据母表）。
> **工具**：[`tools/corpus-coverage`](../tools/corpus-coverage)（双例存在性机断，接 `check-docs.sh` 第十门）。
> **状态**：`冻结（裁定点，2026-11-28；三项裁定见 §2）`。修订走本文档 Change Log（只增不减）。

---

## 1. 问题定义

L1 语料体是 G-S1 的回归底座，但存在两类不对称：

- **负例不对称**：43 在册码中 35 个零负例（`diag-extract --selfcheck` 机检输出）；
- **正例不对称**：正例仅 10 条且全为「单规则边界内侧」形态，**组合正例（≥3 规则同文件合法）为 0**——
  误报（检查器改一次、悄悄多拒一批合法程序）无回归防线。

本规范把「每码至少一正一负」（conformance 约定 4）升级为**机器可断言的双例规则**，
并给出等价类驱动的语料设计方法与分级收紧节奏。

## 2. 冻结裁定（2026-11-28，仓库所有者）

| # | 自由度 | 裁定 | 语义 |
|---|---|---|---|
| D-TM-1 | 双例规则是否升门禁 | **升门禁**：`tools/corpus-coverage` 接入 `check-docs.sh`（第十门） | 断言面 = **实现面即双例面**：凡被任一检查器实发的诊断码，必须 ≥1 负例且（ls-sem 判定范围内的）≥1 正例；未实现码进豁免表（随实现推进自动迁移） |
| D-TM-2 | 变异器 | **先做 spike 不入库** | `tools/corpus-mutate` 以 `.temp/` 内 spike 形态运行；机器生成候选负例 → 检查器实拒 → 人工审定队列；人审通过率数据出来后再决定转正（转正须走本文档 Change Log） |
| D-TM-3 | 组合正例归属 | **进 `tests/conformance/accept/`** | 误报回归属于检查器门日常职责，conformance-run 每次全量执行；`dossiers/` 保留档案语义不承担回归职责 |

## 3. 双例规则（机器断言口径）

### 3.1 负例规则

1. `reject/*.ls` 首行 `// EXPECT: <code>`（既有约定）；
2. **一文件一错误**：文件内恰好一处触发点；触发点行尾注释标 `// E-LS-…`（既有惯例）；
3. 触发条件注释必须写明**等价类**（§4 表格式），无等价类标注的负例按违例报 INFO。

### 3.2 正例规则

| 档 | 定义 | 判定 |
|---|---|---|
| **边界内侧**（boundary） | 恰好合法的最小写法，距同码负例一步之遥（改一行即触判） | ls-sem `rc=0` |
| **组合**（combined） | 一个程序同时合法使用 ≥3 类规则（如 region+borrow+effect+契约/spawn） | ls-sem `rc=0`；文件头注释列举叠加的规则集与各自条款 |
| **回归**（regression） | 曾经被误报、随 A 类缺陷修复同批入库的合法用例 | ls-sem `rc=0`；`results/` 缺陷单链接（REQ-registry 承接任务列同批更新） |

正例一文件一焦点：组合正例的「焦点」= 其叠加规则集本身（防误报的组合面）。

### 3.3 断言算法（`tools/corpus-coverage`）

1. **实现面**导出：`tools/ls-sem/src/**.rs` 与 `tools/checker-spike/src/**.rs` 中实发的
   `E-LS-`/`W-LS-` 码集合（机械扫源码字符串常量）；B-LS 码（`spec/bls.md` §5.1）以
   `bootstrap/` 实现同法导出；
2. **双例面**核对：实现面每码——
   - 负例：`tests/conformance/{reject,checker-spike/reject,bootstrap/bls/tests/reject}/` 首行 EXPECT 命中；
   - 正例：ls-sem 判定范围（reject/ 与 accept/ 目录族）内的码需 accept 侧 ≥1 条
     **同名规则族**正例（按 REQ-registry §1 正例列登记，机器核对登记路径存在）；
3. **豁免表**：未实现码 = 自动豁免（无需人工维护）；实现面新增码未带双例 ⇒ FAIL——
   「实现面即双例面」与 G4-07「实现提交同批带语料」同一哲学，语料可先于实现落地
   （RED 状态），实现落地后豁免即刻失效；
4. 输出：`corpus-coverage: PASS/FAIL (impl=N, dual=N, exempt=M, missing=[...])`。

## 4. 等价类矩阵（设计方法 + 首批落地表）

每码一张等价类表，行 = 触发空间的等价类（维度 × 取值），缺哪格、补哪个负例即机械可读。
**首批落地**（2026-11-28，全部经 ls-sem 探针实测定形；设计稿原表的三处修订如注）：

| 码 | 等价类维度 | 已覆盖类 | 本批落地（实测形态） |
|---|---|---|---|
| `E-LS-ALIAS` | 别名来源 × 写点位置 × 访问类型 × 下标确定性 | borrow×同域、freeze、borrow×嵌套域 | **+动态下标**：`borrow p[i]` 后写 `p[j]`——下标不可静态判定 ⇒ 整 place 保守覆盖（`E-LS-ALIAS-r5-dynamic-index-write.ls`） |
| `E-LS-MOVE` | move 后使用形态 | 变量重绑（spike：box-move） | **+ls-sem 重绑形态**（`E-LS-MOVE-rebind-after-move.ls`）＋边界内侧正例 `accept-move-use-target.ls` |
| `E-LS-MODE` | ref 值逸出形态 | —（新等价类） | **+直接返回 ref 本体**：探针实测此形态落在 MODE 门（先于区域约束求解），期望码按实判定为 `E-LS-MODE`；＋边界内侧正例 `accept-mode-return-owned.ls` |
| `E-LS-IRQ` | 锁序方向 | 逆序获取（rank2→rank1） | **+合法序内侧正例** `accept-irq-rank-order.ls`（rank1→rank2 单调栈合法） |
| `E-LS-REGION-ESCAPE` | 逃逸载体 | ref 字段（聚合，A-5） | 聚合形态已覆盖；「直接 return ref」经实测归 `E-LS-MODE`（见上行），两件合盖逃逸空间 |
| `E-LS-RACE` | 跨域对象形态 × 操作 | box/ref/val×spawn、shared 读写 | 组合正例 `combined-spawn-iso-atomic.ls` 兼作 R8 合法路径正例 |

**探针结论登记**（边界复核位产出，如实记录）：

1. `ref` 字段别名写（R4 族、原设计稿目标）：ls-sem 现版本**直接 ACCEPT**
   （该写路径未实现检查）⇒ 按 D-TM-1「实现面即双例面」不建语料；待 surface
   实现后本格转正（RED 语料允许先行落地）；
2. `frozen` 跨域（原边界复核位）：实测 `frozen[T]` 非 surface 参数形态
   （类型检查报「has no field」）；语义层 `m=frozen` 的 surface 表达是 **`val` 句柄**
   （semantics.md §2.3 R8-transfer `m ∈ {iso, atom, frozen}` ⇔ 报文 `iso/atom/
   region-safe val`）——实现自洽，**无缺陷**，跨域 frozen 值的正/负例即
   `val-static`/`val-local-region` 既有语料，不另建。

首批**组合正例**（`accept/combined-*.ls`，D-TM-3）：

| 文件 | 叠加规则 | 依据 |
|---|---|---|
| `combined-region-borrow-contract.ls` | region 分配 + borrow 作用域 + R5 写回 + `requires`/`ensures` 契约 | 00 §5.9 骨架收敛（实测要点：值以 by-copy 传出 region，region 内不返回） |
| `combined-spawn-iso-atomic.ls` | iso 转移 + spawn/join + R6 方法形原子操作 | 00 §5.9 / accept-r8 族组合 |

组合正例仅收 **ls-sem 实际判定的 surface**（含 spike 族构造的组合作 SP2 迁移项登记）。

> **边界复核位**（§3.2 之外的设计件）：负例族中混入「按规范应被接受」的边界位；
> 若实判为拒，产出缺陷单而非语料；该位不计入双例缺口。本批两个复核位结论见上表。

## 5. 分级收紧节奏

| 阶段 | 时点 | 面上要求 | 机器保证 |
|---|---|---|---|
| 收 0（本批） | 立即 | §4 首批表全落地（4 负例 + 2 组合正例 + 1 边界复核位） | `corpus-coverage` 接入十门并对**存量实现面**立即生效 |
| 收 1（SP2 起） | 每新接检查项 | 同批 ≥1 正 ≥1 负（06 §2 条 2） | corpus-coverage 与 red-timing 双机断（前者管双例、后者管 RED 时序） |
| 收 2（S0′ 收官） | 里程碑 | reject 覆盖**全部已接**码 + 00 §4.9/§6.4 的 20 条负例清单全额 | corpus-coverage 零缺失 + 里程碑 QEMU 全量 |
| 收 3（S0″） | 5 试金石 | ≥3/5 全程安全子集 | 试金石判定走 06 §1 SP6 口径 |

## 6. oracle 分层

| 层 | oracle | 用法 | 现状 |
|---|---|---|---|
| O1 | 判定器自身（ls-sem/spike/rustc） | conformance-run 全量 | 已运行 |
| O2 | Lean 机械模型（A 线 8 条 UB） | 反例重放：模型反例 → 实现侧必须同判（`bad()` 重放 REJECT 先例，spec/t4-proof.md） | 部分在册 |
| O3 | M4 解释器 × 检查器差分 | 判定一致；不一致即缺陷单（06 SP4 口径） | 待 SP4 |
| O4 | 变异器（D-TM-2 spike） | accept 语料按算子变异 → 候选负例人审 | `.temp/` spike |

## Change Log

| 版本 | 日期 | 变更摘要 |
|---|---|---|
| 1.0.0 | 2026-11-28 | 首次冻结：三项裁定（D-TM-1 双例升门禁入十门 / D-TM-2 变异器先 spike 不入库 / D-TM-3 组合正例进 accept/）；双例规则机读口径与断言算法（实现面即双例面、未实现码自动豁免）；等价类矩阵方法 + 首批落地表（全部探针实测定形：ALIAS 动态下标、MOVE 重绑、MODE 直返 ref；正例 MODE/MOVE/IRQ 边界内侧 ×3 + 组合 ×2；探针结论 2 项——R4 写路径未实现转正待 surface、frozen/val surface 映射实现自洽）；分级收紧节奏（收 0–3）；oracle 四层（O1–O4）；任务号 TM-0（工程先导，不入 06 里程碑表）。D-TM-2 spike 首批数据：4 算子 ×11 accept 语料 → 7 候选、3 实拒（42%），M1 零产出/M3 全放行系算子模板与语义边界限制，转正评审待更多数据 |

> AI生成
