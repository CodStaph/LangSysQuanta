# Q4 · `Unsafe` 终止规则（effects.md §4.1）

状态：**检查器规则已落地（spike）；Q4 未完全关闭**
日期：2026-10-18
上位：[`spec/effects.md`](../spec/effects.md) §4、[`spec/trust.md`](../spec/trust.md)

## 已实现（checker-spike）

| 条件 | 实现 | 代码位置 |
|---|---|---|
| 1. 非 `unsafe fn`；参数/返回不含 `rawptr` | `FnDef.is_unsafe` + 参数/返回 token 扫描 | `analyze()` |
| 2. 模块 `#[cap(Unsafe)]` 或显式 `Cap[Unsafe]` 值 | 解析 module 属性；扫参数/返回/函数体 | `Program.module_attrs` / `analyze()` |
| 3. `ls audit` + `trusted.lock` / crate 审计覆盖 | `#[trusted]` 属性，或模块 `#[cap(Unsafe)]` 近似 | `analyze()` |

判定：

- 有 unsafe 面积、无 cap 上下文 ⇒ `E-LS-CAPCTX`；
- 有 cap、有 `eff(...)` 但缺 `Unsafe`，且不是安全包装 ⇒ `E-LS-EFFECT`；
- 正例：`tests/conformance/accept/accept-unsafe-termination.ls`；
- 负例：`tests/conformance/reject/E-LS-EFFECT-unsafe-wrapper-exposes-rawptr.ls`。

## 验证

```text
tests/conformance/accept    SUMMARY PASS
tests/conformance/reject    SUMMARY PASS
dossiers/slab               expected=7 actual=7
```

## 未完成（不得写成 Q4 关闭）

- 未读取 `trusted.lock`；模块 cap 作为 audit 上下文只是 spike 近似；
- 未展开公开 struct 字段的传递 `rawptr` 暴露；
- 未检查 `#[boundary]` trampoline 的效果并集；
- `H-LS-4` 仍是 `Out-of-scope`，安全包装的 soundness 由信任闭包承担。

## 后续

S0′ 的 `ls-sem` 实现：
1. 解析 `trusted.lock`，把审计条目与 unsafe 面积关联；
2. 计算 struct 字段的传递 `rawptr` 暴露；
3. 在 `#[boundary]` 处做效果并集，禁止 trampoline 吞掉 `Unsafe`。
