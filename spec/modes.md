# spec/modes.md · 模式与区域（草稿）

> **状态**：`草稿`（Q1 部分冻结；Q8 `val` 别名策略与 Q9 初始化规则已定；A-2 待后续；A-5 已由 `Rgn*` 收口）。
> **上位**：[`00 §4`](../00-LangSysQuanta-设计初稿.md)、[`03 §4.0`](../03-开发与工程实践评审.md)、
> [`results/A-views.md`](../results/A-views.md)。
> **权威**：与 00 冲突时以 00 为准；本文件只细化可执行规则。
> **范围**：region 格、mode 格、R1–R8、视图与 Cursor、约束推断、`recover`、未初始化 `let`。
> **不在本文件**：cap 上下文、效果系统、UB/provenance（分别在 `cap-context.md`/`effects.md`/`ub.md`）。

---

## 1. 区域格

```text
local(s) ⊑ region(R) ⊑ thread ⊑ heap(H) ⊑ static
```

- ρ 只出现在**推断类型**与诊断中，源码不写生命周期参数（LS-P10）；
- `local(s)`：函数/块作用域；
- `region(R)`：`region R { }` 引入的分配区域；
- `thread`：线程局部；
- `heap(H)`：全局堆（`Alloc[Heap]` 产生）；
- `static`：编译期初始化、不可释放（`static`，见 00 §4.10）。

**逃逸规则**：`ref @ ρ` 不可存入 ρ' ⊐ ρ 的位置；`box @ ρ` 不可 move 出 ρ；
`iso` 只能位于 `heap`（可跨域转移）。

## 2. mode 格

| 源码类型 | 核心 mode | 语义 | 可跨域 | 可别名 | 可写 |
|---|---|:--:|:--:|:--:|:--:|
| `box[T]` | `uniq` | 唯一拥有（堆/区域） | 否 | 否 | 是 |
| `iso[T]` | `uniq` | 唯一拥有 + 可转移 | 是 | 否 | 是 |
| `val[T]` | `frozen` | 冻结/只读 | 是 | 是 | 否 |
| `ref[T]` | `mut` | 独占临时借用 | 否 | 受检 | 是 |
| `shared[T]` | `atom` | 共享（锁；原子用 `shared[Atomic[T]]`） | 是 | 是 | 受同步保护 |
| `rawptr[T]` | `raw` | 裸指针（仅 `unsafe`） | 不保证 | 是 | 是 |

**容器（不是 mode）**：`cell[T]`（单域内部可变、`Local`）、`Slice[T]`（只能以 `val`/`ref` 出现）。

### 2.1 `val` 别名策略（Q8 已定，ADR-31 方案 B）

`val[T]` 是**可别名的只读视图**，不是仿射 owner：

1. `let q = v`（`v: val[T]`）复制句柄，不复制底层数据；`H` 给同一别名增加一个
   holder `q`。`val` 进入聚合字段（`S { f: v }`）同样登记 holder。
2. `read p`（`p` 为 frozen、非 Copy）分配**新的别名 id** `b`，并把它登记到 `Λ`；
   它与从变量复制得到的句柄共享同一个 target `p`。
3. `val` 的只读性不因别名而改变：写 `p` 仍按 R5 检查，frozen 直接 `E-LS-ALIAS`。
4. `recover` 必须消费**所有 holder 出现**，不是只消费一个变量；聚合字段里的副本
   未被消费 ⇒ `E-LS-UNIQ`（`bad()` 反例，见 `t4-proof.md` 的 M2 重放）。
5. `val` 不是 `iso`：`recover` 只恢复 `uniq`，不把 `val` 变成可转移的唯一所有权。
   跨域共享仍按 R8：`frozen` 需 `thread ⊑ Rgn(v)`，且目标域的写权限重新检查；
   需要唯一所有权转移时，必须使用 `iso`。

示例（`q`、`s.f` 都是同一 target 的 holder）：

```ls
let v: val[Point] = freeze p;   // v 持有 owner 句柄 b
let q = v;                        // 复制句柄：H 增加 holder q
let s = S { f: v };               // 聚合字段：H(s) 增加 holder
recover { v }                     // E-LS-UNIQ：q 或 s.f 未消费
```

要实现“可别名但可回收”，检查器必须按 holder 出现位置做 `recover` 检查，
不能只看 `Λ` 里是否存在 `b`。

> 实现要求：静态状态带 `H : Place ⇀ ℘(Bid)`；`Aliases*`/`Consumed*` 按出现位置计。
> 详见 [`semantics.md` §2](semantics.md)。

