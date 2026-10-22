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
| FFI nounwind（UB-15 / T4c） | `HonorsNounwind`：每个可达 `extern "C"` callee 只 `ret`/`abort`，不 unwind（见 §3） | 语言侧已机械化（`lean/LSys/Ffi.lean`）；**callee 未验证** |
| 后端 volatile 顺序（UB-11 / T4b） | `HonorsVolatile`：后端只保留访问、删除非 volatile 访问、交换**非全 volatile** 的一对访问（见 §2） | 模型已机械化（`lean/LSys/Mmio.lean`）；**后端未验证** |
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

## 2. MMIO / volatile 的显式信任（UB-11 / T4b）

`F0` 没有 `Mmio`/`Hw`，操作语义无法证明「后端不重排 volatile 访问」；
所以 T4b 把这条义务写成**具名假设**而不是定理。

- **语言侧（已机械化）**：`Mmio[T]` 的读写按类型固定为 volatile（`LSys.mmioAccess`），
  UB-11 不可能落在它身上（`typed_mmio_no_ub`）；反之，普通 `*T` 访问 MMIO 地址
  **就是** UB-11（`plain_mmio_is_ub`），且分类是全的（`safe_or_ub`）。
  轨迹层面：`TypedTrace`（所有 MMIO 访问都是 volatile）不含 UB-11
  （`typed_trace_no_ub`），而普通访问的轨迹就是反例（`untyped_mmio_has_ub`）。
- **编译侧（假设）**：后端只允许「保留一个访问 / 删除非 volatile 访问 / 交换两个
  **不都是 volatile** 的相邻访问」，即 `LSys.Compliant`；
  `LSys.HonorsVolatile compile ≜ ∀ t, Compliant t (compile t)` 就是本文件登记的那条信任。
  在它之下 volatile 子序列（相对顺序）与 `ls cost` 的 volatile 计数都不变：
  `honors_preserves_volatile` / `honors_preserves_volatile_count`。
- **可证伪**：无条件交换前两条访问的后端不满足该信任（`not_every_backend_honors`）。
  信任不是「自动成立」的性质；拿不出证据（审计报告 / 后端测试 / 形式化后端模型）时，
  `Hw` 效果按 `spec/effects.md` 的边界处理，并应记入 `ls audit`。

**信任边界（必须如实记录）**：

1. 模型只覆盖**顺序**（volatile 相对顺序 + 不可删除）；缓存一致性、寄存器副作用、
   总线宽度/对齐由硬件手册与 `spec/baremetal.md` 承担。
2. `fence(Order)` 仍按 `spec/semantics.md` 的「MMIO / volatile」小节是唯一排序手段；
   Lean 模型不把 `Order` 展开成指令（内存序映射属 `spec/cost.md`）。
3. `ls cost` 的「1 volatile」由 `volatileCount` 记录，信任下计数不变。
4. 这既不背书 `unsafe` 深层 soundness（`H-LS-4` 仍 `Out-of-scope`），
   也不替代 `Mmio` cap 范围检查（checker 的 cap/`E-LS-PROV` 规则）。
5. 证据文档：[`results/T4b-mmio.md`](../results/T4b-mmio.md)。

## 3. FFI nounwind（UB-15 / T4c）

`extern "C"` 隐含 `nounwind`（`spec/baremetal.md` §5），但 **callee 的行为不在语言内**
（`H-LS-5`）：它可以正常返回、abort，也可以 unwind。第三种就是 UB-15。

- **语言侧（已机械化）**：跨界退出只有 `ret` / `abort` / `unwind` 三种（`LSys.Exit`），
  只有 `unwind` 未定义（`isDefined`）；unwind 穿过 nounwind 边界即 UB-15 事件
  （`LSys.FfiEvent`），分类全（`defined_or_ub`），`ret`/`abort`（含 `panic`）不产生 UB-15。
- **静态 ABI gate**：`?` 越过边界要求返回类型能编码错误，且无 varargs
  （`LSys.AbiSig`/`abiOk`；对应 Q6 的 `check_signature`，违规为 `E-LS-ABI`）。
  它是**静态**问题，不走 UB-15 的运行时分支（`abi_rejects_unencodable_error`）。
- **信任（假设）**：`LSys.HonorsNounwind exitOf ≜ ∀ f, isDefined (exitOf f) = true`
  —— 每个可达 callee 只正常返回或 abort。其下 nounwind 边界不会产生 UB-15
  （`honors_no_ub`、`trace_no_ub_of_callees`）。
- **声明不够**：`nounwind_trace_not_enough` 说明「全是 `extern "C"` 声明」仍可能出 UB-15；
  必须叠加 callee 信任。会 unwind 的 callee 违反信任（`not_every_callee_honors`），
  所以该假设可证伪。

**信任边界**：不覆盖 C 侧的 `setjmp`/`longjmp`、信号、语言异常（这些要么被 ABI 拒绝，
要么由 `H-LS-5` 的审计承担）；也不替代 Q6 的标量/布局映射。证据：
[`results/T4c-ffi.md`](../results/T4c-ffi.md)。

## 待办

- [~] 定义 `trusted.lock` 的文件格式（TOML 子集已实现；最终 schema/哈希算法待定）；
- [ ] 明确 `Reach(P)` 的收集口径（泛型单态化结果、`ref[Trait]` 动态分派目标）；
- [ ] 明确「不做传递信任」的机器检查：lock 必须列出完整闭包，禁止间接信任；
- [ ] `ls audit` 的**离线**行为与 advisory 数据源（谁签发、如何验证）；
- [x] UB-11/T4b 的具名信任与可证伪反例（`lean/LSys/Mmio.lean`，2026-10-22；见 §2）；
- [x] UB-15/T4c 的具名信任与可证伪反例（`lean/LSys/Ffi.lean`，2026-10-22；见 §3）；
- [ ] 把 `HonorsVolatile` / `HonorsNounwind` 的审计证据（后端测试 / callee 审计报告）纳入 `ls audit` 输出；
- [~] 与 `tests/conformance/reject` 的负例契约：已有「哈希错」1 条；缺失条目/过期报告待补；
- [ ] 片段声明登记表：定理只对「单线程 + 无 unsafe + 无 FFI + 无递归」成立（中断域见 `H-LS-16`）。

## 不做（本阶段明确排除）

- 不做运行期吊销（吊销 = 更新 lock）；
- 不背书 `unsafe` 块的深层 soundness（`H-LS-4` 仍为 `Out-of-scope`）；
- 不定义硬件后果（由 `Hw`/`Dma` 效果承担，见 `spec/effects.md`）。
