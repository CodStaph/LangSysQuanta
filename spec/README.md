# spec/ · S-1 规范清单

> 上位：[`04-S-1-执行计划.md`](../04-S-1-执行计划.md) §0/§4。
> **规则**：不要创建空文件冒充「已完成」。状态只有 `未开始 / 草稿 / 评审中 / 冻结`。

| 文件 | 类别 | 状态 | 负责人 | DoD（摘要） |
|---|---|---|---|---|
| `ub.md` | 必须 | **草稿（15 条 + oracle 已列）** | — | 15 条 UB + oracle + provenance 决策 |
| `modes.md` | 必须 | **草稿（Q1 冻结）** | 语言负责人 | 区域格 + R1–R8 + 约束推断 + 视图规则 |
| `effects.md` | 必须 | **草稿（gate matrix + Unsafe 终止）** | — | 效果集 + gate matrix + `Unsafe` 终止规则 |
| `image.md` | 必须 | **草稿（不变量 + loader 伪代码）** | — | header/段/cap 表/验签/防回滚/loader 伪代码 |
| `baremetal.md` | 支撑 | 未开始 | — | 属性/asm/link/naked/入口/C 类型映射 |
| `resource.md` | 支撑 | 未开始 | — | `defer`/`#[must_release]`/泄漏检查 |
| `cap-context.md` | 支撑 | 未开始 | — | 模块 `#[cap]` + 每模块旋钮 |
| `toolchain.md` | 支撑 | 未开始 | — | `[target]` + SVD/bindgen + 可复现（可 skeleton） |
| `cost.md` | skeleton | **skeleton** | — | 只写接口与待办 |
| `trust.md` | skeleton | **skeleton** | — | 只写接口与待办 |
| `coherence.md` | skeleton | **skeleton** | — | 只写接口与待办 |
| `langSysQuanta.ebnf` | 必须 | 未开始 | — | 覆盖 00 §5 全部代码块 |
| `bls.md` | 支撑（bootstrap） | **草稿（M0 已实现）** | 工具链 | B-LS 子集 / seed 契约 / 阶段判据 |

## 评审要求

- 每份规范必须引用对应的 00 章节、`H-LS-*` 与 ADR；
- 每条规则必须有正例与负例（`tests/conformance/`）；
- 规范与 00 冲突时：语义以 00 为准，边界/部署以 02 为准，交付以 04 为准；
- 冻结后修改必须走 02 的 ADR 或 04 §9 的变更规则。