### 2.2 `Guard` 与锁 rank（v2.2：surface = `let g = m.lock()`）

`00 §4.3` 规定 `lock` 返回 `Guard`，本文件按此执行。**不引入 `lock` 关键字**：
块形式 `lock m as g { }` 不是语法的一部分，避免与 `m.lock()` 的方法名冲突
（`lock` 若成为保留字，`postfix_op = "." ident` 将不再接受这个方法）。

`Guard` 是线性资源，规则：

1. `Guard` 是 `!Copy`；`move g` ⇒ `E-LS-MOVE`（线性值不可转移）；
   跨域（`spawn`/`Irq`/`Dma`）⇒ `E-LS-RACE`；不可 `return`、不可存入字段或聚合；
2. 释放只发生在**作用域退出**（S12）；v2.2 没有显式释放 `Guard` 的 surface 形式
   （`drop`/`release` 不在 EBNF），因此同一作用域内 `Guard` 按声明逆序释放，
   活跃集是一个栈；
3. `lockCtx(E)` ≜ 「`E` 处存在活跃 `Guard` 绑定」；活跃集与 `Λ` 同构，由流敏感状态追踪
   （[`semantics.md` §2.2](semantics.md)）；
4. `rankOk(E)` ≜ 「对任意活跃 `Guard` 对 `(g₁,g₂)`，若 `acquire(g₁) < acquire(g₂)`
   则 `rank(g₁) ≤ rank(g₂)`」；`rank` 来自 `Lock[T, const Rank: USize]`，违反 ⇒ `E-LS-IRQ`；
5. 因为 `Guard` 不可复制、不可转移、不可提前释放，`lockCtx`/`rankOk` 是**局部可判定**的：
   只需扫描当前作用域链的 `Guard` 声明，不需要全程序不动点。

> 代价（必须写清）：锁的获取点由 `m.lock()` 的位置决定，`Guard` 的作用域 = 其所在块。
> 需要提前解锁时，把临界区拆成更小的块；这是 LS-P17「fix-it 不引入 unsafe」之外的
> 又一条“用结构换安全”的取舍。

## 3. 检查规则 R1–R8

| # | 规则 | 诊断 |
|---|---|---|
| R1 | `uniq` 无别名；`move` 后源失效 | `E-LS-MOVE` |
| R2 | `uniq` 可在作用域 s 内借出 `ref`，s 结束归还（reborrow） | `E-LS-ALIAS` |
| R3 | `uniq --freeze--> frozen` 单向；`recover {}` 内消费全部别名方可回 `uniq` | `E-LS-UNIQ` |
| R4 | `ref @ ρ` 不可存入 ρ' ⊐ ρ 的位置（逃逸） | `E-LS-REGION-ESCAPE` |
| R5 | 写 place 要求**其区域内**无 `frozen`/`ref` 别名（区域级，非全局） | `E-LS-ALIAS` |
| R6 | `atom` 只能跨域共享，且带 `Atomic/Order` 或锁 rank（UB-5 的运行时模型：`lean/LSys/Threads.lean` 的 `shared_atomic_no_race`） | `E-LS-RACE` |
| R7 | `raw` 仅在 `unsafe` 且作用域内存在 `Cap[Unsafe]` 值（或模块 `#[cap]`）时可用 | `E-LS-UNSAFE`/`E-LS-CAP` |
| R8 | 跨域（`Thread`/`Irq`/`Dma`）移动只允许 `iso`/`atom`（转移后单线程拥有 ⇒ `no_race_if_single_owner`） | `E-LS-RACE` |

### 3.1 R5 的代价（必须保留）

`val` 的生命期等于所属区域；区域结束前不得再对该 place 取可变借用。
fix-it 只能建议：缩小作用域 / `cell` / 复制；**不得**建议 `unsafe`（LS-P17）。

## 4. 视图与 Cursor（Q1 已冻结）

> 证据：[`results/A-views.md`](../results/A-views.md)，checker `173d1b6`。

### 4.1 规则

