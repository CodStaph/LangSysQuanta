# spec/ub.md · UB 清单与 provenance 决策

> **状态**：`草稿`（15 条条目与诊断码已冻结；Q5 已于 2026-10-18 关闭：RTT v1 / D41）
> **上位**：[`00 §8.1`](../00-LangSysQuanta-设计初稿.md)（UB 清单，**唯一权威**）、
> [`00 §8.2`](../00-LangSysQuanta-设计初稿.md)（安全子集闭包，决策 **D24**）。
> **相关**：`H-LS-4`（`unsafe` 深层 soundness，`Out-of-scope`）、`H-LS-16`（中断域）、
> 决策 **D41**（RTT v1 provenance，Q5 已关闭）、`spec/trust.md`。
> **规则**：新增 UB 必须走 edition 变更；本表是「安全子集无 UB」的**唯一 oracle**。

## 1. 清单

「安全子集可达 = 否」表示：在 `Safe(P)` 成立的程序里语言保证不发生。
「仅 `unsafe`」表示：只有显式 `unsafe` + 满足契约时才可能出现，由契约与审计承担。

| # | UB | 安全子集可达 | 检测 / 处理 | 诊断码 | oracle（如何验证被防住） |
|---|---|:--:|---|---|---|
| UB-1 | 越界读/写 | 否 | 默认边界检查；`explore` 守卫 | `E-LS-BOUNDS` | 负例：`tests/conformance/reject/bounds.ls` 报 `E-LS-BOUNDS`；正例：契约可证时边界检查被消除（`ls cost`） |
| UB-2 | 悬垂引用/指针 | 否 | 区域约束检查 | `E-LS-ESCAPE` | 负例：`dossiers/views/reject.ls` 的越界派生（`E-LS-REGION-ESCAPE`）+ region 逃逸负例 |
| UB-3 | double free / 重复 drop | 否 | 线性所有权 | `E-LS-DROP` | 负例：同一 `box` 二次 move/drop；正例：`iso` 转移后原绑定不可用 |
| UB-4 | 使用未初始化 | 否 | 初始化检查 | `E-LS-INIT` | 负例：`let x: T;` 后读取 |
| UB-5 | 数据竞争（线程域） | 否 | mode `R6`/`R8` | `E-LS-RACE` | 负例：`shared` 写入 + 并发送达；正例：`iso`/`val` 转移 |
| UB-6 | 整数溢出 | 否 | 语言定义 **wrapping**；`agent` checked 为调试 trap（非不同语义） | `E-LS-OVERFLOW` / `W-LS-OVERFLOW` | 正例：`Int.MAX + 1` wrap 结果可预测；`agent` 下同表达式 trap |
| UB-7 | 除零 / 非法移位 | 否 | trap（**定义行为**：abort） | — | 运行期 oracle：退出码与 `abort` 一致，不是未定义结果 |
| UB-8 | 解引用 null/野指针 | 仅 `unsafe` | 契约 + `Witness` | `E-LS-PROV` | 负例：`unsafe` 块内无 `Witness` 的 `rawptr` 解引用 |
| UB-9 | 未对齐访问 | 仅 `unsafe` | 契约 / `align_of` 检查 | `E-LS-PROV` | 负例：用 `align_of::<T>()` 可证的对齐违约 |
| UB-10 | 违反 provenance（别名/越界派生） | 仅 `unsafe` | **RTT v1（D41）** + 契约（见 §2） | `E-LS-PROV` | 负例：`dossiers/slab/reject.ls` 的 `E-LS-PROV` 两例（越界派生、跨域别名）；RTT-1/RTT-2 见 §2.6 |
| UB-11 | MMIO 非 volatile 访问被优化/重排 | 否（须用 `Mmio[T]`） | 类型固定 volatile + `fence` + 后端 `HonorsVolatile` 信任 | `E-LS-PROV` | 负例：普通 `*T` 访问 `Mmio` 区域；正例：`Mmio[T]` 访问在 `ls cost` 中显示 1 volatile；运行时模型：`results/T4b-mmio.md` |
| UB-12 | 未定义求值顺序 | 否 | **规范求值序**：从左到右、先求值后调用 | — | 正例：`f(g(), h())` 的求值顺序在 IR 与产物中一致（`spec/bls.md` 同规则） |
| UB-13 | 栈溢出 | `agent` 可达；`kernel` 否 | `agent` depth 预算（运行时）；`kernel` 静态栈上界 | `W-LS-STACK` / `E-LS-RECURSION` | 负例：`dossiers/recursion/reject.ls`（`E-LS-RECURSION` / `E-LS-STACK`）；正例：`accept_stack.ls` 显式栈；运行时模型：`results/T4d-stack.md` |
| UB-14 | drop 期间使用已释放对象 | 否（`abort`，无 unwind） | 见 `00 §6.6` | `E-LS-DROP` | 负例：`drop` 实现中访问已释放字段 |
| UB-15 | 跨 FFI 的 unwind | 否 | `extern "C"` 隐含 `nounwind` + ABI gate + 显式 `HonorsNounwind` 信任 | `E-LS-ABI` | 负例：`extern "C"` 函数体内 `?`/`panic` 越过边界；运行时模型：`results/T4c-ffi.md` |

