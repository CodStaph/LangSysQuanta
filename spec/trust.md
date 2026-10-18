# spec/trust.md · 信任闭包（skeleton）

> **状态**：`skeleton` —— 只写接口与待办；按 [`04 §0.1`](../04-S-1-执行计划.md)，本文件不进 S-1 阶段 DoD。
> **上位**：[`00 §8.2`](../00-LangSysQuanta-设计初稿.md)（安全子集闭包，决策 **D24**）、
> [`00 §7`](../00-LangSysQuanta-设计初稿.md)（`[policy]` 的 `trust` 旋钮）。
> **相关**：`H-LS-4`（`unsafe` 深层 soundness，`Out-of-scope`）、`H-LS-5`（FFI 外部行为，`Out-of-scope`）、
> `E-LS-TRUST`（失败关闭）。

## 接口（最终要定义什么）

| 项 | 说明 | 现状 |
|---|---|---|
| 闭包定义 | `Safe(P) ⇔ P 无 unsafe/rawptr/Ffi/Asm ∧ ∀q ∈ Reach(P): Safe(q) ∨ Trusted(q)` | `00 §8.2` 已给出 |
| `trusted.lock` | 每条 `(crate, version, content_hash, audit_report_hash, scope, assumptions, auditor, date)` | 字段已定，格式未定 |
| 信任粒度 | 按 **API 范围**（`#[trusted(scope = …, assumptions = …)]`），非整 crate | `00 §8.2` 已定 |
| 分层 | T0 工具链 prelude/std、T1 项目钉住、T2 未信任 | `00 §8.2` 已定 |
| 失败关闭 | 缺条目 / 哈希不符 / 报告过期 ⇒ `E-LS-TRUST`，`Safe` 不成立 | 规则已定，检查未实现 |
| advisory 与吊销 | `(crate, version, hash) → unsound`，由 `ls audit` 读取；离线模式失败关闭 | 未开始 |
| `ls audit` 输出 | 链接级 unsafe 面积、未判定项、lock 哈希校验结果 | 未开始 |

## 待办

- [ ] 定义 `trusted.lock` 的文件格式（推荐 TOML，需与 `00 §7` 的 `[policy].trust` 对齐）；
- [ ] 明确 `Reach(P)` 的收集口径（泛型单态化结果、`ref[Trait]` 动态分派目标）；
- [ ] 明确「不做传递信任」的机器检查：lock 必须列出完整闭包，禁止间接信任；
- [ ] `ls audit` 的**离线**行为与 advisory 数据源（谁签发、如何验证）；
- [ ] 与 `tests/conformance/reject` 的负例契约：缺失条目、哈希错、过期报告各一条；
- [ ] 片段声明登记表：定理只对「单线程 + 无 unsafe + 无 FFI + 无递归」成立（中断域见 `H-LS-16`）。

## 不做（本阶段明确排除）

- 不做运行期吊销（吊销 = 更新 lock）；
- 不背书 `unsafe` 块的深层 soundness（`H-LS-4` 仍为 `Out-of-scope`）；
- 不定义硬件后果（由 `Hw`/`Dma` 效果承担，见 `spec/effects.md`）。
