# spec/diagnostics.md · 诊断码登记处（发布版）

> **状态**：`草稿`，由 [`00 §6.4`](../00-LangSysQuanta-设计初稿.md) 机械抽取。
> **权威**：本文件是 `E-LS-*` / `W-LS-*` 的**机器可读登记处**。
> [`tools/doc-lint`](../tools/doc-lint) 只读本文件 + [`bls.md`](bls.md) 的 B-LS 扩展表，
> 检查“被使用的诊断码是否已定义”。
> **B-LS 专属码**（`E-LS-UNSUPPORTED`、`E-LS-MAIN`）登记在 [`bls.md` §5.1](bls.md)。
> `00 §6.4` 保留设计叙述；新增/修改码位必须同时改两边。

---

## 1. 码表

| 码 | 含义 | 级别 | fix-it |
|---|---|---|---|
| `E-LS-REGION-ESCAPE` | 引用/box 逃出 region | Enforced | 改 `val`/复制/改 `Alloc[Heap]` |
| `E-LS-ALIAS` | 区域级别名冲突 | Enforced | 缩短借用/改 `val`/`cell` |
| `E-LS-ESCAPE` | 存活期超界 | Enforced | 提升 region/复制 |
| `E-LS-RACE` | mode 不允许跨域 | Enforced | 改 `iso`/`val`/`shared` |
| `E-LS-CAP` | 令牌缺失/越界 | Enforced | 补 `Cap[...]`/缩小范围 |
| `E-LS-UNSAFE` | 安全块用裸内存 | Enforced | 包 `unsafe` |
| `E-LS-INIT` | 未初始化 | Enforced | 初始化/`MaybeUninit` |
| `E-LS-MOVE` | 使用已 move 的值 | Enforced | 复制/重排/改 `iso` |
| `E-LS-UNIQ` | 唯一性被破坏 | Enforced | `recover`/复制 |
| `E-LS-DROP` | 重复 drop / profile 禁止隐式 drop | Enforced | 显式 `release` |
| `E-LS-EFFECT` | 边界效果缺失 | Enforced(seal) | 补 `eff(...)` |
| `E-LS-LAYOUT` | 布局/ABI 不符 | Enforced | 改 `#[repr]` |
| `E-LS-ABI` | 泛型/布局跨 FFI 不稳定 | Enforced | 改 `extern "C"` 签名 |
| `E-LS-BOUNDS` | 越界 | Enforced | 加长度检查/契约 |
| `E-LS-OVERFLOW` | 常量溢出 | Enforced | `wrapping_*`/`checked_*` |
| `E-LS-RECURSION` | kernel 递归 | Enforced | 改迭代/展开 |
| `E-LS-COMPTIME` | comptime fuel 耗尽/越权 | Enforced | 结构化递归/移出运行时 |
| `E-LS-PROV` | provenance 契约不满足 | Enforced(unsafe) | 补契约/`Witness` |
| `E-LS-IRQ` | 中断域/锁 rank 违反 | Enforced | 调整 rank/移出 ISR |
| `E-LS-MATCH` | `match` 不穷尽 / 模式类型不符 | Enforced | 补分支/改模式 |
| `E-LS-ARITY` | 调用实参个数/类型位置不匹配 | Enforced（片段） | 修正实参/签名 |
| `E-LS-DUP` | 重复定义：函数/字段/变体同名 | Enforced（片段） | 改名/合并 |
| `E-LS-BUFFER-CAP` | `Buffer[T]` 超出静态容量 | Enforced（片段） | 扩容 / `push` 前检查 `len < cap` |
| `E-LS-MONO-SIZE` | 单态化体积超预算 | Reported | 用 `dyn`/拆分泛型 |
| `E-LS-STATIC` | `static mut` 或非法 `static` 类型 | Enforced | 改 `val`/`shared`/`cell` |
| `E-LS-ERROR-SIZE` | 模块错误枚举超预算 | Enforced | 合并/`Other(u16)` |
| `E-LS-TRUST` | `Trusted` 声明不完整/哈希不符 | Enforced | 补审计元数据/重新审计 |
| `E-LS-PROFILE` | 非法 profile 依赖/跨域参数 | Enforced | 改依赖/加 `#[boundary]` |
| `E-LS-COHERENCE` | orphan impl / impl 重叠 / sealed 被实现 | Enforced | 用 newtype/本地 trait/`#[sealed]` |
| `E-LS-LEAK` | `defer`/`#[must_release]` 未执行或重复执行 | Enforced | 加 `defer`/显式 `release` |
| `E-LS-STACK` | 递归上界超 `stack_bound` | Enforced | 降低 bound/改显式栈 |
| `E-LS-CAPCTX` | 模块 cap 放宽/嵌套越权 | Enforced | 收紧 `#[cap]`/显式参数 |
| `E-LS-ATTR` | 未知/不适用的属性（封闭集之外，`spec/langSysQuanta.ebnf` 的 `builtin_attr`） | Enforced | 删除属性或改用封闭集内的属性 |
| `E-LS-DIAL` | 安全旋钮降级缺契约/证据 | Enforced | 补 `requires`/CI 证据 |
| `W-LS-STACK` | 递归深度/栈上界不可判 | Reported | 改迭代/加 `#[stack(n)]` |
| `W-LS-UNSAFE-DENSITY` | unsafe 密度超阈值 | Reported | 审查/重构 |
| `W-LS-NONDET` | 隐式非确定性 | Reported | 标 `#[nondet]` |
| `W-LS-OVERFLOW` | kernel 静默回绕 | Reported | `checked_*` |
| `W-LS-FIXIT-UNSAFE` | 自动修复试图引入 unsafe（拒绝） | Reported | 人工处理 |
| `W-LS-WCET` | 最坏情况上界（栈/中断延迟）超限 | Reported | 缩短临界区/拆分函数 |

---

## 2. 规则

1. **新增码位**：先改本文件 → 再改 `00 §6.4` → 再实现；三步缺一不可。
2. **正负例**：每个码至少一个正例与一个负例（`tests/conformance/` 或对应
   `tools/*/tests/`；例如 `E-LS-BUFFER-CAP` 在 `tools/ls-sem/tests/surface.rs`）。
3. **错误 vs 报告**：`E-LS-*` 是错误（拒绝编译），`W-LS-*` 是警告/报告；不得混用。
4. **B-LS 专属码不进本表**：实现进度/入口约束登记在 [`bls.md` §5.1](bls.md)。
5. **改名**：必须同时改实现、测试、文档；旧码保留一版弃用说明，不得静默消失。

---

## 3. 与 `00 §6.4` 的同步

- 本文件由 `00 §6.4` 机械抽取；**不要手改**，改 `00` 后重新生成。
- 本地检查：`python tools/diag-extract --check`（golden diff）；
  重新生成：`python tools/diag-extract --write`。
- 发布/CI 检出没有 `00`，`--check` 输出 INFO 并退出 0：无法比较，不是失败。
- 抽取范围：`00 §6.4` 的整张表（40 个码位）；B-LS 专属码另计。