1. **`val` 字段可返回**：含 `val` 字段的结构体是区域参数化的；ρ 由源推断，源码不写。
2. **`ref` 字段不可返回**：只能在借用作用域内存活；返回即 `E-LS-REGION-ESCAPE`。
3. **Cursor 模式**：`struct Cursor { src: val[Slice[T]], pos: USize }`，可返回、可 `ref` 可变。
4. `recover` 仅限**单函数 + 同域**；跨模块/跨域禁止（`E-LS-UNIQ`）。
5. 需要可变视图：`ref[Slice]` + 作用域内 API；跨函数传 owner，不传 `ref`。
6. **含 `ref` 字段的 `val`/`box`（A-5）**：`Rgn*` 递归收集嵌套
   `ref`/`val`/`box`/`slice` 的区域；源区域结束后使用 ⇒ `E-LS-REGION-ESCAPE`。
   `val` 字段本身可返回，但字段里的 `ref` 必须指向比返回值更长寿的区域。

### 4.2 正例

```ls
struct Packet { header: Header, payload: val[Slice[U8]] }
fn parse(src: val[Slice[U8]]) -> Result[Packet, Error] { ... }

struct Cursor { src: val[Slice[U8]], pos: USize }
fn cursor(src: val[Slice[U8]]) -> Cursor { ... }
```

### 4.3 负例

```ls
struct BadCursor { src: ref[Slice[U8]] }
fn bad(src: ref[Slice[U8]]) -> BadCursor { BadCursor { src } }   // E-LS-REGION-ESCAPE

fn bad_store(p: Packet) { static S: Packet = p; }                // E-LS-STATIC

fn bad_recover(p: val[Packet]) -> Packet {
    let q = p;
    recover { p }                                                // E-LS-UNIQ (q 未消费)
}
```

## 5. 约束推断

1. **约束生成**：`borrow`/`alloc`/`freeze`/`recover`/`spawn`/`store` 产生 `ρ1 ⊑ ρ2`；
2. **求解**：区域格上并查集 + 最小上界；函数级完成，不做全程序不动点（ADR-8）；
3. **失败**：输出最小不可满足核（2–3 条约束）+ fix-it；
4. **fix-it 顺序**：缩小作用域 → 复制 → 改 `uniq` → 提升 region → `recover`；
5. **禁止**：fix-it 生成 `unsafe`/新 cap/`Ffi`。

## 6. `recover` 的线性检查与初始化

### 6.1 `recover`（Q8 后的规则）

- 目标 `p = target(b_owner)`；别名集合是**出现位置**集合
  `Aliases*(Σ,p) = { (q,b) | b 指向 p 且 q 持有 b }`，包含 `val`/`ref` 与聚合字段副本；
- 块结果按隐式 move 消费；`ConsumeResult` 之后要求 `Aliases*(Σ_c,p)=∅`；
- `let q = v` / `S { f: v }` 产生的 holder 都算“未消费”，除非在块内 `move`/`drop`/被覆盖；
- 未消费 ⇒ `E-LS-UNIQ`；只看裸 `b` 的旧规则会漏掉 `s.f`，已废弃；
- 跨模块/跨域无法追踪 ⇒ 直接拒绝；
- 若未来引入 `#[recover]` 注册表，必须另立 ADR。

### 6.2 未初始化 `let`（Q9 已定）

语法（EBNF v2）：

```text
let [mut] x: T;          (* 未初始化声明 *)
let [mut] x: T = e;      (* 声明即初始化 *)
let [mut] x = e;         (* 类型由 e 推断 *)
```

状态：`uninit` → （首次赋值）→ `init` → （`move`）→ `moved`。

规则：

1. `let x: T;` 创建未初始化槽；在首次赋值前**不得** `read`、`move`、借用、返回、
   `drop`、作为 `recover` 目标或聚合构造的字段读取 ⇒ `E-LS-INIT`。
2. **首次赋值是初始化，不是 mutation**：即使没有 `mut`，`x = v` 也允许一次；
   这次赋值把状态从 `uninit` 变为 `init`。
3. 初始化后：`mut` 允许继续写；非 `mut` 的再次赋值按写权限拒绝 ⇒ `E-LS-ALIAS`
   （不是 `E-LS-INIT`）。
4. `let mut x: T;` 的首次赋值同样是初始化；`move x` 后可用 `x = v` 重新初始化
   （reinit），未初始化状态不因 `move` 自动恢复。
5. `let x: T = e;` 在声明处完成初始化；`mut` 只影响之后的写。
6. 不支持部分初始化：`x.f = v` 要求整个 `x` 已 `init`；否则 `E-LS-INIT`。
   需要逐字段初始化时，用 `let x: T = T { ... };` 或 `MaybeUninit` API。
7. 作用域退出时未初始化的槽**没有值，不执行 drop**；未使用也未 `drop` 的
   `let x: T;` 不报错。若类型带必须释放的线性资源，definite-initialization
   分析要求所有正常路径初始化（S0′ 完整实现；当前 checker 只做线性保守）。
