# spec/cap-context.md · 模块能力上下文与每模块旋钮（草稿）

> **状态**：`草稿`。**Q2 决定已定**（词法、不可放宽、无隐式继承）；完整检查器待 `ls-sem`。
> **上位**：[`02 ADR-18`](../02-架构评审与ADR.md)（模块级能力上下文）、
> [`00 §5.1`](../00-LangSysQuanta-设计初稿.md)（module/profile/属性）、
> [`00 §6.2`](../00-LangSysQuanta-设计初稿.md)（gate matrix）、
> [`effects.md`](effects.md)（`Unsafe` 终止）、[`trust.md`](trust.md)。
> **范围**：模块 `#[cap]`、`#[forbid(unsafe)]`、每模块 `#[bounds]`/`#[overflow]`/`#[fp]`。
> **不在本文件**：cap 运行期令牌的签发/消费（`effects.md`）、镜像 cap 表（`image.md`）。

---

## 1. Q2 决定

`#[cap(...)]` 是**模块级词法能力上下文**，不是动态全局状态，也不是可复制令牌：

1. 只能在 `module` item 的根声明；其他 item 上的 `#[cap]` ⇒ `E-LS-CAPCTX`；
2. **不可嵌套放宽**：子模块/内部 `unsafe` 不得用局部 `#[cap]` 扩大父模块能力；
3. **不可跨模块隐式继承**：每个模块文件必须自己声明所需 cap；`use` 不传递 cap；
4. 跨模块边界仍按值传递 `iso`/`val`/`Cap[...]` 令牌，不引入 ambient；
5. `#[forbid(unsafe)]` 是**向下封闭**的：子模块不能重新开启 unsafe；
6. 每模块旋钮只在当前模块生效，子模块不继承；子模块只能收紧，不能放宽；
7. 模块 cap 只提供**权限上下文**，不证明 `unsafe` 深层 soundness（`H-LS-4` 仍 Out-of-scope）；
   安全包装仍需 `trusted.lock`/审计（`effects.md` §4）。

> 结论：**Q2 = 词法 + 不可放宽 + 无隐式继承**。这与 ADR-18 一致。

---

## 2. 能力集与声明

```text
Capability ::= Unsafe | Alloc | Mmio[a..b] | Dma | Ffi | Spawn | Irq
```

- `Mmio[a..b]` 必须给出闭区间，且地址范围非空；
- `#[cap]` 参数是封闭集合；未知 cap ⇒ `E-LS-CAP`；
- 模块 cap 是**编译期事实**，不生成运行期值；需要线性令牌时仍显式传 `Cap[...]` 值；
- `#[cap]` 不能出现在 `impl`/`fn`/`struct`/`static` 上；
- cap 的**最小授权**由 manifest `[capabilities]` 与模块 `#[cap]` 交叉校验（ADR-16）。

正例：

```ls
#[cap(Unsafe, Mmio[0x4000_0000..0x4000_0fff])]
module drivers.uart;

fn write_reg(r: ref[Mmio[U32]], v: U32) eff(Hw) {
    unsafe { r.write(v) }
}
```

负例：

```ls
module drivers.spi;                  // 父模块没有 cap
#[cap(Unsafe)]                       // E-LS-CAPCTX：cap 只能在 module 根
fn bad() { unsafe { ... } }

#[cap(Unsafe)]
module drivers.i2c;

// 子模块文件 drivers/i2c/child.ls（不继承父 cap）：
module drivers.i2c.child;
fn f() { unsafe { ... } }            // E-LS-CAPCTX
```

---

## 3. 词法作用域规则

