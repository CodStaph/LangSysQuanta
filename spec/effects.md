# spec/effects.md · 效果系统、gate matrix 与 Unsafe 终止

> **状态**：`草稿`（§2 gate matrix 与 §4 Unsafe 终止规则已冻结；§3 profile 的效果级门禁待补，Q4 未关闭）
> **上位**：[`00 §5.6`](../00-LangSysQuanta-设计初稿.md)（效果语法）、
> [`00 §6.2`](../00-LangSysQuanta-设计初稿.md)（gate matrix，**唯一权威**）、
> [`00 §6.3`](../00-LangSysQuanta-设计初稿.md)（跨 profile 调用）。
> **相关**：决策 **D9**（模块/profile 单一写法）、**D18**（profile 是 crate 图分区）、
> `H-LS-4`（`unsafe` 深层 soundness，`Out-of-scope`）、**Q4**（`Unsafe` 在安全包装处终止）、
> `spec/ub.md`、`spec/trust.md`。

## 1. 效果集

### 1.1 分类

| 类 | 效果 | 说明 |
|---|---|---|
| 内部 | `Pure` | 偏序最小元；无副作用、无分配、无 I/O |
| 内部（可推断） | `Local` | `cell` 读写，限定单域 |
| 内部（可推断） | `Write` | 写共享状态（如 `push`） |
| 内部（可推断） | `Io` | 文件 / 设备 I/O |
| 边界（`seal` 必须显式） | `Unsafe` `Ffi` `Hw` `Asm` `Alloc` `Dma` `Irq` `Block` `Atomic` `Spawn` `Panic` `Eval` `Rewrite` | 见 `00 §5.6` |

> 内部效果可推断并报告；**边界效果必须显式写在 `eff(...)` 里**，缺失报 `E-LS-EFFECT`。

### 1.2 代数

- 组合：`eff(E1, E2) = E1 ∪ E2`；
- 偏序：子集关系，`Pure ⊑ E` 对所有 `E` 成立；
- **函数效果子类型**：效果更小的函数可用于要求更大的位置（反之拒绝，`E-LS-EFFECT`）；
- `Unsafe` 是边界效果，但可按 §4 在安全包装处**终止**（不进入签名）。

## 2. gate matrix（唯一权威）

> 三重门：**cap 判权限，mode 判别名，effect 判可见性**。
> 实现者不得用 effect 替代 cap 检查（这是 0.1.0 `unsafe(Cap[Unsafe])` 的缺陷）。

| 操作 | mode 要求 | cap 要求 | effect | 权威检查 |
|---|---|---|---|---|
| 索引/解引用 `ref/box/val` | 对应 mode | — | — | mode + 边界检查 |
| `rawptr` 解引用/算术 | `raw` | `Cap[Unsafe]`（值） | `Unsafe` | cap + effect |
| `Mmio[T]` 读写 | 类型本身 | `Cap[Mmio[a..b]]` 且地址在范围内 | `Hw` | cap |
| `fence(Order)` | — | — | `Hw` | 类型/参数 |
| 分配 `alloc`/`box` | — | `Cap[Alloc]`（kernel） | `Alloc` | cap/effect |
| `spawn` / `join` | `iso`/`atom` | `Cap[Spawn]`（kernel） | `Spawn` | mode + cap |
| `extern "C"` 调用 | `raw`（指针参数） | `Cap[Ffi]` | `Ffi` | cap |
| `asm` | — | `Cap[Unsafe]` | `Asm` | cap |
| DMA 提交 | `iso` | `Cap[Dma]` | `Dma` | cap + mode |
| 原子操作 | `atom` | — | `Atomic` | mode |
| `freeze`/`recover` | `uniq`/`frozen` | — | — | mode |
| `unsafe` 块 | — | `Cap[Unsafe]` | `Unsafe`（+ 内含效果） | cap + effect |
| `comptime` 求值 | — | — | — | fuel |
| `panic` | — | — | `Panic` | effect |
| `static` 初始化 | — | — | — | comptime 常量 |
| `cell` 读写 | 单域 | — | `Local` | mode + 域 |
| `shared` 加锁 | `atom` | — | `Atomic` | mode + 锁 rank |
| `release` | `uniq` | — | — | 消费 + 返回值 |
| `defer expr` | 捕获资源 | — | — | 恰好一次消费 |
| `#[recursion]` | — | — | — | 静态栈上界 |
| 模块 `#[cap(...)]` | — | 词法上下文 | — | 入口检查 + 不可放宽 |
| `#[bounds(off)]` | — | — | — | 必须有 `requires` |
| `#[boundary]` 调用 | `val`/`iso`/标量 | 按 callee 需求 | 并集 | trampoline |
| `ls audit`（工具） | — | — | — | Trusted 闭包 |

> 本表与 `00 §6.2` 逐行一致；任何差异以 `00` 为准并回改本文件。
> 每行必须有**唯一权威检查**，不得出现「两处都能判」的重叠。