> **UB-15 的运行时模型（T4c，2026-10-22）**：`lean/LSys/Ffi.lean` 把「跨界退出」分成
> `ret` / `abort` / `unwind` 三种（`Exit`），只有 `unwind` 是未定义（`isDefined`），
> 且「unwind 穿过 `extern "C"` 边界」就是 UB-15 事件（`FfiEvent … UBCode.unwind`）；
> 分类全（`defined_or_ub`），`ret`/`abort`（含 `panic`）不产生 UB-15
> （`ret_not_unwind`/`abort_not_unwind`）。真正跨边界的是**信任**：callee 行为不在语言内
> （`H-LS-5`），故按 `spec/trust.md` 的 `HonorsNounwind`（每个可达 callee 只 `ret`/`abort`）
> 处理——其下 nounwind 边界不产生 UB-15（`honors_no_ub`/`trace_no_ub_of_callees`），
> 而会 unwind 的 callee 违反它（`not_every_callee_honors`）；
> `nounwind_trace_not_enough` 明确「仅靠声明不够」。`?` 越过边界是**静态** ABI 问题
> （`AbiSig`/`abiOk`，`E-LS-ABI`），不是 UB-15 的运行时分支。
>
> **UB-11 的运行时模型（T4b，2026-10-22）**：`lean/LSys/Mmio.lean` 把「MMIO 访问必须是
> volatile」做成类型固定的事实（`mmioAccess`）：typed `Mmio[T]` 访问不可能触发 UB-11
> （`typed_mmio_no_ub`），普通 `*T` 访问 MMIO 地址**就是** UB-11（`plain_mmio_is_ub`），
> 分类全（`safe_or_ub`）；轨迹层面 `TypedTrace` 无 UB-11（`typed_trace_no_ub`）。
> 「后端不重排」不是语言内核能证的事，按 `spec/trust.md` 的 **`HonorsVolatile`**
> 显式信任处理：后端只保留访问、删除非 volatile、交换非全 volatile 的对；其下 volatile
> 子序列与 `ls cost` 的 volatile 计数不变（`honors_preserves_volatile`），而无条件交换
> 前两条的后端违反该信任（`not_every_backend_honors`）——信任是**可证伪**的。
>
> **UB-13 的运行时模型（T4d，2026-10-22）**：`lean/LSys/Stack.lean` 把栈深度做成
> 显式预算层：`Fits s ⇔ depth ≤ budget`、越界事件 `StackEvent … UBCode.stack`，并给出
> 两条对偶 oracle（`fits_or_overflow`：预算内，或 UB-13）；`callV` 入帧、`retV` 出帧，
> 其余步（含 14 条 `abort*`——LSys 的 `abort` 不 unwind）为中性。可见的核心步
> `EffHStepEvalCK` 被标注为 `StackStepCK`，同时保持预算（`fits`）与结果类型化
> （`StackStepCK.wt` ← `WTKH.preserved`）；`no_stack_overflow_reachable` 说明
> 「预算内不溢出」。`kernel` 的**静态**上界仍由 `E-LS-STACK`/`H-LS-29` 承担，本模型
> 只证「静态检查通过 ⇒ 运行时帧预算足够」（`static_bound_fits`）。

## 2. provenance 决策（UB-10，Q5 已关闭：RTT v1）

> **决策 D41 / 2026-10-18**：v0 采用 **RTT v1（Region-Tag Tree）**，Tree Borrows 的受限子集。
> Q5 关闭：UB-10 有了规范定义与 oracle。
> **关闭的是模型选择，不是 `unsafe` 深层 soundness**：`H-LS-4` 仍为 `Out-of-scope`；
> 本节给规则，S3 给可执行检查，S5 给机械化。`spec/semantics.md` §4.3 只保留运行时接口。

### 2.1 范围与术语