| # | 规则 | 诊断 |
|---|---|---|
| C1 | `#[cap]` 只允许在 `module` 根；每个文件最多一条 | `E-LS-CAPCTX` |
| C2 | 子模块不继承父 cap；需要时自己声明 | `E-LS-CAPCTX` |
| C3 | 内部 item 不能扩大模块 cap 集 | `E-LS-CAPCTX` |
| C4 | `unsafe {}` 需要模块 cap `Unsafe` 或显式 `Cap[Unsafe]` 值 | `E-LS-CAPCTX` |
| C5 | `#[forbid(unsafe)]` 向下封闭；子模块声明 `#[cap(Unsafe)]` 仍被拒 | `E-LS-CAPCTX` |
| C6 | 跨模块只传 `iso`/`val`/标量/显式 cap 值；不传 ambient | `E-LS-CAP` |
| C7 | `Mmio` 地址必须在模块 `Mmio[a..b]` 内 | `E-LS-CAP` |
| C8 | 模块 cap 与 manifest 能力清单不一致（超集/非最小） | `E-LS-CAP`/`E-LS-PROFILE` |

> C4 的“或显式 `Cap[Unsafe]` 值”允许库函数在**无模块 cap**时通过参数接收令牌；
> 该令牌仍是线性的（S17 消费）。

---

## 4. 每模块旋钮

```text
#[bounds(off, requires = "...")]   关闭边界检查，必须带契约
#[overflow(wrapping)]              覆盖默认溢出策略
#[fp(fast)]                        放宽浮点（仅 agent/登记目标）
```

规则：

1. 旋钮只在当前模块生效，**不继承**；子模块默认安全；
2. 子模块只能**收紧**（例如父 `bounds(off)` 子模块仍默认检查）；
3. `bounds(off)` 必须同时有 `requires` 契约与 CI 证据，否则 `E-LS-DIAL`；
4. `overflow(wrapping)` 不能覆盖 `agent` 的 checked 调试语义（D20）；
5. `fp(fast)` 只能在登记目标/CI 证据下使用；不得改变 `Order`/原子语义；
6. 同一模块重复/冲突旋钮 ⇒ `E-LS-DIAL`；
7. 旋钮变化必须进入构建指纹（`toolchain.md`）。

---

## 5. 与 `Unsafe` 终止的关系

- 模块 `#[cap(Unsafe)]` 提供词法权限，但**不等于**安全包装；
- `effects.md` §4.1 的安全包装仍需：非 unsafe fn、参数/返回无 `rawptr`（含公开字段传递）、
  `trusted.lock`/审计覆盖；
- 当前 checker-spike 把模块 cap 视为 unsafe-API 边界，跳过 Q4 判定；
  这是**过渡近似**，`ls-sem` 必须按 §4.1 逐函数判定；
- `#[forbid(unsafe)]` 模块的安全包装不吸收 `Unsafe` 效果；内部不得出现 unsafe 面积。

---

## 6. 检查器现状

| 能力 | checker-spike | `ls-sem` 目标 |
|---|---|---|
| 解析 module `#[cap]` | 已实现 | 保留 |
| 无模块 cap 的 unsafe ⇒ `E-LS-CAPCTX` | 已实现 | 保留 |
| `#[forbid(unsafe)]` 向下封闭 | 未实现 | 必须 |
| 子模块不继承 cap | 未实现（无模块图） | 必须 |
| `Mmio` 范围检查 | 未实现 | 必须 |
| 每模块旋钮继承/收紧 | 仅 `bounds(off)`→`E-LS-DIAL` | 完整组合 |
| manifest 最小授权 | 未实现 | 链接期 |

---

## 7. 未决/后续

| # | 项 | 归属 |
|---|---|---|
| C-1 | 模块图与子模块 cap 的机器检查 | S0′ `ls-sem` |
| C-2 | manifest `[capabilities]` 与模块并集的最小性 | S1/链接期 |
| C-3 | `Irq`/`Dma` cap 的域规则 | `H-LS-16` |
| C-4 | 生成代码（SVD/bindgen）的 cap 归属 | `toolchain.md`/ADR-20 |
| C-5 | 模块 cap 与 `trusted.lock` scope 的交叉校验 | `trust.md` |

> Q2 的**规格决定**已关闭；实现关闭条件是 C-1/C-2 通过，且档案 C 的嵌套模块负例可复现。