## 3. profile 映射

| profile | 允许的效果 | 禁止 / 改写 |
|---|---|---|
| `kernel` | `Alloc`(cap) `Hw` `Dma` `Irq` `Atomic` `Unsafe`(cap) `Ffi`(cap) `Asm`(cap) `Write` `Io` | `Block` 禁止；`Panic` → **abort**（不 unwind）；递归禁止（`E-LS-RECURSION`） |
| `agent` | 上述全部 + `Block` + `Panic`(abort 语义) | `depth`/`mem` 预算限制；不得依赖 `kernel` crate |

跨 profile 规则（`00 §6.3`）：

1. **只能经 `#[boundary]` trampoline**，效果取**并集**，不得隐式继承预算与 cap；
2. `#[boundary]` 参数只允许 `val`/`iso`/标量（不传 `ref`/`box`/`rawptr`）；
3. v0 **禁止跨 profile 静态链接**；违规报 `E-LS-PROFILE`；
4. 跨域 `panic` 一律 abort，不 unwind。

## 4. `Unsafe` 终止规则（Q4）

### 4.1 定义

函数 `f` 是**安全包装**（可以把 `Unsafe` 吸收掉）当且仅当三条同时成立：

1. `f` 的声明不含 `unsafe`，且**参数与返回值不含 `rawptr`**（含公开 struct 字段的传递暴露）；
2. `f` 所在模块有 `#[cap(Unsafe)]` 词法上下文（`00 §5.1`，ADR-18），或 `f` 内显式取得 `Cap[Unsafe]` **值**；
3. `f` 的 unsafe 面积已记入 `ls audit`，且被 `trusted.lock` 条目或 crate 内审计覆盖（`spec/trust.md`）。

满足时：`eff(f)` 的签名**不含** `Unsafe`，内部 `unsafe` 的效果在 `f` 处终止。

### 4.2 判定（可执行）

| 情形 | 结果 |
|---|---|
| `f` 满足 §4.1 | 不报错；`Unsafe` 不进入 `eff(f)` |
| `f` 不满足 §4.1 且 `eff(f)` 缺 `Unsafe` | **`E-LS-EFFECT`**（边界效果缺失） |
| `f` 暴露 `rawptr`（参数/返回/公开字段） | 终止不成立，必须是 `unsafe fn` 或在 `eff` 中显式保留 `Unsafe` |
| `f` 返回 `ref` 派生值 | 先报 `E-LS-REGION-ESCAPE`（终止无从谈起） |
| 经 `#[boundary]` 跨 profile | 效果**取并**，`Unsafe` 不得被 trampoline 吞掉 |

> 「终止」是**语言层**声明，soundness 由 `trusted.lock` + `ls audit` 承担，
> `H-LS-4` 仍是 `Out-of-scope`；不允许用「下游信任上游」的方式洗白。

### 4.3 为什么必须允许终止

`Mmio[T]`、`dossiers/slab` 的容器、通用容器库都是「内部 unsafe、外部安全 API」的形态。
若 `Unsafe` 不能在包装处终止，这些库只能以 `unsafe fn` 暴露，安全子集将无法使用它们
（对应 `00 §6.2` 的注记与 `LS-27`「cap 工效导致 unsafe 上移」风险）。

## 5. 正例 / 负例

| 场景 | 期望 | 依据 |
|---|---|---|
| `Mmio[T]` 的安全读取 API（内部 `unsafe`） | 接受，`eff` 只有 `Hw` | §4.1 三条满足 |
| 安全函数返回 `rawptr` | 拒绝：`E-LS-EFFECT` 或 `E-LS-UNSAFE` | §4.2 |
| `kernel` 模块调用 `Block` | 拒绝：`E-LS-EFFECT` | §3 |
| `agent` crate 依赖 `kernel` crate | 拒绝：`E-LS-PROFILE` | §3 第 1 条 |
| `#[boundary]` 传 `ref` 参数 | 拒绝：`E-LS-PROFILE` | §3 第 2 条 |
| `unsafe` 块缺 `Cap[Unsafe]` 值 | 拒绝：`E-LS-CAP` | gate matrix 第 12 行 |

## 6. 待办

- [ ] §4.1 三条写成**检查器规则**（需要 cap 上下文 + `ls audit` 联动），之后才可关闭 **Q4**；
- [ ] §3 补「效果级」门禁（当前 profile 表只覆盖溢出/越界/递归/panic）；
- [ ] 与 `spec/cost.md` 对齐：每个边界效果的成本（如 `Hw` = 1 volatile）；
- [ ] `tests/conformance/reject` 为 §5 的 5 条负例各补一条用例；
- [ ] `Eval`/`Rewrite` 的语义归属 comptime 规范，本文件只登记其存在；
- [ ] `E-LS-EFFECT` 需区分「未声明」与「声明超集」两种文案。