RTT v1 只回答一个问题：**什么算 UB-10**。它不替代 R1–R8，也不证明 `unsafe` 契约成立。

| 术语 | 定义 |
|---|---|
| `a` | 分配 id（`alloc` 或 region 根） |
| `off` | 字节偏移 |
| `size(a)` | 分配大小 |
| `T(a)` | 分配 `a` 的 tag 树 |
| `t = (a, parent, kind, state, ρ)` | tag；`kind ∈ {uniq, mut, frozen, raw}`，`state ∈ {act, res, froz, dis}` |
| `live(t)` | `t ∈ T(a)` 且 `t.state ≠ dis` |
| `Witness` | `unsafe` 契约提供的运行期/审计见证；`ls audit` 记录未判定项 |

- **安全子集**不产生 `rawptr`：RTT 规则在编译期擦除，不增加运行时成本；
- **`unsafe`** 的 `rawptr` 通过契约 + `Witness` 进入 RTT；没有 `Witness` 的路径按 UB-10 处理；
- **并发**：`T(a)` 是每分配一棵树；跨域 raw 访问的 HB/独占义务由 `Witness` 承担。
  RTT v1 **不证明** race freedom，T2/T4 仍依赖 `H-LS-3`/`H-LS-16`。

### 2.2 tag 状态与来源

| `kind` | 来源 | 初始 `state` | 允许读 | 允许写 |
|---|---|:--:|:--:|:--:|
| `uniq` | `alloc`/`box`/`iso` | `act` | 是 | 是 |
| `mut` | `borrow mut` | `act` | 是 | 是 |
| `frozen` | `freeze`/`val` 复制 | `froz` | 是 | 否 |
| `raw` | `raw(p)`/`ref→raw` | `act`（可写）/`froz`（只读） | 是 | 仅 `act` + `Witness` |

`res` = Reserved：可读，等待子 tag 结束后恢复；`dis` = Disabled：不可访问。
`state` 是**所有权/别名**状态，不是内存初始化状态（后者见 UB-4）。

### 2.3 创建与转换

| 事件 | 规则 |
|---|---|
| `alloc` | 新建根 `(uniq, act)` |
| `borrow mut p as r` | 父 tag → `res`；子 tag `(mut, act)` |
| `borrow` 结束 | 子 → `dis`；父 → `act` |
| `freeze p` | 父 `uniq` → `froz`；子 `(frozen, froz)` |
| `val` 复制 | 新子 `(frozen, froz)`；父不变 |
| `recover` | 所有 `frozen` 后代 → `dis`；根 → `act` |
| `raw(p)` | `uniq/mut` 来源：父 → `res`，子 `raw` → `act`；`val` 来源：父保持 `froz`，子 `raw` → `froz` |
| 通过 `act` 写 | 同分配所有非祖先 tag → `dis`；祖先 → `res` |
| `raw` 写 | 同分配所有非 `raw` tag（含祖先）→ `dis`；该 `raw` → `act` |
| 调用 retag | 传 `ref/val` 建子 tag；返回时子 → `dis`，父恢复 |

`iso` 跨域转移整棵 `T(a)`；`val`/`atom` 只共享 `froz` 视图，不产生写权限。

### 2.4 访问与 UB-10

一次访问 `Access(t, off, sz, rw)` 必须同时满足：

```text
A1  t ∈ T(a) 且 t.state ≠ dis
A2  0 ≤ off ∧ off+sz ≤ size(a)
A3  aligned(t, off, sz)
A4  rw=read  ⇒ t.state ∈ {act, res, froz}
    rw=write ⇒ t.state = act
A5  t.kind=raw ∧ rw=read
      ⇒ 同分配没有活的 act uniq/mut tag 在 t 的子树之外（除非 Witness）
A6  t.kind=raw ∧ rw=write
      ⇒ 同分配没有活的非 raw tag 在 t 的子树之外且不在 t 的祖先链上
        （祖先由本次写 → dis；除非 Witness）
```

不满足任一条 ⇒ **UB-10**；下列指针算术/转换违规同样归入 UB-10：

- `p + k`：`off' = off + k`；`off' ∈ [0, size(a)]` 允许形成指针（`sz=0` 可用于比较），
  `off' ∉ [0, size(a)]` 把 tag 置 `dis`；之后解引用 ⇒ UB-10；
- `p - q`：必须同一 `a`，否则 UB-10；
- `ref → raw`：保留 `(a, tag)`；
- `raw → ref`：必须 `Witness`（有效、对齐、无冲突），否则 UB-10；
- `int → raw`：必须 `Witness` 给出 `a` 与 tag；RTT v1 **不**支持 provenance 洗白；
- 分配释放/region 结束：仍有活 `raw` tag ⇒ 必须 `Witness` 证明不再使用，否则 UB-10（归入 UB-2）。

