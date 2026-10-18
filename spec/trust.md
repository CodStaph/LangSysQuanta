# spec/trust.md · 信任闭包（skeleton）

> **状态**：`skeleton` + **spike 实现**（2026-10-18）：checker-spike 已读取 `trusted.lock` 的 TOML 子集；
> 最终 schema、advisory、`ls audit` 仍未完成。按 [`04 §0.1`](../04-S-1-执行计划.md)，本文件不进 S-1 阶段 DoD。
> **上位**：[`00 §8.2`](../00-LangSysQuanta-设计初稿.md)（安全子集闭包，决策 **D24**）、
> [`00 §7`](../00-LangSysQuanta-设计初稿.md)（`[policy]` 的 `trust` 旋钮）。
> **相关**：`H-LS-4`（`unsafe` 深层 soundness，`Out-of-scope`）、`H-LS-5`（FFI 外部行为，`Out-of-scope`）、
> `E-LS-TRUST`（失败关闭）。

## 接口（最终要定义什么）

| 项 | 说明 | 现状 |
|---|---|---|
| 闭包定义 | `Safe(P) ⇔ P 无 unsafe/rawptr/Ffi/Asm ∧ ∀q ∈ Reach(P): Safe(q) ∨ Trusted(q)` | `00 §8.2` 已给出 |
| `trusted.lock` | 每条 `(crate, version, content_hash, audit_report_hash, scope, assumptions, auditor, date)` | **spike 读取已实现**（见 §1）；TOML 完整 schema 未定 |
| 信任粒度 | 按 **API 范围**（`#[trusted(scope = …, assumptions = …)]`），非整 crate | `00 §8.2` 已定 |
| 分层 | T0 工具链 prelude/std、T1 项目钉住、T2 未信任 | `00 §8.2` 已定 |
| 失败关闭 | 缺条目 / 哈希不符 / 报告过期 ⇒ `E-LS-TRUST`，`Safe` 不成立 | **spike：内容哈希不符 ⇒ 不信任**；`E-LS-TRUST` 未单独实现 |
| advisory 与吊销 | `(crate, version, hash) → unsound`，由 `ls audit` 读取；离线模式失败关闭 | 未开始 |
| `ls audit` 输出 | 链接级 unsafe 面积、未判定项、lock 哈希校验结果 | 未开始 |

## 1. `trusted.lock` spike 格式（2026-10-18）

checker-spike 读取 TOML 子集（零依赖）：

```toml
# 注释
[[trusted]]
crate = "test.trusted_lock"
version = "0.1.0"
content_hash = "fnv1a64:a565573dcfc1ead7"
audit_report_hash = "fnv1a64:0123456789abcdef"
scope = "public-api"          # public-api | module | <fn-name>
assumptions = ["audited wrapper"]
auditor = "internal"
date = "2026-10-18"
```

规则：

- `content_hash` 必须匹配当前源文件；spike 使用 **FNV-1a 64**（先规范化 `CRLF→LF`），
  最终格式应换 SHA-256；
- `audit_report_hash` 非空才视为有审计报告（spike 不校验报告内容）；
- 缺条目、哈希不符、`audit_report_hash` 为空 ⇒ **失败关闭**（不信任）；
- 查找顺序：`LS_TRUSTED_LOCK` → 源文件同目录 `trusted.lock` → 当前目录 `trusted.lock`；
- `scope = "public-api"` 覆盖同 crate 的所有函数；`scope = "<fn>"` 只覆盖该函数。

用例：

- `tests/conformance/accept/accept-unsafe-trusted-lock.ls` + `trusted.lock`（匹配）；
- `tests/conformance/reject/E-LS-EFFECT-stale-trusted-lock.ls` + 陈旧哈希（失败关闭）。

> 这是**临时 schema**，不是 `trusted.lock` 的最终格式；最终需与 `00 §7` 的 `[policy].trust` 对齐。

## 待办

- [~] 定义 `trusted.lock` 的文件格式（TOML 子集已实现；最终 schema/哈希算法待定）；
- [ ] 明确 `Reach(P)` 的收集口径（泛型单态化结果、`ref[Trait]` 动态分派目标）；
- [ ] 明确「不做传递信任」的机器检查：lock 必须列出完整闭包，禁止间接信任；
- [ ] `ls audit` 的**离线**行为与 advisory 数据源（谁签发、如何验证）；
- [~] 与 `tests/conformance/reject` 的负例契约：已有「哈希错」1 条；缺失条目/过期报告待补；
- [ ] 片段声明登记表：定理只对「单线程 + 无 unsafe + 无 FFI + 无递归」成立（中断域见 `H-LS-16`）。

## 不做（本阶段明确排除）

- 不做运行期吊销（吊销 = 更新 lock）；
- 不背书 `unsafe` 块的深层 soundness（`H-LS-4` 仍为 `Out-of-scope`）；
- 不定义硬件后果（由 `Hw`/`Dma` 效果承担，见 `spec/effects.md`）。
