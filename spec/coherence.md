# spec/coherence.md · trait coherence 与 impl 可见性（skeleton）

> **状态**：`skeleton` —— 只写接口与待办；按 [`04 §0.1`](../04-S-1-执行计划.md)，本文件不进 S-1 阶段 DoD。
> **上位**：[`00 §6.5`](../00-LangSysQuanta-设计初稿.md)（`comptime`/单态化/coherence 选择，决策 **R-11**）、
> [`00 §5.2`](../00-LangSysQuanta-设计初稿.md)（impl 与 `dyn` 语法）。
> **相关**：风险 `LS-24`（orphan 场景表达力不足）、`R-3`（trait coherence / 孤儿规则会抬高组合复杂度）。

## 接口（最终要定义什么）

| 项 | 说明 | 现状 |
|---|---|---|
| 默认可见性 | `#[open]` 为默认：本地类型 + 本地 trait 可 impl | `00 §6.5` 已定 |
| 封闭与孤儿 | foreign × foreign 禁止；`#[sealed]` 显式封闭；`#[orphan]` 仅 S4 | `00 §6.5` 已定 |
| impl 集合范围 | crate 局部：本 crate 的 impl 集 + orphan 检查 | `00 §6.5` 已定 |
| impl semver 规则 | 新增 impl 是否破坏下游（重叠风险） | 未开始 |
| vtable ABI | `dyn` 分派的目标布局、`ref[Trait]` 单态化与动态分派边界 | 未开始 |
| 冲突诊断 | 重叠 impl 的错误码与 fix-it 建议 | 未开始 |

## 待办

- [ ] 把 `[open]`/`[sealed]`/`[orphan]` 的判定写成可执行规则（检查器可验，参考 `tools/checker-spike` 的做法）；
- [ ] 定义重叠 impl 的**诊断码**（当前 00 §11 未列，需要新增并登记到 00 §12）；
- [ ] impl semver：新增 impl 何时算破坏性变更（与 `H-LS-12`「稳定 ABI 覆盖所有类型」相关）；
- [ ] `dyn` vtable 的字段顺序与 ABI 冻结条件（与 `image.md` 的 loader 契约交叉）；
- [ ] 与 `#[orphan]`（S4）的边界：S-1 阶段只做「禁止 foreign × foreign」，不实现 `#[orphan]`；
- [ ] 至少 2 条负例进 `tests/conformance/reject`（重叠 impl、foreign × foreign）。

## 不做（本阶段明确排除）

- 不实现 `#[orphan]` 注册表（S4，且取决于 `LS-24` 的重估结论）；
- 不定义跨 crate 的 coherence 传播规则；
- 不做 LSP/自动补全层面的 impl 搜索。