### 2.5 与 Tree Borrows 的关系

RTT v1 是 **保守子集**，不是 Tree Borrows 全量：

- 采用 TB 的 tag 树、父子、`Reserved/Active/Frozen/Disabled` 思想；
- 写通过 `act` 时保守地禁用所有非祖先 tag（比 TB 更严格）；
- raw 读/写用 A5/A6 的保守条件，宁可多报 UB-10，不放行；
- **不包含**：`Untagged`/`Wildcard`、protector、two-phase borrow、完整 retag 变体、
  整数 provenance、跨语言 FFI provenance、`may_alias` foreign 访问。

**不声称**「RTT v1 与 TB 行为等价」；设计目标是「RTT v1 接受的访问在 TB 下也应有效」，
该包含关系仍需 S5 机械化证明。TB 的超集特性不进入 v0。

### 2.6 UB-10 的 oracle

| # | 程序骨架 | 预期 |
|---|---|---|
| RTT-1 | `let p = base + len; *p` | UB-10（越界派生） |
| RTT-2 | `let r = &mut x; let p = raw(r); *p = 1; *r` | UB-10（raw 写禁用 `r`） |
| RTT-3 | `let v = freeze x; *v = 1` | UB-10（写 `froz`） |
| RTT-4 | `let p = 0x1000 as *mut T; *p` | UB-10（无 `Witness` 的整数→指针） |
| RTT-5 | `borrow r { p = raw(r); } *p` | UB-10（子 tag 已 `dis`） |
| RTT-6 | `recover { v }` 且仍有活 `val` 副本 | `E-LS-UNIQ` / UB-10（别名未消费） |
| RTT-7 | raw 读，且同分配无活 `act uniq/mut` | 允许 |
| RTT-8 | 子借用结束，父 tag 恢复后使用 | 允许 |
| RTT-9 | `p` 来自分配 a、`q` 来自分配 b；`p - q` | UB-10（分配不匹配） |
| RTT-10 | `res` 状态的父 tag 上执行写 | UB-10（写 `res`） |

`dossiers/slab/reject.ls` 已覆盖 RTT-1/RTT-2 的两种形态；其余进
`tests/conformance/reject`（S-1 期间 ≥ 20 条负例的一部分）。

### 2.7 明确不做

- 不证明 `unsafe` 块的深层 soundness（`H-LS-4` 仍 `Out-of-scope`）；
- 不做跨 FFI 的 provenance 传递（`H-LS-5`）；
- 不做运行期吊销/全局 provenance 注册表；
- 不把 RTT v1 扩展到中断/DMA 域的定理（`H-LS-16`）；
- 不要求安全子集生成 tag 检查；RTT 是 `unsafe` 的 oracle，不是安全子集的运行时开销。

## 3. 规则

- 本表与 `00 §8.1` 必须逐行一致；任何差异以 `00` 为准并回改本文件；
- 每条 UB 的 oracle 必须是**可执行**的：要么 `tools/checker-spike` 报出对应诊断码，要么运行期行为可断言；
- 诊断码新增需同时登记到 `00 §11`（诊断表）与 `00 §12`（`H-LS-*`，若涉及能力降级）；
- 不得用「安全子集不含 unsafe」这类**排除式**说法替代闭包定义（`00 §8.2` D24）。

## 4. 待办

- [ ] 为 UB-1/3/4/5/14/15 各补一条 `tests/conformance/reject` 负例（当前仅有 UB-2/10/13 的覆盖）；
- [ ] UB-7 的「定义行为」需要写成可断言 oracle（`abort` 的退出码与信号）；
- [ ] UB-12 需要在 `spec/bls.md` 与正式 EBNF 里同步求值序条款；
- [ ] `E-LS-PROV` 目前由 `dossiers/slab/reject.ls` 覆盖，需扩展到 `unsafe` 契约负例集；
- [ ] 把 RTT v1 的 `Access`/状态转移写成 checker-spike 可执行规则（S3；**不是 Q5 的阻塞**，
      Q5 已在 2026-10-18 由 D41 关闭）；
- [ ] 为 §2.6 的 RTT-1…RTT-6 建 `tests/conformance/reject` 负例（当前 dossiers 仅 2 例）；
- [ ] `ls audit` 输出 RTT v1 的「未判定项」（无 `Witness` 的 raw 路径）。
