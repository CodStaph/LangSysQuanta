# Q4 · `Unsafe` 终止规则（effects.md §4.1）

状态：**检查器规则已落地（spike）；Q4 未完全关闭**
日期：2026-10-18
上位：[`spec/effects.md`](../spec/effects.md) §4、[`spec/trust.md`](../spec/trust.md) §1

## 已实现（checker-spike）

| 条件 | 实现 | 代码位置 |
|---|---|---|
| 1. 非 `unsafe fn`；参数/返回不含 `rawptr` | `FnDef.is_unsafe` + 参数/返回 token；递归展开按值 struct 字段 | `analyze()` / `type_exposes_rawptr()` |
| 2. 模块 `#[cap(Unsafe)]` 或显式 `Cap[Unsafe]` 值 | 解析 module 属性；扫参数/返回/函数体 | `Program.module_attrs` / `analyze()` |
| 3. `ls audit` + `trusted.lock` / crate 审计覆盖 | 读取 `trusted.lock`（crate/scope/content_hash/audit_report_hash）或 `#[trusted]` | `parse_trusted_lock()` / `trusted_entry()` |

附加：

- `#[boundary]` 参数只允许 `val`/`iso`/标量；`ref`/`box`/`rawptr`/`shared` ⇒ `E-LS-PROFILE`；
- `#[boundary]` 的 `eff` 必须是直接 callee 效果的并集；缺 `Unsafe` ⇒ `E-LS-EFFECT`；
- `trusted.lock` 使用失败关闭：内容哈希不符/审计哈希为空 ⇒ 不信任。

## 用例

```text
tests/conformance/accept/accept-unsafe-termination.ls        #[trusted]
tests/conformance/accept/accept-unsafe-trusted-lock.ls      trusted.lock
tests/conformance/accept/accept-boundary-effect-union.ls    boundary 并集
tests/conformance/reject/E-LS-EFFECT-unsafe-wrapper-exposes-rawptr.ls
tests/conformance/reject/E-LS-EFFECT-rawptr-in-public-field.ls
tests/conformance/reject/E-LS-EFFECT-stale-trusted-lock.ls
tests/conformance/reject/E-LS-EFFECT-boundary-drops-unsafe.ls
```

## 验证

```text
tests/conformance/accept    SUMMARY PASS
tests/conformance/reject    SUMMARY PASS
dossiers/slab               expected=7 actual=7
```

## 未完成（不得写成 Q4 关闭）

- `trusted.lock` 仍是临时 TOML 子集：FNV-1a 64、`audit_report_hash` 只查非空；
  最终 schema/哈希算法/advisory/过期策略未定；
- mode 包装类型（`ref/val/box/...`）内的 struct 字段未递归展开；
- 未计算跨 crate 的 `Reach(P)`；`trusted.lock` 必须列出完整闭包这一条未实现；
- 模块 `#[cap(Unsafe)]` 在 spike 中被视为 unsafe-API 边界，不执行 Q4 判定；
- `H-LS-4` 仍是 `Out-of-scope`，安全包装的 soundness 由信任闭包承担。

## 后续

S0′ 的 `ls-sem` 实现：
1. 固定 `trusted.lock` 最终 schema（SHA-256、advisory、过期）；
2. 计算跨 crate `Reach(P)` 与 mode 包装字段的传递 `rawptr` 暴露；
3. 在 `#[boundary]` 处做完整效果并集，禁止 trampoline 吞掉 `Unsafe`。