8. 控制流汇合：只有所有可达路径都 `init` 时，汇合后才算 `init`；
   `if`/`while` 分支内初始化不外泄。该路径敏感规则由 S0′ 的初始化分析实现；
   当前 `checker-spike` 只覆盖直线代码。
9. `drop` 一个 `uninit` 或 `moved` 的值 ⇒ `E-LS-INIT`/`E-LS-MOVE`；
   不把“未初始化”当作“零值”。

诊断映射：

| 情形 | 诊断 |
|---|---|
| 首次赋值前读/move/借用/返回/drop | `E-LS-INIT` |
| 部分初始化 `x.f = v`（`x` 未 init） | `E-LS-INIT` |
| 非 `mut` 的第二次赋值 | `E-LS-ALIAS` |
| `move` 后未 reinit 就使用 | `E-LS-MOVE` |

示例（`let p: Point;` 与 `mut` 的首次赋值）：

```ls
struct Point { x: Int, y: Int }

fn q9_ok() {
    let p: Point;                 // uninit
    p = Point { x: 1, y: 2 };     // 首次赋值 = 初始化（不需要 mut）
    let a = p.x;                  // OK

    let mut q: Point;             // uninit + 后续可写
    q = Point { x: 3, y: 4 };     // 首次赋值同样是初始化
    q.x = 5;                      // OK：mut 在 init 之后才生效
}

fn q9_bad_read() {
    let p: Point;
    let a = p.x;                  // E-LS-INIT
}

fn q9_bad_write() {
    let p: Point = Point { x: 1, y: 2 };
    p = Point { x: 3, y: 4 };     // E-LS-ALIAS：非 mut 的第二次赋值
}
```

判定表：

| 声明 | 首次 `x = v` | 再次 `x = v` | 首次赋值前读取 |
|---|---|---|---|
| `let x: T;` | 初始化，允许 | `E-LS-ALIAS` | `E-LS-INIT` |
| `let mut x: T;` | 初始化，允许 | 允许 | `E-LS-INIT` |
| `let x: T = e;` | 已在声明处 init | `E-LS-ALIAS` | — |
| `let mut x: T = e;` | 已在声明处 init | 允许 | — |

> `mut` 不是“允许未初始化”的开关；它只授予初始化之后的写权限。
> 这条与 `00 §4.1` 的“默认拥有、可 move”一致，不引入零值/默认构造。
> 当前 `checker-spike` 只对直线代码做保守检查；路径敏感 definite-assignment
> 与“非 mut 第二次赋值”的完整诊断由 S0′ 的初始化分析实现。

## 7. 未决 / 待验证

| # | 项 | 阻塞 | 计划 |
|---|---|---|---|
| M-1 | 源区域结束后使用 `Packet` 的检查（A-5） | **已收口**：`Rgn*` 逐字段足迹 + R4/`(Region)` 约束（`semantics.md` 的 Rgn* 与 R4 小节） | — |
| M-2 | `parse` 无 `memcpy` 的 IR/汇编验证（A-2） | 需要后端 | S0′ |
| M-3 | `cell` 与 `val` 的别名规则边界 | 库 API 表达力 | W3 |
| M-4 | `recover` 是否需要跨函数逃生舱 | 零拷贝归还 | S4 |
| M-5 | 初始化状态的路径敏感 definite-assignment（`if`/`while` 汇合） | S0′ 检查器 | S0′ |

## 8. 语料

- `dossiers/views/accept.ls` / `reject.ls`（当前）；
- `tests/conformance/accept|reject`（S-1 期间 ≥20 条负例）；
- 首批 reject：`E-LS-UNIQ-val-alias-field.ls`、`E-LS-MOVE-use-after-move.ls`、
  `E-LS-INIT-read-uninitialized.ls`（checker-spike 本地 PASS）。

## 9. 冻结条件

- R1–R8 每条有正/负例；
- §4 视图规则被 checker 接受（A-1/A-3/A-6/A-7）；
- 最小不可满足核有 1 个可复现样例；
- A-5 已收口：`Rgn*` 逐字段足迹 + R4/`(Region)` 约束（`semantics.md`）；
- Q8 `val` 别名策略与本文件 §2.1/§6.1 一致，`bad()` 负例被拒；
- Q9 未初始化 `let` 的“首次赋值 = 初始化”有正/负例（`E-LS-INIT`/`E-LS-MOVE`）。
