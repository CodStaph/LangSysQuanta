# spec/ · S-1 规范清单

> 上位：[`04-S-1-执行计划.md`](../04-S-1-执行计划.md) §0/§4。
> **规则**：不要创建空文件冒充「已完成」。状态只有 `未开始 / 草稿 / 评审中 / 冻结`。

| 文件 | 类别 | 状态 | 负责人 | DoD（摘要） |
|---|---|---|---|---|
| `ub.md` | 必须 | **草稿（15 条 + RTT v1 + oracle）** | — | 15 条 UB + oracle + RTT v1 provenance（Q5 已关闭） |
| `modes.md` | 必须 | **草稿（Q1 冻结；Q8 `val`/Q9 初始化已定）** | 语言负责人 | 区域格 + R1–R8 + 约束推断 + 视图规则 + `val` 别名（ADR-31）+ 未初始化 `let` |
| `semantics.md` | 必须 | **草稿（18 条规则 + `Σ'`/`H` + T1a/T1–T4）** | 语言负责人 | 18 条小步规则；R1–R8 带 `⊣ Σ'`/`H` 写回；L1/L2；T1a/T1–T3 证明草稿；T4 明确未证明 |
| `t4-proof.md` | 支撑（证明） | **草稿（M0/M1 完成，M2/M3 核心写出）** | 语言负责人 | M0/M1 纸面证明；M2 L-Adequacy/Preservation/L4 + M3 核心（S10/S11/S14 条件，S12 收口）；`bad()` 重放 REJECT；语义冻结未通过（完整 M3/Progress/R5-R8 正负例/M4-M5 缺）；T4a 未证明 |
| `effects.md` | 必须 | **草稿（gate matrix + Unsafe 终止；Q4 spike 已落地）** | — | 效果集 + gate matrix + `Unsafe` 终止三条件；checker-spike 已实现 `trusted.lock` 子集、传递 `rawptr`、boundary 并集；最终 schema 待 `ls-sem` |
| `image.md` | 必须 | **草稿（不变量 + loader 伪代码）** | — | header/段/cap 表/验签/防回滚/loader 伪代码 |
| `baremetal.md` | 支撑 | **草稿（Q6 C ABI v1 已定）** | — | 属性/asm/link/naked/入口/C ABI 映射；ABI 冻结套件待 S1 |
| `resource.md` | 支撑 | **草稿（defer/must_release 规则）** | — | `defer` LIFO/错误路径、`#[must_release]`、泄漏检查；checker 仅 `let _` |
| `cap-context.md` | 支撑 | **草稿（Q2 决定已定）** | — | 模块 `#[cap]` 词法/不可放宽/无继承 + 每模块旋钮；子模块检查待 `ls-sem` |
| `toolchain.md` | 支撑 | **草稿（Q7 三目标矩阵已定）** | — | `[target]` + SVD/bindgen + 可复现；Q7-1…Q7-4 待 S1/S2 |
| `cost.md` | skeleton | **skeleton** | — | 只写接口与待办 |
| `trust.md` | skeleton | **skeleton** | — | 只写接口与待办 |
| `coherence.md` | skeleton | **skeleton** | — | 只写接口与待办 |
| `foundations.md` | 支撑 | **skeleton（选型 + 映射 M1–M10）** | — | 数学工具选型、替换清单、纪律 F1–F6、落地顺序 |
| `langSysQuanta.ebnf` | 必须 | **草稿（v2.1，113 产生式，覆盖 §5.1–§5.11）** | — | 覆盖 00 §5 全部代码块；`tests/syntax` 44/44 PASS |
| `langSysQuanta.gbnf` | 派生 | **生成物（由 EBNF 机械导出）** | — | `tools/ebnf-parse --gbnf`；`tests/syntax/gbnf_diff.py` golden diff |
| `elaboration.md` | 支撑（G4） | **草稿（surface→core 合同 + 片段矩阵）** | 语言负责人 | 113 产生式归属、脱糖 E1–E20、F0/F_thr/F_unsafe/F_ffi 矩阵；elaborator 未实现 |
| `bls.md` | 支撑（bootstrap） | **草稿（M0 已实现）** | 工具链 | B-LS 子集 / seed 契约 / 阶段判据 |

## 评审要求

- 每份规范必须引用对应的 00 章节、`H-LS-*` 与 ADR；
- 每条规则必须有正例与负例（`tests/conformance/`）；
- 规范与 00 冲突时：语义以 00 为准，边界/部署以 02 为准，交付以 04 为准；
- 冻结后修改必须走 02 的 ADR 或 04 §9 的变更规则。
