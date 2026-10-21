# spec/semantics.md · 核心操作语义与元理论（草稿）

> **状态**：`草稿`。18 条小步规则为「冻结候选」；R1–R8 已改为带输出 `⊣ Σ'`（`Σ=(Γ,Λ,M,H)`），
> M2 的 L-Adequacy/Preservation/L4 与 M3 核心已写出（`t4-proof.md` 的 M2/M3 章节；
> S10/S11/S12/S14 条件）；完整 M3 与 Progress 未完成；T1–T3 是纸面证明草稿；T4 **明确未证明**。
> **最近变更（2026-10-18）**：按 ADR-31 方案 B 补 `H : Place ⇀ ℘(Bid)`、判定输出 `Σ'`、
> `Aliases*`/`Consumed*`（按**别名出现位置**计），并补结构体构造/字段读取规则；
> 这是 G2 的文档修复，不等于 T4a 已证明。
> **上位**：[`00 §4.4`](../00-LangSysQuanta-设计初稿.md)（借用/逃逸）、
> [`00 §4.5`](../00-LangSysQuanta-设计初稿.md)（区域推断）、
> [`00 §4.8`](../00-LangSysQuanta-设计初稿.md)（形式化义务）、
> [`00 §6.2`](../00-LangSysQuanta-设计初稿.md)（gate matrix）、
> [`00 §8.1`](../00-LangSysQuanta-设计初稿.md)（UB 清单）、
> [`00 §8.2`](../00-LangSysQuanta-设计初稿.md)（安全子集）、
> [`00 §9`](../00-LangSysQuanta-设计初稿.md)（S5 形式化）。
> **相邻**：[`modes.md`](modes.md)、[`effects.md`](effects.md)、[`ub.md`](ub.md)、
> [`bls.md`](bls.md)、[`../02-架构评审与ADR.md`](../02-架构评审与ADR.md)（ADR-8 / ADR-19）。
> **权威**：与 `00` 冲突以 `00` 为准；本文件只把 `00` 的语义**写成规则**，不新增语言特性。
> **范围**：L-Sys₀ 核心演算的 18 条小步规则、静态检查判断、内存模型公理、T1–T4 与证明草稿。
> **不在本文件**：完整 surface 语法（见 [`langSysQuanta.ebnf`](langSysQuanta.ebnf)）、后端/ABI、
> `comptime`、FFI、中断/DMA 域形式化（`H-LS-16`）、完整线程定理（`H-LS-3`，S3）。

---

## 0. 读法与状态

### 0.1 本文件解决什么

`00 §4.8` 列了 8 条形式化义务，`04` 的 S-1 要求「小步操作语义（≤ 20 条规则，含 region/mode/`recover`）」。
本文件交付三件东西：

1. **一个可实现的动态语义**：18 条小步规则，足够写参考解释器、生成 conformance 用例；
2. **一个可检查的静态语义**：R1–R8 的判断形式、区域格、约束求解与可复现的不可满足核（不保证全局最小）；
3. **一个诚实的元理论**：T1–T3 有证明草稿，T4 明确标注未证明，不把计划写成结论。

### 0.2 状态表

| 对象 | 状态 | 位置 |
|---|---|---|
| 18 条小步规则 | 冻结候选（S-1 内评审） | §3.3 |
| R1–R8 规则化 | 草稿（`⊣ Σ'` + `H` 已写回） | §2.3 |
| `Σ'` / `H` 静态输出 | 草稿（ADR-31 方案 B） | §2.2–§2.3 |
| 区域格（树展开） | 草稿（澄清 `00 §4.0` 的链式缩写） | §2.4 |
| 约束求解 L1/L2 | 纸面证明 | §2.6 |
| 确定性 L3 | 纸面证明 | §3.5 |
| 不变量保持 L4 | 草稿（仅 5/18 例复核） | §5.2 |
| T1a 求解成功 ⇒ 无逃逸 | 纸面证明 | §2.7 |
| T1 逃逸 soundness（运行时） | 草稿 | §5.1 |
| T2 别名 / 线程域 | 草稿（仅 `F_thr` 片段） | §5.2 |
| T3 `recover` 唯一性 | 草稿 | §5.3 |
| T4 安全子集无 UB | **未证明（M2 Adequacy 已写出）** | §5.4 |
| 机械化 | L3 F0 核心 + Runtime 地基片段（2026-10-20） | §7.4 / `lean/README.md` |

> **纪律**：T4 未证明前，README、评审结论、对外材料**不得**写「安全子集无 UB 已成立」，
> 只能写「T4 的目标陈述与本文件的规则基线」。

### 0.3 记号

| 记号 | 含义 |
|---|---|
| `⊑` / `⊐` | 区域偏序：内层/短寿命 ⊑ 外层/长寿命；`⊐` 为严格外层 |
| `⟨e, S⟩ → ⟨e', S'⟩` | 单步归约 |
| `→*` | 自反传递闭包 |
| `read(p)` / `S[p←v]` | 读写 place `p`；自动解引用 |
| `β(l)` | 根位置 `l` 的所有权/别名状态 |
| `B(b)` | 借用/别名 `b` 的 `(mode, place, ρ_s)` |
| `INIT(p)` | `read(p) ≠ ⊥` |
| `LIVE(l)` | `β(l).st = live` |
| `REFS(l)` | 指向 `l` 子位置的活别名集合 |
| `REACH(v)` | 从值 `v` 可达的位置与别名集合 |
| `CONSUMED(e)` | 块 `e` 动态消费的别名/`val` 句柄集合（S9） |
| `H(q)` | 静态别名表：place `q` 的**值内部**所含的活别名 id 集合 |
| `Holders(Σ,b)` | `{ q | b ∈ H(q) }`：仍持有别名 `b` 的 place 集合 |
| `Aliases*(Σ,p)` | 指向 `p` 的活别名的**出现位置**集合 `(q,b)`（含聚合字段/索引） |
| `Consumed*(Σ,Σ')` | 在 `Σ→Σ'` 中被消费掉的别名出现位置 `(q,b)` |
| `COPY(v)` | 平凡可复制值（无 `uniq` 字段、无句柄） |

---

## 1. 核心演算 L-Sys₀

### 1.1 为什么需要核心演算

Surface 语言有泛型、`match`、`defer`、属性等；把全部语法写进操作语义会淹没内存规则。
标准做法是先定义一个**核心演算** L-Sys₀，只保留与 region/mode/cap/`recover` 相关的构造，
surface 通过机械脱糖映射到核心。L-Sys₀ 不是第二门语言，而是 `00 §5` 的语义内核。

### 1.2 语法

```text
(* 值；Loc 是所有权的运行时表示 *)
v ::= () | n | true | false
    | Loc l                 (* uniq/iso 值的根 *)
    | C(v⃗)                 (* struct / enum 构造 *)
    | val(b)                (* frozen 别名（仿射句柄） *)
    | ref(b)                (* mut 借用（仿射句柄） *)
    | cap(κ)                (* 线性权限令牌 *)
    | handle(d)             (* 线程句柄，仅运行时 *)
    | raw(l, o)             (* 裸指针：根 + 偏移 *)
    | ⊥                     (* 仅出现在 σ 中：未初始化 *)

(* 表达式 *)
e ::= v | x
    | op(e⃗)                (* 纯运算，δ 表定义 *)
    | let x = e; e
    | move p
    | read p
    | p := e
    | e; e
    | region R { e }
    | alloc(a, e)
    | freeze p
    | recover { e }
    | borrow mut p as x { e }
    | drop p
    | f(e⃗)
    | return e
    | spawn(f, e)
    | atomic(o, p, e)
    | unsafe { e }
    | deref_raw e
    | abort(k)              (* 定义行为：trap 的终点 *)

(* place *)
p ::= x | p.f | p[i]
```

**省略但可脱糖**：`if`/`match` 进入 δ 表；`while`/`for` 用派生规则 `D-While` 展开
（`while c { e } ⇒ if c { e; while c { e } }`，不计入 18 条）；`box`/`iso`/`val` 类型标注只影响静态判断；
`a.alloc(v)` 脱糖为 `alloc(a,v)`；隐式解引用按 `00 §4.3` 的 `b[i] ≡ (*b)[i]` 处理。
`let x: T;`（未初始化声明）在 core 记为 `let x = ⊥; e`，其中 `⊥` 只出现在 `σ` 中；
首次赋值即初始化，路径敏感规则与诊断见 [`modes.md`](modes.md) 的 Q9 小节。
本文件 §2 不展开 definite-assignment，`E-LS-INIT` 由初始化分析提供。

### 1.3 配置

```text
S = (γ, σ, β, B, Δ, D, κ, τ)
γ : Var ⇀ Val                 变量绑定（move 后删除）
σ : Loc × Path ⇀ Val          堆/区域存储；根位置 + 字段/索引路径
β : Loc ⇀ Bor                 根位置状态
Bor = (own : Mode, refs : ℘(Bid), st : live | moved | dead)
B : Bid ⇀ (mode, place, ρ_s)  活别名表（ref/mut/val）
Δ : Region ⇀ ℘(Loc)           区域分配集（根位置）
D : Loc ⇀ Domain              并发域：Thread | Irq(k) | Dma
κ : Frame list                调用帧 + 块帧（`Borrow(b,p)`，借用退出用）
τ : Event list                事件轨迹（R/W/Acq/Rel/Freeze/Recover/Spawn/Fence/Audit）
```

**place 与解引用**：`p` 是路径表达式，`⟦p⟧` 是句柄值；`read(p)` 自动解引用：

```text
⟦x⟧      = γ(x)
⟦p.f⟧    = field(⟦p⟧)
⟦p[i]⟧   = index(⟦p⟧)

deref(Loc l)   = σ[l]
deref(ref(b))  = read(B(b).place)
deref(val(b))  = read(B(b).place)
deref(v)       = v

read(p)  = deref(⟦p⟧)
mode(p)  = β(root(p)).own | frozen (val) | mut (ref) | copy (immediate)
DOM(p)   = D(root(p))
```

`root(p)` 是 `⟦p⟧` 的所有权根：`Loc l` 取 `l`，`val(b)`/`ref(b)` 取 `B(b).place` 的根。
`INIT(p) ⇔ read(p) ≠ ⊥`；`BOUNDS(p)` 在 `p[i]` 上检查 `0 ≤ i < len`，越界由 δ 产生
`abort(Bounds)`。`S[p←v]` 是 place 更新：根为变量时改 `γ`，为 `p.f`/`p[i]` 时改
`σ` 的对应路径；它不复制所有权，只替换该 place 的值。

```text
DropOld(S, p):
  old = read(p)
  old = Loc l ∧ mode(p) ∈ {uniq, mut}  ⇒ DropVal(S, p)   (* 覆盖前析构旧值 *)
  old = val(b) ∨ old = ref(b)           ⇒ S[B-=b, REFS(root(p))-=b]
  否则                                   ⇒ S

Write(S, p, v) = DropOld(S, p)[p←v]
```

`Write` 防止赋值泄漏旧 `box`，也防止旧 `val`/`ref` 别名在 `B` 中残留。
`read p` 不把 `ref`/`val` 句柄本身复制出来（与 surface 的隐式解引用一致）；
要移动句柄本身，用 `move p`。

**作用域**：所有绑定在脱糖时 α-重命名为唯一名字，因此 `γ` 可视为平坦映射；
帧记录 `locals`，在返回时按逆序删除/析构（S14）。块退出不另立规则，避免与 18 条核心重复。

**事件约定**：所有读写、原子、`freeze`/`recover`、`spawn`、`unsafe` 审计都向 `τ` 追加事件。
为可读性，规则中只在语义相关处显式写 `τ +=`；`τ` 的唯一消费者是 §4 的 `hb` 定义。

### 1.4 良构不变量

配置 `S` 良构（记 `WF(S)`）当且仅当：

| # | 不变量 |
|---|---|
| I1 | `l ∈ Δ(ρ) ⇒ l` 的分配区域是 `ρ`；`D(l)` 在 `iso` 转移外不变 |
| I2 | `B(b) = (m, p, ρ_s) ⇒ l(p) ∈ dom(σ) ∧ b ∈ β(l(p)).refs` |
| I3 | `β(l).refs` 中 `mut` 至多一个；`frozen` 可多个；`mut` 与 `frozen` 不共存于同一根位置 |
| I4 | 每个活 `b` 满足 `ρ_s(b) ⊑ ρ(target(b))`（引用作用域不长于目标区域） |
| I5 | `Δ` 按区域树嵌套；释放父区域先释放子区域，顺序为分配逆序 |
| I6 | 没有活 `ref`/`val` 指向已 `dead` 的根位置 |
| I7 | `H(q)` 中的每个 `b` 都在 `Λ` 中存活（`H` 不记录已消费别名） |
| I8 | 每个活 `b` 至少有一个 holder（`Holders(Σ,b) ≠ ∅`），除非它正作为表达式结果“在飞行中”；飞行别名由判断的 `A` 输出承载 |

I7/I8 是 `H` 与 `Λ` 的双向对应：`Λ` 负责任务/借用身份，`H` 负责“这个别名被复制到了哪些 place”。
没有 I7/I8，`recover` 只能看到 `Λ` 的别名 id，看不到聚合字段里的副本（M2 反例）。

`WF` 是 T1–T3 的载体；规则必须保持 `WF`（L4）。

---

## 2. 静态语义

### 2.1 类型与模式

```text
T ::= Unit | Int | Bool | C[T⃗]
    | box_ρ[T] | iso[T] | val_ρ[T] | ref_ρ[T] | shared[T] | rawptr[T] | Slice_ρ[T]
    | Cap[K]                     K ∈ {Unsafe, Alloc, Mmio[a..b], Dma, Ffi, Spawn}
m ::= uniq | frozen | mut | atom | raw
```

区域 ρ 只出现在推断类型与诊断中（`00 §4.2`）；源码不写生命周期参数。
`ref`/`box` 的字段与索引自动解引用（`00 §6.1`）。

### 2.2 判断与状态

静态状态是一个四元组（ADR-31 方案 B）：

```text
Σ = (Γ, Λ, M, H)
Γ : Var ⇀ (T, m, ρ)            变量 → 类型/模式/区域；`moved` 用 M 表示
Λ : ℘(Borrow)                  活跃借用/别名集（mut 与 frozen）
    Borrow = (b, place, m_b, ρ_b)
M : ℘(Place)                   已 move 的 place（存根，覆盖其字段/索引）
H : Place ⇀ ℘(Bid)             每个 place 的值内部所含的活别名集合
```

`M` 存的是所有权根/被移动的 place；`moved(Σ,p) ⇔ ∃q∈M. overlap(q,p)`，
所以 `move s` 之后 `s.f` 也不可用。`H` 是 flow-sensitive 的：`move`/`drop`/强写会把
对应 place（及其后代）的 `H` 清空，`let`/函数实参/聚合构造/存储会把结果别名写回。

判断：

```text
Σ; ρ ⊢ e : T @ m ▷ C ⊣ Σ' ; A     表达式：类型 T、模式 m、约束 C、输出状态 Σ'、结果别名集 A
Σ ⊢ p : T @ m at ρ_p               place：类型 T、模式 m、区域 ρ_p
Σ ⊢ ok(p)                          权限判断（R1–R8 的结论；ok 是族名）
```

`C` 是区域约束集合 `{ρ₁ ⊑ ρ₂, …}`；`ρ` 是当前函数/块的 ambient region。
判断是**流敏感**的：`M`/`Λ`/`H` 都随子表达式输出 `Σ'` 传递。`A` 是结果值携带的别名集合，
供 `let`/存储/构造/`recover` 写回 `H`；不需要时省略。
程序被接受 ⇔ `solve(C)=Ok`；`Err(core)` 的第一条约束按生成它的 R 规则映射到
[`diagnostics.md`](diagnostics.md) 的诊断码。运行时规则假定静态检查已通过。

辅助定义：

| 谓词/函数 | 定义 |
|---|---|
| `live(Λ,p)` | `{ b ∈ Λ \| overlap(B(b).place, p) }`；值 `v` 取 `live(Λ, place(v))` |
| `Desc*(p)` | `{ p } ∪ { p.f…, p[i]… }`：`p` 的字段/索引路径闭包 |
| `Anc*(p)` | `{ q | p ∈ Desc*(q), q ≠ p }`：`p` 的祖先 place |
| `H*(Σ,p)` | `⋃ { H(Σ,q) \| q ∈ Desc*(p) }`：`p` 整棵值的别名足迹 |
| `Holders(Σ,b)` | `{ q ∈ dom(H) \| b ∈ H(Σ,q) }` |
| `Aliases*(Σ,p)` | `{ (q,b) \| b ∈ live(Λ,p) ∧ q ∈ Holders(Σ,b) }`；**按出现位置计**，含聚合字段 |
| `Consumed*(Σ,Σ')` | `{ (q,b) \| b ∈ H(Σ,q) ∧ (q ∉ dom(H(Σ')) ∨ b ∉ H(Σ',q)) }` |
| `Hval(Σ,e)` | 表达式 `e` 在入口状态 `Σ` 下的结果别名集；权威值是规则的 `A` 输出 |
| `isLocal(p)` | `p` 是局部变量槽（不是堆/区域根） |
| `overlap(p,q)` | `p`、`q` 同根，且其中一个路径是另一个的前缀 |
| `root(p)` | `p` 的所有权根位置 |
| `ρ(p)` | `root(p)` 的分配区域 |
| `COPY(T)` | 平凡可复制类型（无 `uniq`/`frozen` 句柄、无 `box/ref/val` 字段） |
| `Rgn(v)` | 值的**外层**区域：`ref_ρ/val_ρ/box_ρ` 取 `ρ`，`iso` 取 `heap`，`shared` 取 `thread`，标量无 |
| `Rgn*(T)` | 值的**区域足迹**：递归收集可达的 `ref/val/box/slice` 区域（含嵌套字段）；标量 `∅` |
| `regOf(T,ρ)` | 绑定区域：`ref_ρ/val_ρ/box_ρ` 取类型上的 `ρ`，`iso→heap`，`shared→thread`，否则取 ambient `ρ` |

`Rgn*` 的递归定义（A-5 的逐字段展开）：

```text
Rgn*(标量) = ∅
Rgn*(ref_ρ[T])   = {ρ} ∪ Rgn*(T)
Rgn*(val_ρ[T])   = {ρ} ∪ Rgn*(T)
Rgn*(box_ρ[T])   = {ρ} ∪ Rgn*(T)
Rgn*(Slice_ρ[T]) = {ρ} ∪ Rgn*(T)
Rgn*(iso[T])     = {heap}   ∪ Rgn*(T)
Rgn*(shared[T])  = {thread} ∪ Rgn*(T)
Rgn*(C{f_i:T_i}) = ⋃ᵢ Rgn*(T_i)
Rgn*(enum)       = ⋃ 各 variant 的 payload 足迹
Rgn*(Fn/Cap/rawptr) = ∅
```

`Rgn(v)` 只用于“这个值本身在哪”；**存储/返回/跨域/区域退出**一律用 `Rgn*(v)`，
因为内嵌的 `ref` 可能指向更短的区域。
| `atomicOp(E)` | `E` 的 redex 是 `p.op(a⃗)`：`p : atom`、`op ∈ atomicOps`（封闭表见 `effects.md` §2.1）；surface 的方法形式经 `elaboration.md` E-21 降到 core `atomic(ord, op, p, v)` |
| `lockCtx(E)` | `E` 处存在活跃 `Guard` 绑定（`Guard` 是 `!Copy` 线性值，随作用域退出释放；见 `modes.md` §2.2） |
| `rankOk(E)` | 对任意活跃 `Guard` 对 `(g₁,g₂)`：`acquire(g₁) < acquire(g₂) ⇒ rank(g₁) ≤ rank(g₂)`；违反 ⇒ `E-LS-IRQ` |
| `unsafeCtx(E)` | 上下文含 `unsafe { □ }` |
| `site(ρ)` | 区域变量的创建点（求解默认值用） |

`Hval` 的关键形态（其余表达式为 `∅`）：

```text
Hval(Σ,x)        = H(Σ,x)
Hval(Σ,p.f)      = H*(Σ,p.f)                 (* 父/子路径的存储都算 *)
Hval(Σ,p[i])     = H*(Σ,p[i])
Hval(Σ,move p)   = H*(Σ,p)                   (* 值连同别名一起移动 *)
Hval(Σ,C(v⃗))    = ⋃ᵢ Hval(Σ,vᵢ)            (* 聚合构造不复制别名 id，只聚集 *)
Hval(Σ,read p)   = A(规则给出的新 b)；Copy(T) 时为 ∅
Hval(Σ,freeze p) = {b}，b 由 R3-freeze 新分配
Hval(Σ,其它)     = ∅
```

`Aliases*` 用**出现位置**而不是裸 `b`，是为了覆盖 `s.f` 这种“别名被复制进另一个聚合”
的情况：`recover` 必须看到所有 holder，而不只是 `Λ` 里那个 id。
`Consumed*(Σ,Σ')` 同理：只有 `(q,b)` 这个出现被移除，才算该副本被消费。

### 2.3 R1–R8 的判断规则

#### 2.3.0 结构规则（节选）

```text
(Let)
  Σ; ρ ⊢ e₁ : T @ m ▷ C₁ ⊣ Σ₁ ; A₁
  Σ₁[x↦(T,m,regOf(T,ρ)), H(x):=A₁]; ρ ⊢ e₂ : T₂ @ m₂ ▷ C₂ ⊣ Σ₂ ; A₂
  ─────────────────────────────────────────────────────────────────────
  Σ; ρ ⊢ let x = e₁; e₂ : T₂ @ m₂ ▷ C₁ ∪ C₂ ⊣ Σ₂ ; A₂

(Call)
  f = fn(x⃗:T⃗)→T eff(E) ▷ C_f      f 的参数别名足迹为 H_f
  Σ; ρ ⊢ v⃗ : T⃗ @ m⃗ ▷ C_v ⊣ Σ_v ; A⃗
  C_call = {ρ_i^formal ⊑ ρ_i^actual}
           ∪ ⋃_{ρ_v∈Rgn*(T)} {ρ ⊑ ρ_v}            (* ρ 是调用点 ambient *)
  Σ' = Σ_v[H_f(x_i):=A_i]                          (* 形参继承实参别名 *)
  ────────────────────────────────────────────────
  Σ; ρ ⊢ f(v⃗) : T @ m ▷ C_f ∪ C_v ∪ C_call ⊣ Σ' ; A_ret

(Region)
  Σ; ρ_R ⊢ e : T @ m ▷ C ⊣ Σ_e ; A_e
  Rgn*(T) = {ρ_v^i} ⇒ C' = C ∪ {ρ_R ⊑ ρ} ∪ ⋃ᵢ {ρ ⊑ ρ_v^i}
  Rgn*(T) = ∅ ⇒ C' = C ∪ {ρ_R ⊑ ρ}
  Σ' = Σ_e ⊖ Desc*(locals(ρ_R))                   (* 区域退出清掉局部 holder *)
  ───────────────────────────────────────
  Σ; ρ ⊢ region R { e } : T @ m ▷ C' ⊣ Σ' ; A_e

(Alloc)
  a : Alloc[ρ_a]      Σ; ρ ⊢ e : T @ m ▷ C ⊣ Σ_e ; A_e
  l fresh      Σ' = Σ_e[H(l):=A_e]                (* 新根包含 e 的别名 *)
  ─────────────────────────────────────────────
  Σ; ρ ⊢ alloc(a,e) : box_{ρ_a}[T] @ uniq ▷ C ∪ {ρ ⊑ ρ_a} ⊣ Σ' ; ∅

(Construct)
  Σ_i; ρ ⊢ v_i : T_i @ m_i ▷ C_i ⊣ Σ_{i+1} ; A_i     (i = 1..n)
  ─────────────────────────────────────────────────────────
  Σ; ρ ⊢ C(v⃗) : C[T⃗] @ uniq ▷ ⋃ᵢ C_i ⊣ Σ_{n+1} ; ⋃ᵢ A_i
```

`C_call` 的方向是**形参使用区域 ⊆ 实参值区域**，返回侧是 **调用者使用区域 ⊆ 返回区域**；
写反会把短寿命实参/返回值传进长寿命上下文，T1a 不成立。实参区域取 `Rgn(v_i)`；
标量取当前 ambient `ρ`。调用约定要求形参与实参的别名足迹一一对应（`H_f(x_i):=A_i`），
否则 `val` 经函数参数进入聚合后会从 `H` 中消失。`A_ret` 是返回值的别名足迹；
若返回区域不允许逃逸，`R4-return` 的约束会拒绝。
其余表达式规则按同样方式组合 `C` 与 `Σ'`；不产生/复制别名的表达式取 `A=∅`。

未初始化声明 `let x: T;` 在 core 中记作 `let x = ⊥; e`：它只建立 `Γ(x)`/`H(x)=∅`，
不产生值；何时算“已初始化”是路径敏感分析（首次赋值 = 初始化，`mut` 只管之后的写）。
本文 §2 不展开 definite-assignment，`E-LS-INIT` 由 `modes.md` 的 Q9 规则提供。

#### 2.3.1 place 判断

```text
(Place-Var)
  Γ(x)=(T,m,ρ_x)      ¬moved(Σ,x)
  ─────────────────────────────
  Σ ⊢ x : T @ m at ρ_x

(Place-Field)
  Σ ⊢ p : C[T⃗] @ m at ρ_p
  ──────────────────────────────
  Σ ⊢ p.f_i : T_i @ m at ρ_p

(Place-Index)
  Σ ⊢ p : Array[T,N] @ m at ρ_p      0 ≤ i < N
  ───────────────────────────────────────────
  Σ ⊢ p[i] : T @ m at ρ_p
```

`box/ref/val` 的字段与索引按 `00 §6.1` 自动解引用；核心把 `p.f`/`p[i]` 视为同一根下的路径。
`moved(Σ,p)` 对路径是保守的：`move s` 后 `s.f` 也不可用；
若需要部分移动，必须在语法/规则里显式拆出子 place（当前核心不做部分移动）。

#### 2.3.2 R1 · `uniq` 无别名

```text
(R1-uniq)
  Σ ⊢ p : T @ uniq at ρ_p      live(Λ,p)=∅
  ───────────────────────────────────────────
  Σ ⊢ uniqOk(p)

(R1-use)
  Σ ⊢ p : T @ uniq at ρ_p      Σ ⊢ uniqOk(p)      COPY(T)
  ──────────────────────────────────────────────────────
  Σ; ρ ⊢ read p : T @ uniq ▷ {ρ ⊑ ρ_p} ⊣ Σ ; ∅

(R1-move)
  Σ ⊢ p : T @ uniq at ρ_p      Σ ⊢ uniqOk(p)      ¬COPY(T)
  ──────────────────────────────────────────────────────
  Σ; ρ ⊢ move p : T @ uniq ▷ {ρ ⊑ ρ_p}
      ⊣ Σ[M += root(p), H ⊖ Desc*(p)] ; H*(Σ,p)

(R1-drop)
  Σ ⊢ p : T @ uniq at ρ_p      Σ ⊢ uniqOk(p)
  ────────────────────────────────────────────────────────────
  Old = H*(Σ,p)
  Σ; ρ ⊢ drop p : Unit @ copy ▷ {ρ ⊑ ρ_p}
      ⊣ Σ[H ⊖ Desc*(p), Λ -= { b ∈ Old | Holders(Σ[H⊖Desc*(p)],b)=∅ }] ; ∅
```

结论中的 `⊣ Σ[M += root(p), …]` 表示后续判断的 moved 集与别名表；再次使用该 place 会因
`Place-Var` 的 `¬moved(Σ,x)` 或 `live(Λ,p)=∅` 失败（`E-LS-MOVE`）。
`move` 把整棵值的别名足迹 `H*(Σ,p)` 作为结果 `A` 交给 `let`/存储规则写回；
源 place 的 `H` 必须清空，否则会出现“已移走但仍持有别名”的假副本。
`drop` 同时从 `Λ` 删除被析构值内部的别名（`H*(Σ,p)`）；前提已保证没有别名指向 `p`。

#### 2.3.3 R2 · reborrow

```text
(R2-borrow)
  Σ ⊢ p : T @ uniq at ρ_p
  Σ ⊢ uniqOk(p)
  b fresh      y ∉ dom(Γ)
  ρ_s = local(borrow-site)      ρ_s ⊑ ρ_p      ρ_s ⊑ ρ
  Σ₁ = Σ[y ↦ (ref_{ρ_s}[T], mut, ρ_s),
          Λ ∪ {(b,p,mut,ρ_s)},
          H(y) := {b}]
  Σ₁; ρ_s ⊢ e : T_e @ m_e ▷ C ⊣ Σ_e ; A_e
  b ∉ A_e                                          (* 借用不随块结果逃出 *)
  Holders(Σ_e,b) = {y}                              (* 没有副本逃到别的 holder *)
  Σ' = Σ_e - {y} - {b} - H(y)                     (* 退出借用块 *)
  ────────────────────────────────────────────────────────────────────
  Σ; ρ ⊢ borrow mut p as y { e } : T_e @ m_e
      ▷ C ∪ {ρ_s ⊑ ρ_p, ρ_s ⊑ ρ} ⊣ Σ' ; A_e
```

`ρ_s ⊑ ρ_p` 同时是 R2 的检查与 R4 的输入：引用作用域不长于目标区域。
`ρ_s ⊐ ρ_p` ⇒ `E-LS-ALIAS`。

**`ρ_s` 必须是具体的 `local(borrow-site)`，不能是可由求解器抬升的变量**：
否则一个需要更长目的地的存储会把借用作用域抬到块外，`R2` 的 `Λ` 在块结束时删除，
但外部仍持有 `ref`，`uniq` 就出现两个写者——这是明确的 soundness 漏洞。
`ρ_s ⊑ ρ` 保证借用块在当前作用域内；`ρ_s` 具体化保证它不能被抬高。

读 `mut` place 也受作用域约束：

```text
(R2-read)
  Σ ⊢ p : T @ mut at ρ_p      COPY(T)
  ────────────────────────────────────────
  Σ; ρ ⊢ read p : T @ mut ▷ {ρ ⊑ ρ_p} ⊣ Σ ; ∅
```

`b ∉ A_e` 与 `H(y):={b}` 一起保证：`ref` 句柄只能经 `y` 或其副本传播，
块结束时 `Λ`/`H` 中与 `b` 相关的出现全部清除；若结果携带 `b`，直接判 `E-LS-REGION-ESCAPE`。

#### 2.3.4 R3 · freeze / recover

```text
(R3-freeze)
  Σ ⊢ p : T @ uniq at ρ_p      live(Λ,p)=∅      b fresh
  ──────────────────────────────────────────────────────
  Σ; ρ ⊢ freeze p : val_{ρ_p}[T] @ frozen ▷ {ρ ⊑ ρ_p}
      ⊣ Σ[Λ += (b,p,frozen,ρ_p), mode(p):=frozen] ; {b}

(R3-recover)
  Σ; ρ ⊢ e : val_{ρ_p}[T] @ frozen ▷ C ⊣ Σ_e ; A_e
  A_e ≠ ∅      ∀b∈A_e. target(b)=p               (* 同一个冻结根 *)
  Σ_c = ConsumeResult(Σ_e, A_e)                   (* 隐式消费块结果，见下 *)
  Aliases*(Σ_c,p) = ∅                             (* 所有 holder 都已消失 *)
  Σ' = Σ_c[mode(p):=uniq, H(p):=∅, Λ -= live(Λ_c,p)]
  ──────────────────────────────────────────────────────
  Σ; ρ ⊢ recover { e } : T @ uniq ▷ C ⊣ Σ' ; ∅
```

`freeze` 是单向的，返回 `val(b)`；`b` 由 `let`/实参/存储规则写入对应 holder 的 `H`。
`freeze` 不把 `b` 写进 `H(p)`：`H` 记录“值内部装了哪些别名”，不是“谁借用了 `p`”；
后者由 `Λ` 的 `B(b).place` 表达。

`recover` 要求所有别名 holder 都在块内被消费，否则 `E-LS-UNIQ`。规则里的
`ConsumeResult` 把块结果本身按**隐式 move** 处理：

```text
ConsumeResult(Σ, A):
  若结果来自变量 q  ⇒ 删 Γ(q)、清 H(q)；
                      对每个 b∈A，仅当 Holders(Σ,b) ⊆ {q} 时才从 Λ 删除 b，
                      否则保留 b（它还有别的 holder，交给 Aliases* 拒绝）
  否则               ⇒ 只把 A 中“仅在飞行中”的 b 从 Λ 删除（它们尚无 holder）
  返回处理后的 Σ_c
```

于是 `Aliases*(Σ_c,p)=∅` 等价于：块内所有指向 `p` 的别名出现都被移除，
且没有新的 `val` 被存进别的聚合。关键在于 `ConsumeResult` **不会**在还有
其他 holder 时把 `b` 从 `Λ` 删掉——否则 I7 被破坏，`Aliases*` 就看不到 `s.f`。
若只看 `Aliases*(Σ,p) ⊆ Consumed*(Σ,Σ_c)`，
会漏掉“`e` 执行期间新建并存入 `s.f` 的别名”；上面的后置空集检查把这一类也覆盖。
跨函数/跨域 `recover` 直接拒绝（`H-LS-15`）。

**M2 反例检查**（`t4-proof.md` §3.2 的 `bad()`）：

```text
let v = freeze x;          Λ += (b,x);  A={b};  H(v)={b}
let s = S { f: v };        Construct: A={b};  Let 写回 H(s)={b}
recover { v }              ConsumeResult 隐式 move v: 清 H(v)；
                           因 s 仍持有 b，b 保留在 Λ
                           Aliases*(Σ_c,x) 含 (s,b) ≠ ∅  ⇒ E-LS-UNIQ
```

若换回旧的 `Aliases(Λ,p)`（只看 `b`），这个程序会被误接受；
按出现位置计后，聚合里的副本 `H(s)` 让检查失败，这正是 G2 要修的点。
（实现可以把 `H` 细到 `s.f`；规则只用 `H*`/`Holders`，两种粒度都成立。）

读 `frozen` place 产生 `val` 别名；`A` 是新 `b`，由外层绑定/存储写回 `H`：

```text
(R3-read-Copy)
  Σ ⊢ p : T @ frozen at ρ_p      COPY(T)
  ────────────────────────────────────────────────
  Σ; ρ ⊢ read p : T @ frozen ▷ {ρ ⊑ ρ_p} ⊣ Σ ; ∅

(R3-read-Alias)
  Σ ⊢ p : T @ frozen at ρ_p      ¬COPY(T)      b fresh
  ────────────────────────────────────────────────
  Σ; ρ ⊢ read p : val_{ρ_p}[T] @ frozen ▷ {ρ ⊑ ρ_p}
      ⊣ Σ[Λ += (b,p,frozen,ρ_p)] ; {b}
```

#### 2.3.5 R4 · 存储与返回（逃逸检查）

```text
(R4-store)
  Σ ⊢ p_dst : T_dst @ m_dst at ρ_dst
  Σ; ρ ⊢ v : T_v @ m_v ▷ C_v ⊣ Σ_v ; A_v
  Rgn*(v)={ρ_v^i}ᵢ      Old = H*(Σ_v,p_dst)
  Σ' = Σ_v[H ⊖ Desc*(p_dst)]
          [∀q∈Anc*(p_dst). H(q) -= Old]   (* 父 place 若粗粒度记录过旧值，一并去掉 *)
          [H(p_dst) := A_v]              (* 强更新：旧值被析构 *)
          [Λ -= { b ∈ Old | Holders(Σ',b)=∅ }]   (* 只杀掉无其他 holder 的旧别名 *)
  ────────────────────────────────────────────────────────────
  Σ; ρ ⊢ p_dst := v : Unit @ copy
      ▷ C_v ∪ ⋃ᵢ {ρ_dst ⊑ ρ_v^i} ⊣ Σ' ; ∅

(R4-return)
  Σ; ρ_ret ⊢ v : T_v @ m_v ▷ C_v ⊣ Σ_v ; A_v
  Rgn*(v)={ρ_v^i}ᵢ
  ────────────────────────────────────────────────────────
  Σ; ρ ⊢ return v : T_v @ m_v ▷ C_v ∪ ⋃ᵢ {ρ_ret ⊑ ρ_v^i} ⊣ Σ_v ⊖ locals(frame) ; A_v
```

方向必须记牢：`⊑` 是「内层/短寿命」。对 `Rgn*(v)` 里的**每一个** `ρ_v^i`：
存到 `ρ_dst` 要求 `ρ_dst ⊑ ρ_v^i`（目的地不能比任何内嵌引用的有效期更长）；
返回要求 `ρ_ret ⊑ ρ_v^i`；调用点再要求 `ρ_caller ⊑ ρ_ret`。
若写成 `ρ_v ⊑ ρ_dst` 就会把逃逸放行。
`Rgn*(v)=∅`（标量）时不生成约束；`iso` 取 `heap`，返回值安全。
**A-5**：`val`/`box` 内嵌更短寿命的 `ref` 时，足迹包含该 `ref` 的区域，
因此把它存进长寿命位置会因对应的 `ρ_dst ⊑ ρ_ref` 失败而被拒。

存储是**强更新**：`R5-writable` 已保证目的地没有活别名，因此旧值可以被析构，
`H(p_dst)` 整体替换为 `A_v`，而不是与旧集合求并。若实现改用弱更新（例如
`cell`/`atom` 的无条件写），必须保留旧 `H` 并多一条 `H(p_dst) += A_v`；
两者不能用同一套写回。`Old` 中只有 `Holders` 已空的别名才从 `Λ` 删除；若仍有其他 holder，
`I8` 要求它继续存活。

#### 2.3.6 R5 · 写权限（区域级别名）

```text
(R5-writable)
  Σ ⊢ p : T @ m at ρ_p
  m ∈ {uniq, mut} ∨ (m=copy ∧ isLocal(p))
  ¬∃(q,b) ∈ Aliases*(Σ,p):
      B(b).m_b ∈ {frozen,mut} ∧ B(b).ρ_b ⊑ ρ_p
  ────────────────────────────────────────────────────────
  Σ ⊢ writable(p)

(R5-atom)
  Σ ⊢ p : T @ atom at ρ_p
  atomicOp(E) ∨ (lockCtx(E) ∧ rankOk(E))
  ───────────────────────────────────────────
  Σ ⊢ writable(p)

(R5-write)
  Σ ⊢ p : T @ m at ρ_p      Σ ⊢ writable(p)
  Σ; ρ ⊢ v : T @ m_v ▷ C ⊣ Σ_v ; A_v
  Old = H*(Σ_v,p)
  Σ' = Σ_v[H ⊖ Desc*(p)]
          [∀q∈Anc*(p). H(q) -= Old]
          [H(p):=A_v]
          [Λ -= { b ∈ Old | Holders(Σ',b)=∅ }]
  ────────────────────────────────────────────────
  Σ; ρ ⊢ p := v : Unit @ copy ▷ C ∪ {ρ ⊑ ρ_p} ⊣ Σ' ; ∅
```

R5 按**区域**检查（`00 §4.4`「区域级，非全局」），比逐字节别名保守；
`Aliases*(Σ,p)` 按出现位置枚举，所以存储在 `s.f` 里的 `val` 副本也会参与
`writable` 判断，不再只检查 `Λ` 里的借用记录。
fix-it 只能建议缩小作用域/`cell`/复制，**不得**建议 `unsafe`。

#### 2.3.7 R6 · `atom` 访问

```text
(R6-atom)
  Σ ⊢ p : T @ atom at ρ_p
  atomicOp(E) ∨ (lockCtx(E) ∧ rankOk(E))
  ───────────────────────────────────────────────
  Σ ⊢ atomOk(p)

(R6-read)
  Σ ⊢ p : T @ atom at ρ_p      Σ ⊢ atomOk(p)
  ────────────────────────────────────────────
  Σ; ρ ⊢ read p : T @ atom ▷ {ρ ⊑ ρ_p} ⊣ Σ ; ∅
```

`atom` 写走 R5-atom；非原子访问且无锁 ⇒ `E-LS-RACE`；锁 rank 违反 ⇒ `E-LS-IRQ`。
R5-atom 与 R6-atom 共用同一个前提，避免“写”与“读”的授权条件分叉：
`atomicOp(E) ∨ (lockCtx(E) ∧ rankOk(E))`。

#### 2.3.8 R7 · `raw` 与 `Unsafe`

```text
(R7-raw)
  Σ ⊢ p : T @ raw at ρ_p
  Γ(u) = Cap[Unsafe]      Unsafe ∈ eff      unsafeCtx(E)
  ──────────────────────────────────────────────────────
  Σ ⊢ rawOk(p)

(R7-deref)
  Σ ⊢ p : T @ raw at ρ_p      Σ ⊢ rawOk(p)
  ────────────────────────────────────────────
  Σ; ρ ⊢ deref_raw p : T @ raw ▷ {ρ ⊑ ρ_p} ⊣ Σ ; ∅

(R7-write)
  Σ ⊢ p : T @ raw at ρ_p      Σ ⊢ rawOk(p)
  Σ; ρ ⊢ v : T @ m_v ▷ C ⊣ Σ_v ; A_v
  Old = H*(Σ_v,p)
  Σ' = Σ_v[H ⊖ Desc*(p)][H(p):=∅]
          [Λ -= { b ∈ Old | Holders(Σ',b)=∅ }]
  ────────────────────────────────────────────────
  Σ; ρ ⊢ p := v : Unit @ raw ▷ C ∪ {ρ ⊑ ρ_p} ⊣ Σ' ; ∅
```

缺 `Cap[Unsafe]` ⇒ `E-LS-CAP`；缺 `Unsafe` 效果 ⇒ `E-LS-UNSAFE`。
`raw` 的深层义务（对齐/provenance/长度）由 S18 的 `W` 承担，不在 R7 内。
`R7-write` 清空 `H(p)`：裸写之后静态别名表不再可信；这条规则**不在** T4a 的
安全子集 `F0` 内，由 RTT v1 的 `Witness` 接管（`ub.md` §2），不能用它来关闭 `recover` 的检查。

#### 2.3.9 R8 · 跨域转移

```text
(R8-transfer)
  Σ; ρ ⊢ v : T @ m ▷ C ⊣ Σ_v ; A      m ∈ {iso, atom, frozen}
  m ∈ {iso, atom} ⇒ C' = C
  m = frozen ⇒ C' = C ∪ ⋃_{ρ_v∈Rgn*(v)} {thread ⊑ ρ_v}
  m = iso ⇒ live(Λ,v)=∅ ∧ Holders(Σ_v,b)=∅ (b∈A)
  ────────────────────────────────────────────────────────
  Σ ⊢ transferable(v) ▷ C' ⊣ Σ_v ; A

(R8-spawn)
  Σ ⊢ transferable(v) ▷ C_v ⊣ Σ_v ; A
  Σ; ρ ⊢ v : T @ m ▷ C
  CAP_SPAWN（kernel）
  Σ' = Σ_v[H(source(v)) := ∅, Λ -= A]       (* iso 转移后源域不再持有 *)
  ────────────────────────────────────────────────────────
  Σ; ρ ⊢ spawn(f,v) : handle(d) @ copy ▷ C ∪ C_v ⊣ Σ' ; ∅
```

`box`/`ref` 跨域 ⇒ `E-LS-RACE`；`iso` 转移唯一所有权；`val` 还要求
对 `Rgn*(v)` 的**每个**区域 `thread ⊑ ρ_v`（目标区域至少线程级），
否则内嵌引用可能先于目标域释放。

#### 2.3.10 R1–R8 速查

| 规则 | 判断结论 | 拒绝码 | 动态规则 |
|---|---|---|---|
| R1 | `uniqOk(p)` / `read p` / `move p` / `drop p` | `E-LS-MOVE` | S3/S4/S12 |
| R2 | `borrow mut p as y { e }` / `read p` | `E-LS-ALIAS` | S6/S7 |
| R3 | `freeze p` / `read p` / `recover { e }` | `E-LS-UNIQ` | S8/S9 |
| R4 | `p := v` / `return v` | `E-LS-REGION-ESCAPE` | S5/S14 |
| R5 | `writable(p)` / `p := v` | `E-LS-ALIAS` | S5 |
| R6 | `atomOk(p)` / `read p` | `E-LS-RACE` / `E-LS-IRQ` | S16 |
| R7 | `rawOk(p)` / `deref_raw p` | `E-LS-UNSAFE` / `E-LS-CAP` | S18 |
| R8 | `transferable(v)` / `spawn(f,v)` | `E-LS-RACE` / `E-LS-REGION-ESCAPE` | S15 |

所有规则都带 `⊣ Σ'`；`A` 只在需要写回 `H` 的规则中显式写出。
`freeze`/`read` 新分配的 `b` 先作为 `A` 返回，由 `let`/`Call`/`R4-store`/`Construct`
写入 holder 的 `H`；没有这一步，`recover` 就看不到聚合字段里的副本。

### 2.4 区域格（树展开）

`00 §4.0` 把区域写成一条链：

```text
local(s) ⊑ region(R) ⊑ thread ⊑ heap(H) ⊑ static
```

这条链是**层级顺序**的缩写。实际偏序是树：两个 `local(π₁)`、`local(π₂)` 可能不可比
（兄弟作用域），链式写法无法表达。本文件按树展开，层级顺序不变：

```text
Region ::= local(π) | region(R) | thread(d) | heap(H) | static
```

`⊑` 由以下规则生成（自反传递闭包）：

1. `local(π) ⊑ local(π')` 若 `π'` 的词法作用域包含 `π`；
2. `local(π) ⊑ region(R)` 若 `π` 位于 `R` 内；
3. `region(R) ⊑ region(R')` 若 `R` 嵌套在 `R'` 内；
4. `region(R) ⊑ thread(d) ⊑ heap(H) ⊑ static`；
5. `local(π) ⊑ thread(d) ⊑ heap(H) ⊑ static`（同域）。

`ρ₁ ⊔ ρ₂` 取最小公共祖先（LCA）。树没有 bottom（两个兄弟 `local` 不可比），
但约束只使用 `⊑` 与 LUB，`solve` 不需要 GLB。

### 2.5 约束求解伪代码

约束语法：

```text
C ::= ∅ | {ρ₁ ⊑ ρ₂} ∪ C
```

生成点：R2（`ρ_s ⊑ ρ_p`）、R4（`ρ_dst ⊑ ρ_v` / `ρ_c ⊑ ρ_v`）、R8（`thread ⊑ Rgn(v)`），
以及 `alloc`/`freeze`/`recover` 的区域传播（`00 §4.5`）。

**求解思路**：每个变量从最小默认值 `local(site)` 开始，只向**上**抬（RHS 抬高）。
对约束 `a ⊑ b`，若 `val(a) ⋢ val(b)`，则把 `b` 抬到 `lub(val(a), val(b))`；
若 `b` 是具体区域、无法再抬，则该约束不可满足。

**site-bound 与 ceiling**（T1a-mono 的前提）：每个推断区域变量 `ρ` 由唯一 site 创建，
其抬升上界是 `ceil(ρ)`——site 所在的**最近具体区域**：

```text
region R { ... } 内创建的变量      ceil(ρ) = R
函数体内、任何 region 之外        ceil(ρ) = local(fn)      (* 函数 ambient *)
顶层 static 变量                  ceil(ρ) = static
具体区域（thread/heap/static）     ceil(ρ) = ρ
```

`ceil` 由 site 静态确定；求解器不允许把变量抬到 `ceil` 之上。**区域多态函数值不在
`F0`**（§2.7），因此 `ceil` 总是可定义的。

```python
# 节点：local(π) / region(R) / thread(d) / heap(H) / static
# leq(a,b) = a 是 b 的后代（a ⊑ b）
# lub(a,b) = 最近公共祖先（LCA）

def solve(C):
    val, ceil = {}, {}
    for v in nodes(C):
        if concrete(v):
            val[v] = ceil[v] = v
        else:
            val[v] = local(site(v))
            ceil[v] = ceil_of(site(v))

    work = list(C)
    while work:
        a, b = work.pop()
        if leq(val[a], val[b]):
            continue
        if isVar(b):                       # 抬 RHS，但不许越过 ceiling
            new = lub(val[a], val[b])
            if not leq(new, ceil[b]):
                return Err(core_path(C, a, b, val, ceil, True))
            if new != val[b]:
                val[b] = new
                work.extend(C)             # 所有涉及 b 的约束重查
        else:                              # b 是具体区域，抬不动
            return Err(core_path(C, a, b, val, ceil, False))

    return Ok(val)
```

`core_path` 返回一条**不可满足路径**（不保证全局最小）：

```python
def core_path(C, a, b, val, ceil, capped):
    # 反向 BFS：找一条把 val[a] 抬到 b 之上的约束链；
    # 若卡在 ceiling，把 (b, ceil[b]) 也放进核。
    frontier = [(a, [(a, b)])]
    seen = {a}
    while frontier:
        x, path = frontier.pop(0)
        for (u, v) in C:
            if v == x and u not in seen:
                if leq(val[u], b) and not leq(val[x], b):
                    return [(u, v)] + path
                seen.add(u)
                frontier.append((u, path + [(u, v)]))
    if capped and isVar(b):
        return [(a, b), (b, ceil[b])]
    return [(a, b)]
```

**终止性**：每次抬升都严格增加某个变量在区域树中的位置；树高有限，故最多
`O(|Var| × height)` 次抬升；worklist 每条约束在每次抬升后重查，总步数有限。
**核（core）**：返回一条不可满足路径；触及 ceiling 时附带 `(b, ceil[b])`。
`00 §4.5` 的「通常 2–3 条」是经验值，不写成定理。

### 2.6 求解引理

**L1（soundness）**：若 `solve(C)=Ok(σ)`，则 `σ ⊨ C`。
证明：`Ok` 只在 worklist 为空时返回；worklist 非空时，每条被弹出的约束要么成立，
要么触发一次抬升并把**全部**约束重新入队。因此返回时每条约束都已被检查且成立。
（`Err` 分支在 `b` 为具体区域且 `val[a] ⋢ b` 时返回，此时该约束无解。）

**L-Ceiling**：若 `solve(C)=Ok(σ)`，则 `∀ρ. σ(ρ) ⊑ ceil(ρ)`。
证明：初值 `local(site(ρ)) ⊑ ceil(ρ)`；每次抬升都被 `leq(new, ceil[b])` 截断，
所以 `σ(ρ)` 始终在 `ceil(ρ)` 内。∎

**L2（site-bounded completeness）**：若 `C` 有一个 site-bounded 模型 `σ'`
（即 `∀ρ. σ'(ρ) ⊑ ceil(ρ)`），则 `solve(C)=Ok`。
证明：设 `σ'` 是任一 site-bounded 模型。对抬升次数归纳证明不变式 `val[v] ⊑ σ'(v)`：

1. 初值 `local(site(v)) ⊑ σ'(v)`，且由 site-bounded 得 `σ'(v) ⊑ ceil(v)`；
2. 若 `val[a] ⊑ σ'(a)`、`val[b] ⊑ σ'(b)`，且 `a ⊑ b` 在 `σ'` 下成立，则
   `lub(val[a], val[b]) ⊑ σ'(b) ⊑ ceil(b)`，cap 不会误拒；抬升后的 `val[b]` 仍 ⊑ `σ'(b)`；
3. 若 `b` 是具体区域，`σ'(b)=b`；`val[a] ⋢ b` 意味着 `σ'(a) ≥ val[a] ⋢ b`，
   与 `σ'(a) ⊑ σ'(b)=b` 矛盾。

故算法不会在可满足的 `C` 上返回 `Err`；而由 L1，返回 `Ok` 时 `val` 就是模型。∎

> L1/L2 是纸面证明；S0′ 用 union-find/树原型 + 属性测试复核（§7.4）。

### 2.7 T1a-mono · 求解成功 ⇒ 无逃逸（site-bound）

**区域模型的解释**：

```text
⟦ρ⟧ = { t | 区域 ρ 在时刻 t 仍存活 }
ρ ⊑ ρ'  ⇔  ⟦ρ⟧ ⊆ ⟦ρ'⟧
```

即 `⊑` 是「存活期包含」的逆序写法：内层/短寿命区域的存活点集合更小。
引用 `ref_{ρ_r}[T]` 的语义承诺是：**在 `⟦ρ_r⟧` 的每个时刻，目标都存活**（I4）。

**定义（逃逸）**：

```text
Escape(e) ⇔
  ∃ 引用创建：σ(ρ_r) ⊐ σ(ρ_t)            (* 引用活得比目标长 *)
  ∨ ∃ 存储/返回：σ(ρ_dst) ⊐ σ(ρ_v)       (* 目的地活得比引用有效期长 *)
```

**定理 T1a-mono**（site-bound 片段）：若 `P ∈ F0`（因而无区域多态函数值）、
`Σ;ρ ⊢ e : T@m ▷ C` 且 `solve(C)=Ok(σ)`，则 `¬Escape(e)`。

**证明**：

1. **所有区域变量 site-bound**：`F0` 的函数类型不含 `∀ρ`（`elaboration.md` 的 `fn`
   签名只写具体区域），`C` 中的变量都来自推断 metavariable，`ceil` 由 site 静态确定。
   由 **L-Ceiling**，`∀ρ. σ(ρ) ⊑ ceil(ρ)`。
2. **约束生成覆盖逃逸点**（对判断树归纳）：
   - R2 的结论含 `ρ_s ⊑ ρ_t`，`ρ_s` 是具体 `local(site)`，求解器只检查、不抬升它；
   - R2-read / R3-read 只产生 `ρ_t` 的别名，不新建区域；其 `Rgn` 直接进 R4 的约束；
   - R4-store 的结论含 `∀ρ_v∈Rgn*(v). ρ_dst ⊑ ρ_v`，R4-return 含
     `∀ρ_v∈Rgn*(v). ρ_c ⊑ ρ_v`；足迹递归覆盖内嵌字段（A-5）；
   - `(Region)` 的结论含 `∀ρ_v∈Rgn*(T). ρ ⊑ ρ_v`（结果必须比区域块活得久）；
   - R3 的 `freeze`/`recover`、R8 的 `transfer` 只在 `C` 上组合或增加
     `thread ⊑ Rgn(v)`，不产生反向约束；
   - R1/R5/R6/R7 不引入引用区域；`Let`/`Call`/`Region`/`Alloc` 只组合子表达式的 `C`
     （`C_call` 的方向是 `ρ_formal ⊑ ρ_actual`；`Alloc` 的 `ρ ⊑ ρ_a` 只保证分配区域覆盖使用点）。
3. **引用创建**：`σ(ρ_s) = ρ_s`（具体 local），`σ(ρ_s) ⊑ σ(ρ_t)`；
   由 `⟦ρ_s⟧ ⊆ ⟦σ(ρ_t)⟧`，目标在引用有效期内全程存活。
4. **存储/返回**：对 `Rgn*(v)` 的每个 `ρ_v^i`，有 `σ(ρ_dst) ⊑ σ(ρ_v^i)`。
   若 `ρ_v^i` 是变量，由 L-Ceiling 得 `σ(ρ_v^i) ⊑ ceil(ρ_v^i)`，所以
   `σ(ρ_dst)` 也在 `ceil(ρ_v^i)` 内——目的地在值（含内嵌引用）的 site 作用域内，
   值比目的地活得久。若 `ρ_dst` 在 ceiling 之外，capped solver 在抬升时返回 `Err`，
   与 `Ok` 矛盾。**A-5 由足迹覆盖**：内嵌 `ref` 的区域同样参与这条论证。
5. **`(Region)`**：`ρ ⊑ Rgn(T)`。若结果引用 `R` 本身（`Rgn(T)=R`），则 RHS 是具体区域，
   `ρ ⊑ R` 不成立 ⇒ `Err`；若 `Rgn(T)` 是变量，则 `σ(Rgn(T)) ⊑ ceil(Rgn(T))`，
   ceiling 至少是 `ρ`，故结果比 `R` 活得久。
6. **调用**：`C_call` 只有 `ρ_formal ⊑ ρ_actual`，无区域抽象；实参的区域在调用点
   已知，传递不引入新的 ceiling。
7. 由 2–6，不存在满足 `Escape` 的创建/存储/返回，故 `¬Escape(e)`。∎

**证明的边界（必须保留）**：

- T1a-mono 是**静态检查的 soundness**，不是运行时 T1；运行时还需 `WF(S)` 与 S1–S18 的保持性（L4）。
- 片段：安全子集、无 `unsafe`/`rawptr`/FFI、无跨模块、无递归（`H-LS-29`）。
- 区域模型假设词法作用域与 `spawn` 的单域转移；跨域 `val` 还需 T2 的域论证（`H-LS-3`）。
- `core_path` 不保证最小核；T1a 只依赖「`Ok` ⇒ 全约束成立」，不依赖核的最优性。
- **区域多态不在 F0**：函数类型不含 `∀ρ`，因此 `ceil` 总可定义。若将来引入区域多态
  函数值，`ceil` 必须变成调用点相关的，需要新的定理；登记为 `H-LS-1` 的覆盖缺口。
  本条是 T1a-mono 与“完整 T1a”的唯一差别。
- **A-5 已收口**：`Rgn*(v)` 递归收集嵌套 `ref`/`val`/`box`/`slice` 的区域，
  R4/`(Region)`/`C_call`/R8 都对**每个**足迹区域生成约束。`val` 内嵌短寿命 `ref`
  会在 store/return 处因 `ρ_dst ⊑ ρ_ref` 不成立而被拒。
- T1a 是**条件定理**：它的结论依赖 §2.3 的规则集与 §2.5 的求解器；若实现偏离这两者，
  定理不再适用（S-1 用同一 `C` 生成器做差分测试）。

---

## 3. 动态语义

### 3.1 求值上下文与 δ

```text
E ::= □ | let x = E; e | read E | p := E | E; e
    | f(v⃗, E, e⃗) | alloc(a, E) | freeze E | E.f | E[i]
    | return E | spawn(f, E) | unsafe { E } | deref_raw E
```

`E` 保证**从左到右**求值：实参先于调用，赋值先左后右，语句先前后后（UB-12）。

δ 表（纯运算；确定性）：

```text
n₁ + n₂      = (n₁ + n₂) mod 2^64          (* Int 定义 wrapping，UB-6 *)
n / 0        = abort(Div)                  (* 定义行为，UB-7 *)
n << k, k≥64 = abort(Shift)
i < 0 ∨ i ≥ len(p) = abort(Bounds)         (* Array/Slice 边界；raw 另见 S18 *)
if true  then e₁ else e₂ = e₁
if false then e₁ else e₂ = e₂
match C_i(v⃗) { … }      = e_i[x⃗:=v⃗]
copy v                   = v               (* 仅 COPY(v) *)
```

`abort(k)` 是终点，不再归约；它是**定义行为**，不是 UB（A9）。

### 3.2 18 条规则总表

| # | 规则 | 作用 | 对应 `00` |
|---|---|---|---|
| S1 | Pure | δ + 上下文 | §4.1、§6.9 |
| S2 | Let | 绑定 Copy/仿射值 | §4.1 |
| S3 | Move | 使源 place 失效 | R1 |
| S4 | Read | 读 place；frozen 产生 `val` 别名 | R5、UB-4 |
| S5 | Write | 写 place；R5 区域级别名检查 | R5、UB-5 |
| S6 | Borrow-Enter | 进入借用作用域；压 `Borrow` 帧 | R2 |
| S7 | Borrow-Exit | 弹出借用帧；禁止逃逸 | R2、R4 |
| S8 | Freeze | `uniq → frozen`；生成 owner 句柄 | R3 |
| S9 | Recover | `frozen → uniq`；线性消费 | R3 |
| S10 | Alloc | 区域分配 | §4.2 |
| S11 | RegionExit | 逆序统一释放 | §4.2、UB-2 |
| S12 | Drop | 显式析构 | §6.6、UB-3/14 |
| S13 | Call | 帧、参数、区域实例化 | §4.5、ADR-8 |
| S14 | Return | 弹帧、逆序析构局部 | §6.6 |
| S15 | Spawn | `iso`/`atom` 跨域 | R8、UB-5 |
| S16 | Atomic | 原子/锁；HB 边 | R6 |
| S17 | Unsafe | 消费 `Cap[Unsafe]`、审计 | R7 |
| S18 | Raw | 裸指针解引用；provenance 见证 | R7、UB-8/9/10 |

### 3.3 逐条规则

#### S1 · Pure

```text
δ(r) = r'
──────────────────────────
⟨E[r], S⟩ → ⟨E[r'], S⟩
```

#### S2 · Let

```text
v 是值      COPY(v) ∨ v ∈ {Loc l, val(b), ref(b), cap(κ), handle(d)}
────────────────────────────────────────────────────────────
⟨let x = v; e, S⟩ → ⟨e, S[γ[x↦v]]⟩
```

`val(b)`/`ref(b)`/`Loc l` 在核心中按**仿射**处理：绑定即转移，不复制句柄。
surface 的 `val` 复制语义由 S4 的 `read` 显式产生新别名。
非 Copy 的源在 surface 中先脱糖为 `move`，因此 S2 只会收到已转移的值，不会隐式复制所有权。

#### S3 · Move

```text
γ(x)=v      ¬COPY(v)      v ∈ {Loc l, val(b), ref(b)}      LIVE(root(v))
──────────────────────────────────────────────────
⟨move x, S⟩ → ⟨v, S[γ-=x]⟩
```

再次使用 `x` 会因 `γ` 无绑定而粘滞；静态检查对应 `E-LS-MOVE`。
S3 只列整变量 `move`；字段 move 在 surface 中脱糖为拆分/重建，核心不收部分 move。

#### S4 · Read

```text
INIT(p)   LIVE(root(p))   READABLE(p)   BOUNDS(p)
mode(p)≠frozen ⇒ v=read(p)
mode(p)=frozen ∧ ¬COPY(read(p)) ⇒ b fresh ∧ v=val(b)
mode(p)=frozen ∧ COPY(read(p)) ⇒ v=read(p)
────────────────────────────────────────────────────────────
⟨read p, S⟩ → ⟨v, S[τ+=(R, DOM(p), p, v)]⟩
```

- `READABLE(p)`：`mode ∈ {copy, frozen, mut, atom, raw}`；`uniq` 仅当 `COPY(read(p))`；
- `frozen` 分支：非 Copy 值才登记 `B(b)=(frozen,p,ρ_scope)` 并令 `REFS(root)+=b`；
  Copy 值（如 `val[Int]`）直接返回值，不产生别名记录；
- `atom` 分支要求 `ATOMIC_CTX(E)`，否则静态 `E-LS-RACE`；
- `raw` 分支要求 `UNSAFE_CTX(E)`，否则 `E-LS-UNSAFE`；
- `BOUNDS(p)` 由 δ 检查；越界 ⇒ `abort(Bounds)`（定义行为）。

#### S5 · Write

```text
WRITABLE(p)   BOUNDS(p)   v 是值
────────────────────────────────────────────────────────────
⟨p := v, S⟩ → ⟨(), Write(S, p, v)[τ+=(W, DOM(p), p, v)]⟩
```

`WRITABLE(p)`：

1. `mode(p) ∈ {uniq, mut, copy(局部槽)}`，或 `mode(p)=atom ∧ ATOMIC_CTX(E)`；
2. `¬∃b∈dom(B): overlap(B(b).place, p) ∧ B(b).mode ∈ {frozen, mut} ∧ ρ_s(b) ⊑ ρ(p)`；
3. `mode(p)=frozen` 直接拒绝（`E-LS-ALIAS`）；`raw` 只能走 S18。

写入不要求 `INIT`（写可初始化）；`uniq` 写后不改变所有权。

#### S6 · Borrow-Enter

```text
mode(p)=uniq   REFS(root(p))=∅   ρ_s ⊑ ρ(p)   b fresh
B(b)=(mut, p, ρ_s)      κ' = Borrow(b,p)::κ
────────────────────────────────────────────────────────────
⟨borrow mut p as x { e }, S⟩ →
  ⟨e, S[γ[x↦ref(b)], B+=b, REFS(root(p))+=b, κ:=κ']⟩
```

进入后 `borrow` 包装从项中消失，借用生命周期由 `κ` 的 `Borrow(b,p)` 帧承担；
块内仍是 S1–S18 的小步执行。`ρ_s` 是块的作用域区域，`ρ_s ⊐ ρ(p)` 时 R2 拒绝。

#### S6′ · Borrow-Body（结构规则，不计入 18 条）

```text
⟨e, S[κ=Borrow(b,p)::κ']⟩ → ⟨e', S'[κ=Borrow(b,p)::κ']⟩
────────────────────────────────────────────────────────────
⟨e, S[κ=Borrow(b,p)::κ']⟩ → ⟨e', S'[κ=Borrow(b,p)::κ']⟩
```

借用体内的一步就是配置的一步；帧不变。

#### S7 · Borrow-Exit

```text
B(b)=(_, p, ρ_s)      ref(b) ∉ REACH(v)      κ = Borrow(b,p)::κ'
──────────────────────────────────────────────────────────
⟨v, S[κ=Borrow(b,p)::κ']⟩ →
  ⟨v, S[B-=b, REFS(root(p))-=b, κ:=κ']⟩
```

`S7` 是**帧弹出**：项不变（`v` 仍是 `v`），`κ` 少一帧。它完成“上下文步 + 退出”的退出半边；
`w` 不变但待弹出块帧数 `r` 减 1，见 `t4-proof.md` 的 L-Term 小节。
`ref(b) ∈ REACH(v)` 表示借用逃出作用域；静态对应 `E-LS-REGION-ESCAPE`，
动态上程序粘滞（不应出现在已检查程序中）。

#### S8 · Freeze

```text
mode(p)=uniq   REFS(root(p))=∅   b fresh
────────────────────────────────────────────────────────────
⟨freeze p, S⟩ →
  ⟨val(b), S[mode(p):=frozen, B+=(b,frozen,p,ρ_scope), REFS(root)+=b, τ+=(Freeze,…)]⟩
```

`ρ_scope` 是 `freeze` 点所在的作用域区域。`freeze` 是**单向**的（`00 §4.3` 决策 D5）；返回的 `val(b)` 是 owner 句柄，
`recover` 时作为 `CONSUMED` 的一员被消费。`val` 的**复制**不另立规则，
由 S4 的 frozen 分支产生新的 `b`（因此 `recover` 能计数）。`thaw` 不存在（`00 §4.3` 已删除）。

#### S9 · Recover

```text
e →* val(b_owner)      p = target(b_owner)      mode(p)=frozen
LIVE_ALIASES(p) ⊆ CONSUMED(e)
──────────────────────────────────────────────────────────
⟨recover { e }, S⟩ →
  ⟨Loc root(p), S[mode(p):=uniq, REFS(root):=∅, B-=LIVE_ALIASES(p), τ+=(Recover,…)]⟩
```

未消费别名 ⇒ 静态 `E-LS-UNIQ`；跨函数/跨域 `recover` 直接拒绝（`H-LS-15`）。
`CONSUMED(e)` 是块内静态消费的 `val`/`ref` 句柄集合，按线性检查。
S9/S11/S13/S17 中的 `→*` 是块边界的闭包缩写；块内仍由 S1–S18 小步执行。

#### S10 · Alloc

```text
a : Alloc[ρ]   CAP_ALLOC_OK   l fresh   dom = 当前域
────────────────────────────────────────────────────────────
⟨alloc(a, v), S⟩ →
  ⟨Loc l, S[σ[l]:=v, β(l):=(uniq,∅,live), Δ(ρ)+=l, D(l):=dom]⟩
```

`alloc` 产生 `uniq` 根（`box` 的语义）；`kernel` 下 `Cap[Alloc]` 必须显式；
`agent` 下 `heap_allocator()` 提供 `Alloc[Heap]`。`iso` 只能位于 `heap`（`spec/modes.md` §1）。

#### S11 · RegionExit

```text
e →* v      Δ*(R)={l₁..lₙ}（分配序）
∀l∈Δ*(R): REFS(l)=∅      ¬REFERS_TO(v, R)
────────────────────────────────────────────────────────────
⟨region R { v }, S⟩ → ⟨v, Free(S, lₙ..l₁, R)⟩
```

`Free` 按**全局分配序号逆序**释放子区域与根位置（同 `00 §6.6`），置 `σ=⊥`、`β.st:=dead`、
`Δ(R):=∅`，并删除所有指向这些位置的 `B` 条目。`REFERS_TO(v,R)` 或 `REFS(l)≠∅` ⇒ 静态 R4 本应拒绝；
动态上粘滞（UB-2 的兜底）。

#### S12 · Drop

```text
mode(p) ∈ {uniq, iso}   REFS(root(p))=∅   LIVE(root(p))
────────────────────────────────────────────────────────────
⟨drop p, S⟩ → ⟨(), DropVal(S, p)⟩
```

`DropVal` 按字段声明顺序递归（`00 §6.6`），然后释放根位置。
`kernel` 下隐式 `Drop` 禁止（`E-LS-DROP`），显式 `release` 走同一规则。
重复 `drop` 因 `LIVE` 失败而粘滞；静态对应 `E-LS-DROP`（UB-3）。

#### S13 · Call

```text
f = fn(x⃗:T⃗)→T eff(E) { e_f }      v⃗ 是值
solve(C_f ∪ C_call)=σ_r           CAPS(f) 成立
F=(γ[x⃗↦v⃗], ret, locals, local(call))
────────────────────────────────────────────────────────────
⟨f(v⃗), S⟩ → ⟨e_f, push(S,F)⟩
```

参数按 mode 复制/移动（`F` 保存新 `γ`）；`C_call` 把实参区域与形参区域变量关联；
`CAPS(f)` 是 gate matrix 的 cap/effect 前提（`00 §6.2`）；`push` 保存调用者 `γ` 并安装 `F.γ`。
求解失败 ⇒ `E-LS-ESCAPE`/`E-LS-REGION-ESCAPE`。函数级完成，不做全程序不动点（ADR-8）。

#### S14 · Return

```text
κ=F·κ'      v 是值      ¬REFERS_TO(v, F.ρ)
────────────────────────────────────────────────────────────
⟨return v, S⟩ → ⟨v, PopDrop(S,F)⟩
```

`PopDrop` 按声明逆序析构帧内局部（S12），弹出帧，恢复调用者的 `γ` 与返回槽。
返回引用逃出帧区域 ⇒ 静态 R4 拒绝；动态上 `REFERS_TO` 兜底。

#### S15 · Spawn

```text
mode(v) ∈ {iso, atom, val}
mode(v)=iso ⇒ REFS(root(v))=∅
CAP_SPAWN（kernel）      d' fresh      mode(v)=iso ⇒ D(l):=d'
────────────────────────────────────────────────────────────
⟨spawn(f, v), S⟩ → ⟨handle(d'), S'⟩   ∧   thread(d') = ⟨f(v), S''⟩
```

`box`/`ref` 跨域 ⇒ 静态 `E-LS-RACE`；`val`/`atom` 共享只读/同步，`iso` 转移唯一所有权。
`val` 跨域还要求 `thread ⊑ ρ(target)`（见 R8）：目标区域至少是线程级，否则目标可能先于目标域释放。
`transfer` 是 `spawn`/`iso` 的参数传递特例。

#### S16 · Atomic

```text
mode(p)=atom      op ∈ {load, store, rmw}      ord 合法
────────────────────────────────────────────────────────────
⟨atomic(ord, op, p, v), S⟩ →
  ⟨v', S[τ+=(ord-kind, DOM(p), p, v')]⟩
```

`Acquire`/`Release`/`AcqRel`/`SeqCst` 产生 §4.3 的同步边；非原子访问 `atom` 且无锁
⇒ 静态 `E-LS-RACE`；锁 rank 违反 ⇒ `E-LS-IRQ`。

surface 只写方法形式 `p.op(a⃗)`（`00 §5.7`），经 `elaboration.md` E-21 降到这里；
`op`/`ord` 的合法组合由 `effects.md` §2.1 的 `atomicOps` 封闭表给出，不在 S16 内重复。
`atomicOp(E)` 是 R6 的**静态前提**（redex 形态），不是语法上下文包装。

#### S17 · Unsafe

```text
γ(u)=cap(Unsafe)      v 是值
────────────────────────────────────────────────────────────
⟨unsafe { v }, S⟩ →
  ⟨v, S[γ-=u, τ+=(Audit, site, obligations)]⟩
```

S17 只刻画**边界退出**：块内仍由 S1–S18 在上下文 `unsafe { □ }` 中小步执行；
`Cap[Unsafe]` 是**线性值**，退出时从 `γ` 消费（`00 §4.6`），缺失 ⇒ `E-LS-CAP`。`site`/`obligations` 是审计记录字段（块位置与证明义务清单）。
块内 `Hw`/`Asm`/`Ffi`/`Dma` 效果必须显式（`E-LS-EFFECT`）；审计条目进 `ls audit`。

#### S18 · Raw

```text
UNSAFE_CTX(E)      r=raw(l,o)      W(l,o,T)
────────────────────────────────────────────────────────────
⟨E[deref_raw r], S⟩ → ⟨E[σ[l,o]], S[τ+=(R, DOM(l), (l,o), ·)]⟩
```

`W(l,o,T)` = 对齐 ∧ `0 ≤ o < size(l,T)` ∧ `LIVE(l)` ∧ provenance 标签有效。
`W` 失败是 **UB**（UB-8/9/10），不是 trap；因为只有 `unsafe` 可达，由契约与审计承担（`H-LS-4`）。

### 3.4 粘滞与 UB

```text
FINAL(e,S) ⇔ e ∈ {v, abort(k)} ∧ κ(S) 中没有待弹出的 Borrow 帧
UB(e,S)    ⇔ ¬∃e',S'. ⟨e,S⟩ → ⟨e',S'⟩ ∧ ¬FINAL(e,S)
```

`FINAL` 必须在**配置**上判定，而不只看项：S6 进入借用后项是块体 `e`，
即使 `e` 是值，也要先由 S7 弹出 `Borrow` 帧才算结束。

**abort 传播（结构规则，不计入 18 条）**：`abort` 是定义行为，必须在任意上下文里
继续传播，否则 `recover { abort }` 会被 `UB` 误判为 stuck：

```text
E[abort(k)]                      → abort(k)
recover { abort(k) }             → abort(k)
region R { abort(k) }            → abort(k)
return abort(k)                  → abort(k)
borrow mut p as x { abort(k) }   → abort(k)
```

`E` 的定义（§3.1）不含块形式，所以块/借用单独列出；S-Abort 不引入新的 UB。

**静态错误 ≠ UB**：未通过检查的程序被拒绝，不进入 `UB` 的定义域。
`UB` 只用于「已接受程序」的运行时兜底，以及 `unsafe` 契约失败。

### 3.5 确定性（L3）

`δ` 是全函数（在定义域内）；`E` 唯一确定下一个 redex（最左最外）；fresh location 取
`next(S)` 的规范顺序；除 `spawn` 的线程交错外，`→` 对给定 `S` 至多一个结果，
且结果对位置重命名 `α`-等价。故**单线程片段**的 `→` 是确定性的；
多线程的交错由 §4.3 的 `hb` 约束，不改变单步关系的确定性。

---

## 4. 内存模型公理

### 4.1 公理

| # | 公理 | 说明 |
|---|---|---|
| A1 | 程序序 | 同一域内的事件按 `τ` 顺序发生 |
| A2 | 域 | `Domain = Thread | Irq(k) | Dma`；`D(l)` 除 `iso` 转移外不变 |
| A3 | HB | `hb = (po ∪ so ∪ jo ∪ sync)⁺`；`po` 程序序，`so` spawn 边，`jo` join 边，`sync` 来自 release/acquire 与锁 |
| A4 | 数据竞争 | 两个事件不同域、同 place、至少一个写、非 `hb` 有序、且非两者原子 ⇒ race |
| A5 | Provenance | `raw(l,o)` 携带 `(a, tag)`；访问必须满足 RTT v1（`spec/ub.md` §2.4） |
| A6 | 初始化 | `read(p)=⊥` 在安全检查下 ⇒ `E-LS-INIT`；`unsafe` 下 ⇒ UB-4 |
| A7 | MMIO | `M` 与 `σ` 分离；MMIO 每次访问都是可观测事件，不消除/不合并/不重排；仅 `fence` 排序 |
| A8 | 求值序 | 从左到右、实参先于调用（UB-12）；δ 在定义域内全函数 |
| A9 | Trap | 边界/除零/移位/checked 溢出 ⇒ `abort(k)`，是**定义行为**（UB-7） |
| A10 | Freeze/Recover | `Freeze` 是 release-like，`Recover` 是 acquire-like；两者之间禁止写（R3/R5） |

### 4.2 HB 与竞争

`hb` 是严格偏序；`race(a₁,a₂)` 按 A4 定义。安全子集的承诺是
「`F_thr` 片段内无 `race`」（T2），不是「所有程序无 race」。
中断域 `Irq(k)` 与 DMA 域不在 T2 内，登记为 `H-LS-16`。

### 4.3 Provenance（RTT v1，Q5 已关闭）

> 规范定义在 `spec/ub.md` §2（决策 D41 / 2026-10-18）。本节只给运行时接口，不重复 tag 状态表。

- 指针值 = `(a, off, tag)`；`tag ∈ T(a)`，状态 `act / res / froz / dis`；
- 安全子集的 `ref`/`val` 派生由 R1–R8 静态检查；RTT 在编译期擦除，不增加安全子集运行时成本；
- `unsafe` 的 `raw` 访问由 `W(l,o,T)` 检查 RTT v1 的 `Access`（`spec/ub.md` §2.4）+ `Witness`；
- 越界/跨分配/禁用 tag/写 `froz`/无 `Witness` 的 raw 冲突 ⇒ UB-10；
- RTT v1 是 Tree Borrows 的**保守子集**；包含关系未机械化证明（S5）；
  `H-LS-4`（`unsafe` 深层 soundness）仍为 `Out-of-scope`。

### 4.4 MMIO / volatile

`Mmio[T]` 不在 `σ` 中，而在 `M : MmioAddr ⇀ Word`；每次 `read`/`write` 生成 `Hw` 事件；
`fence(Order)` 是唯一的排序手段（UB-11）。`Mmio[T]` 是 affine，不能 Copy（`00 §4.7`）。

### 4.5 Trap

`abort(k)` 是程序终点；`kernel` 下 `abort` 触发故障处理，`agent` 下进程终止。
`panic` 也走 `abort`，不 unwind（`00 §6.6`，`H-LS-19`）。

---

## 5. 元理论

> **通用前提**：`WF(S)`、静态检查通过、`→` 按 §3。所有定理只对**已接受程序**陈述。

### 5.1 T1 · 逃逸 soundness

> 静态部分由 T1a（§2.7）承担：`solve` 成功 ⇒ 所有引用/存储约束成立。
> 本节把 T1a 提升到运行时，仍依赖 `WF(S)` 与 L4。

**陈述**：若 `Σ;ρ ⊢ e : T@m ▷ C`、`solve(C)=Ok(σ)` 且 `⟨e,S⟩ →* ⟨v,S'⟩`，则 `REACH(v)` 中每个活引用 `b`
满足 `ρ_s(b) ⊑ ρ(target(b))`，且 `target(b)` 未 `dead`。

**证明草稿**（对 `→` 归纳）：

- S6：新借用满足 `ρ_s ⊑ ρ(p)`，I4 成立；
- S7：`ref(b) ∉ REACH(v)`，借用不随结果逃出；
- S13：调用点的 `C_call` 由 `solve` 求解，L1 保证实参区域满足形参约束；
- S14：`¬REFERS_TO(v,F.ρ)`，返回值不引用帧区域；
- S11：`¬REFERS_TO(v,R)` 且 `REFS(l)=∅`，区域释放后无悬挂；
- 其余规则不引入新的跨区域引用。

**缺口**：帧区域的簿记、过程间区域多态、递归（`H-LS-29`）未纳入；当前只对无递归片段成立。

### 5.2 T2 · 别名与线程域

**陈述**：在片段 `F_thr`（thread fragment：无 `unsafe`/`rawptr`/`Ffi`/`Asm`/`Irq`/`Dma`；跨域仅 `iso`/`atom`；
`atom` 仅经 `atomic`/锁）中，若 `P` 良类型且 `WF(S)`，则 `τ` 中不存在 A4 意义下的数据竞争。

**证明草稿**：

1. **L4（不变量保持）**：S1–S18 逐条检查 I1–I6。已纸面复核 S5、S6、S7、S15、S16；
   S1/S2 不触及 I1–I6；S3、S4、S8、S9、S10、S11、S12、S13、S14、S17、S18 待逐条复核（见 §5.5）。
2. S5 的 `WRITABLE` 排除同区域活 `frozen`/`mut` 别名；S6 的 `REFS=∅` 保证 `uniq` 借出唯一。
3. 跨域只发生在 S15（`iso` 转移或 `val`/`atom` 共享）与 S16（原子/锁）；
   S15 的 `iso` 转移要求 `REFS=∅`，转移后 `D(l)` 单域；S16 产生 `sync` 边。
4. 由 1–3，任意两个不同域的访问要么被 `hb` 排序（S16/锁/spawn-join），要么不重叠；
   故无 A4 race。

**缺口**：锁 rank 的传递证明、`cell` 的别名边界（`M-3`）、`Irq`/`Dma`（`H-LS-16`）、
`H-LS-3` 仍为 Protocol。T2 **不**覆盖中断域。

### 5.3 T3 · `recover` 唯一性

**陈述**：若 `recover { e }` 通过静态检查，则执行后 `p` 的唯一性恢复：
`REFS(root(p))=∅`，且不存在其他活 `val`/`ref` 别名。

**证明草稿**（2026-10-18 按 `H` 规则重写）：

1. 静态前提现在是 `Aliases*(Σ_c,p)=∅`：按**别名出现位置** `(q,b)` 清空，
   不只清 `Λ` 里的 `b`；`ConsumeResult` 已把块结果按隐式 move 处理；
2. 每个 `val` 别名由 S8/S4 创建并登记到 `B`；每个 `ref` 由 S6 创建并登记；
   静态侧对应 `Λ += (b,place,m,ρ)`，`H(q):=A` 在绑定/存储处写回；
3. I7/I8 给出 `Λ` 与 `H` 的双向对应：每个活 `b` 都有 holder，每个 holder 的 `b` 都活；
4. 块内没有规则能在不登记的情况下创建指向 `p` 的别名（S1–S18 枚举）；
   `R4-store`/`R7-write` 的写回会使旧 `(q,b)` 离开 `Consumed*` 或保持 holder；
5. S9 在前提成立时清空 `REFS` 并删除 `LIVE_ALIASES`，恢复 `uniq`。

**缺口**：`shared`/`cell` 不在片段内；跨函数 `recover` 已静态拒绝（`H-LS-15`）；
静态规则到动态 `B/CONSUMED` 的 `L-Adequacy` 已在 `t4-proof.md` §3.5/§3.6 对
M2 全部规则给出纸面证明（S10/S11 条件、S12 仅 uniq）；M2 Preservation/L4 与 M3 仍未证。
运行期 `rc==1` 是 `H-LS-15` 的备选，不在本证明内。

### 5.4 T4 · 安全子集无 UB（**T4a 纸面证明**）

> 执行报告：[`t4-proof.md`](t4-proof.md)。M0/M1/M2/M3 核心与
> **L-Term/L-Block/L-Progress/L-NoStuck** 已写出（2026-10-19，`t4-proof.md` 的 L-Term/L-Block 小节）；
> T1a-mono + `Rgn*` 收口；S10 依赖 `CAP_ALLOC_OK`、S13 依赖 `CAPS(f)`。
> **T4a 在 F0 上成立并已机器检查**（`lean/LSys/T4a.lean`）；T4b–T4e 仍是显式假设/扩展。
> 机械化边界（place 为不透明 id、`Step` 全语法、UB 映射范围）见 `lean/README.md`。

**先说结论**：T4 **不能作为一个单一命题直接证**。它混合了四类完全不同的义务：

1. **语言语义**（progress/preservation、region/ownership/init）；
2. **编译器正确性**（MMIO 不被优化/重排、trap/溢出代码生成）；
3. **平台/ABI**（栈上界、FFI unwind）；
4. **信任闭包**（`Trusted(q)` 的外部假设）。

把这四类写成一个定理，证明会失败在边界上；正确做法是先拆分，再逐个机械化。

#### 5.4.1 拆成五个可证命题

| 命题 | 片段 | 要排除的 UB | 证明手段 |
|---|---|---|---|
| **T4a** 核心 | `F0` | UB-1…UB-5、UB-8…UB-10、UB-12、UB-14 | progress + preservation + T1/T3 |
| **T4b** MMIO | `F0 + Mmio/Hw` | UB-11、UB-6/7 的代码生成 | 后端/volatile 模型或明确信任 |
| **T4c** FFI | `F0 + Ffi` | UB-15 | ABI/nounwind + `H-LS-5` 假设 |
| **T4d** 栈 | `F0 + 递归` | UB-13 | 静态栈上界（`H-LS-29`）/profile |
| **T4e** 信任/并发 | `Trusted`、线程、`Irq`、`Dma` | UB-5、H-LS-16 | T2 + Iris；`H-LS-3`/`H-LS-16` |

`F0` 的权威定义见 [`f0.md`](f0.md)（单线程；无 spawn/Irq/Dma/shared/atom/cell/static、
无 unsafe/rawptr/Ffi/Asm、无递归、无 Mmio/Hw、无 comptime、无泛型单态化/区域多态/
动态分派/跨模块，`Trusted = ∅`）。本文不复制该定义。

`F0` 之外每一项都是**扩展**，不是 T4a 的前提。扩大 `F0` 必须新增一条对应引理，
不能默默把 `Mmio`、`cell`、`Trusted` 塞进“安全子集”。

**T4a 的目标陈述（修正版）**：

```text
若 P ∈ F0、Safe(P)、静态检查通过且 solve(C)=Ok，
则 P 不触发「未定义行为」；
UB-1 的越界、UB-6 的溢出回绕、UB-7 的 abort 是定义行为（trap），不计入未定义。
```

原先把 UB-6/UB-7 也写成“不得触发”，是把**定义行为**和**未定义行为**混在一起；
证明前必须先改口径，否则定理字面为假（一个除零程序会触发 UB-7，但它只是 abort）。

#### 5.4.2 核心证明骨架（T4a）

需要四个对象：

```text
WT(S, e)   运行时配置 S 与表达式 e 的「配置类型正确」
            = CT(S, Σ) ∧ Σ;ρ ⊢ e : T @ m ▷ C ∧ solve(C)=Ok

CT(S, Σ)   配置类型：γ/σ/β/B/Δ/κ 与 Γ/Λ/M 一致，且 I1–I6 成立
Step        18 条小步规则
UB(e,S)     ¬∃ step ∧ e ∉ FINAL（FINAL = value | abort）
```

`CT` 必须逐项绑定：

| 运行时 | 静态 | 要求 |
|---|---|---|
| `γ(x)=v` | `Γ(x)=(T,m,ρ_x)` | `v` 有类型 `T`、模式 `m`，`x∉M` |
| `σ[l]` | 类型/区域表 | 值类型匹配；`⊥` 只对应未初始化槽 |
| `β(l)`/`B(b)` | `Λ` | `B(b)` 的 target/模式/区域与 `Λ` 一致；`mut` 唯一 |
| `Δ(R)` | 区域树 | 分配集合嵌套；释放顺序正确 |
| `κ` | 函数签名 | 帧的局部/返回槽/区域与签名一致 |
| `M` | moved 集 | `x∈M` 当且仅当 `γ(x)` 已失效 |

四条引理：

- **L-Adequacy（静态充分性）**：若 `WT(S,e)` 且 `e` 是某个 S 规则的 redex，
  则该规则的动态前提成立（`INIT`、`LIVE`、`uniqOk`、`writable`、`solve` 等）。
  证明：对 `Σ;ρ ⊢ e` 的推导做逆推；这是**静态语义与动态语义的桥**。
- **L-Preservation**：`WT(S,e)` 且 `⟨e,S⟩ → ⟨e',S'⟩` ⇒ `WT(S',e')`。
  证明：对 18 条规则逐例；每例用 L-Adequacy 与 I1–I6。
- **L-Progress**：`WT(S,e)` ⇒ `e ∈ FINAL` 或 `∃e',S'. ⟨e,S⟩ → ⟨e',S'⟩`。
  证明：对 `e` 的结构分类；若某条规则的前提不成立，用 L-Adequacy 推出与类型/约束矛盾。
- **L-NoStuck**：`WT(S,e)` ⇒ `¬UB(e,S)`。由 L-Progress 与 `UB` 定义直接得到。

**T4a = L-NoStuck + T1（无悬垂）+ T3（`recover` 唯一性）+ UB 映射**。
`L-NoStuck` 只排除“卡住”；UB-2/UB-3 还需要 `WF`/T1/T3 的“无悬垂、无重复释放”。
它不是“所有程序都成功”，而是“不会卡在未定义状态”；`abort(Bounds/Div/Overflow)` 是 `FINAL`，允许发生。

#### 5.4.3 UB 映射（F0）

| UB | 在 F0 中的处置 |
|---|---|
| UB-1 越界 | S4/S5 的 `BOUNDS` → `abort(Bounds)`（定义行为）；静态越界被拒 |
| UB-2 悬垂 | T1a（静态无逃逸）+ T1（运行时 WF/I6） |
| UB-3 double free | S12 的 `LIVE` + 静态 `E-LS-DROP`；线性所有权 |
| UB-4 未初始化 | S4 的 `INIT` + 静态 `E-LS-INIT` |
| UB-5 数据竞争 | `F0` 单线程；**vacuous**（没有两个域） |
| UB-6 溢出 | wrapping 是定义行为，不是 UB |
| UB-7 除零/移位 | `abort` 是定义行为，不是 UB |
| UB-8/9/10 | `F0` 无 `rawptr`/`unsafe`；**vacuous**（T4b/`H-LS-4` 之外） |
| UB-11 MMIO | `F0` 无 `Mmio/Hw`；**T4b** |
| UB-12 求值序 | S1 的 `E` 左到右；`δ` 确定 |
| UB-13 栈 | `F0` 无递归；**T4d** |
| UB-14 drop 中使用 | S12 + A9（`abort`，无 unwind） |
| UB-15 FFI unwind | `F0` 无 FFI；**T4c** |

“vacuous”不是“已证明”：它依赖 `F0` 的语法限制与类型系统禁止这些构造。
若实现允许 `F0` 之外的构造，必须转入对应扩展命题。

#### 5.4.4 难点（按风险排序）

1. **L-Adequacy**：静态判断是流敏感的（`Λ`、`M`、`H`、`Consumed*`），而动态配置是显式的
   `β/B/γ`；两者的对应关系是整条证明最容易被反例击穿的地方。
   `H` 已按出现位置补上，但 `H ⇔ B` 的双向模拟、`recover` 的 `ConsumeResult`、
   `call` 的形参别名继承、`region` 的 `REFERS_TO` 仍需逐例证明。
2. **调用/帧/区域多态**：`C_call` 的方向、帧区域、retag、返回引用的区域约束；
   当前 T1a 只覆盖静态逃逸，运行时 T1 仍需补齐。
3. **`recover` 唯一性**：T3 的别名登记必须与 `CT` 的 `Λ` 双向对应；否则
   “块内消费”可能漏掉一个动态别名。
4. **`drop`/region exit 的顺序**：`WF` 的 I5/I6 要证明 `Free`/`PopDrop` 保持；
   否则 UB-2/UB-3 的运行时兜底不成立。
5. **编译器/后端**：UB-11 不是操作语义能证明的；必须建 volatile 模型或
   把“后端不重排 MMIO”作为显式信任（T4b）。
6. **平台/FFI/Trusted**：UB-13/UB-15 与 `Trusted(q)` 是**假设**，不是语言内核定理；
   写成 T4d/T4c/T4e，并在 `H-LS-*` 明确级别。
7. **反例优先**：若 `F0` 内找到 stuck 程序，说明静态规则不完备或不 sound；
   必须修规则（或缩小 `F0`），不能把反例写进“已知限制”了事。

#### 5.4.5 机械化路线

| 阶段 | 内容 | 工具 |
|---|---|---|
| M0 | 纯表达式 + let/if/while；`WT`/`Step`/`UB` 框架 | Lean 4 |
| M1 | Array/Slice/边界/初始化 | Lean 4 |
| M2 | region/borrow/freeze/recover；T1a/T1/T3 | Lean 4 |
| M3 | call/return/frame/drop；L-Preservation | Lean 4 |
| M4 | 与参考解释器差分；conformance 反例 | Rust + CI |
| M5 | T4b/T4c/T4d/T4e 扩展；线程用 Iris | Lean 4 / Iris |

**验收不是“跑通测试”**：机械化必须给出 `T4a` 的定理陈述与无 `sorry` 的证明，
或者明确降级为 `H-LS-4`/`H-LS-16` 的假设。测试只能找反例，不能证明 T4。

#### 5.4.6 证明失败时怎么办

- 找到 stuck 反例 ⇒ 修静态规则/动态规则，或缩小 `F0`；
- `L-Adequacy` 无法证 ⇒ 检查是否漏了 `Λ`/`M`/`Consumed` 的流敏感规则；
- 只有 `Mmio`/FFI/栈/Trusted 失败 ⇒ 不是 T4a 失败，落到 T4b–T4e 的显式假设；
- 不要用“安全子集不含 unsafe”替代证明：`F0` 内仍要证 progress。

### 5.5 证明状态与缺口

| 定理/引理 | 片段 | 状态 | 缺口 |
|---|---|---|---|
| L1/L2 | 约束求解 | 纸面证明 | 原型与属性测试待做 |
| L3 | 单线程 | 纸面证明 | 多线程交错未形式化 |
| L4 | S1–S18 | **M2+M3 核心（S1–S14）** | S15–S18 在 F0 外；S10/S11/S12/S14 条件 |
| T1a | 安全子集 / 无 unsafe | **纸面证明（T1a-mono + `Rgn*`）** | 区域多态不在 F0；无残余字段缺口 |
| T1 | 无递归 | 草稿 | 帧区域、过程间多态 |
| T2 | `F_thr` | 草稿 | 锁 rank、`cell`、`H-LS-16` |
| T3 | 单函数 | 草稿（`H` 规则已补） | `H ⇔ B` 的 L-Adequacy、`shared`/`cell`、`H-LS-15` |
| T4 | 拆分 T4a–T4e | **T4a 纸面证明** | T4a = L-NoStuck + T1 + T3 + UB 映射；条件 `CAP_ALLOC_OK`/`CAPS(f)`；T4b–e 假设 |

---

## 6. UB 覆盖映射

| UB | 由什么阻止 | 状态 |
|---|---|---|
| UB-1 越界 | S4/S5 的 `BOUNDS` + `abort(Bounds)`（定义行为） | 覆盖 |
| UB-2 悬垂 | S7/S11/S14 + T1 | 草稿 |
| UB-3 double free | S12 的 `LIVE` + 静态 `E-LS-DROP` | 草稿 |
| UB-4 未初始化 | S4 的 `INIT` + `E-LS-INIT` | 覆盖 |
| UB-5 数据竞争 | S5/S6/S15/S16 + T2 | 草稿（仅 `F_thr`） |
| UB-6 整数溢出 | δ 的 wrapping（定义行为） | 覆盖 |
| UB-7 除零/移位 | δ 的 `abort`（定义行为） | 覆盖 |
| UB-8 null/野指针 | S18 的 `W`（RTT v1 + `LIVE` + 界内） | 草稿（RTT v1） |
| UB-9 未对齐 | S18 的 `W`（RTT v1 + `aligned`） | 草稿（RTT v1） |
| UB-10 provenance | A5 + S18 的 `W`（RTT v1） | **已定义（D41）** |
| UB-11 MMIO 重排 | A7 + `Mmio[T]` affine | 草稿 |
| UB-12 求值序 | A8 + `E` 的左到右 | 覆盖 |
| UB-13 栈溢出 | 不在 L-Sys₀；`spec/baremetal.md` + `H-LS-29` | 缺口 |
| UB-14 drop 中使用 | S12 + A9（`abort`，无 unwind） | 草稿 |
| UB-15 跨 FFI unwind | 不在 L-Sys₀；`extern "C"` nounwind（`H-LS-4`） | 缺口 |

---

## 7. 验证与实现

### 7.1 参考解释器

在 `tools/checker-spike`（Rust）中实现 S1–S18，作为**语义 oracle**：

- 输入：`dossiers/**/*.ls` 的核心子集；
- 输出：`accept` / `reject(<code>)` / `trace`（`τ` 与 `WF` 检查）；
- 每个规则一个手写用例，先跑负例（`04` §6「反例优先」）。

### 7.2 conformance 生成

每条规则至少一对：

```text
tests/conformance/accept/S<nn>-<name>.ls
tests/conformance/reject/<code>-<name>.ls     (* 首行 // EXPECT: <code> *)
```

当前 `accept/`、`reject/` 为空（`tests/conformance/README.md` 自述）；S-1 的目标是
S2–S18 各一对（S1 由 δ 表覆盖）+ R1–R8 各一对，负例总数 ≥ 20。**未填满前不得声称「规则已验收」**。

### 7.3 B-LS 差分

B-LS 的可执行语义是 `seed` 解释器（`spec/bls.md`）。验证方式：

1. `seed --run` 与编译产物对同一 B-LS 程序做差分测试；
2. `stage2 == stage3` 作为**确定性**证据，不作为 soundness 证据；
3. L-Sys₀ 与 B-LS 的重叠子集（`let`/`if`/`while`/函数/数组）做规则一致性抽检。

### 7.4 机械化路线

| 阶段 | 目标 | 工具 |
|---|---|---|
| S0′ | L1/L2 的可执行原型（union-find + 属性测试） | Rust |
| S3 | T2 的 race 反例搜索（小步模型） | Rust / Loom 风格 |
| S5 | T1–T3 机械化；T4 的片段 PCC | Lean 4 / Coq / Iris |

若 S5 无法机械化，必须在 `H-LS-*` 明确降级，不得保留「已形式化」措辞。

---

## 8. 未决问题

| # | 问题 | 影响 | 归属 |
|---|---|---|---|
| S5 | RTT v1 与 Tree Borrows 的包含关系/机械化 | UB-10、T4 | S5 |
| H-LS-16 | 中断/DMA 域规则 | T2 扩展 | S3 |
| H-LS-3 | 线程定理的 Enforced 级别 | T2 承诺 | S3 |
| M-3 | `cell` 与 `val` 的别名边界 | T2/T3 | W3 |
| M-4 | `H` 的粒度（root/字段）与父 place 同步、增量缓存、出现位置去重 | `ls-sem` 性能、L-Adequacy | W2–W3 |
| H-LS-29 | 有界递归的栈上界 | T1 片段 | 档案 B |
| — | `comptime` 的求值与 fuel | 不在 L-Sys₀ | S-1 支撑 |
| — | FFI/ABI 的形式化 | UB-15 | `spec/baremetal.md` |
| — | `defer`/`#[must_release]` 的线性语义 | UB-14 | `spec/resource.md` |

---

## 9. 冻结条件

- [ ] S2–S18 每条有正例/负例（S1 由 δ 表覆盖），`tests/conformance` 非空且零漏过；
- [ ] R1–R8 每条至少一正一负；诊断码覆盖与 [`diagnostics.md`](diagnostics.md) 的映射表逐行一致；
- [ ] L1/L2 有可执行原型 + 属性测试；不可满足核（core）有 1 个可复现样例；
- [ ] T1a/T1–T3 的证明草稿经双人评审（solo 模式为作者 + 外部评审）；
- [x] 静态判断带输出 `⊣ Σ'`，`R1/R3/R4/R5` 写回 `H`（2026-10-18，ADR-31 方案 B 草稿）；
- [x] `t4-proof.md` M2 的 L-Adequacy/Preservation/L4 与 M3 核心已写出（2026-10-18，`t4-proof.md` 的 M2/M3 章节；S10/S11/S12/S14 条件）；
- [ ] 求解器原型用同一 `C` 生成器复现 T1a 的前提（R2/R4/R8 约束逐条可追）；
- [~] L4 的 18 例逐条复核：M2+M3 核心 S1–S14 已写出；S10/S11/S14 条件，S12 已收口；S15–S18 在 F0 外；
- [ ] M3 完整（泛型/区域多态/递归/动态分派/跨模块）与 Progress/`L-NoStuck`；
- [ ] R5/R6/R8 的正负例（见 [`results/S1-semantic-freeze.md`](../results/S1-semantic-freeze.md)）；
- [ ] RTT v1 的 §4.3 接口与 `spec/ub.md` §2 逐行一致；UB-10 有可执行 oracle；
- [ ] T4 仍未证明时，对外材料不得声称「安全子集无 UB」；
- [ ] `python tools/doc-lint --strict` 全绿。

> **冻结状态（2026-10-18）**：`Σ'`/M2/M3 核心已写出，但 R5/R6/R8 正负例、Progress/`L-NoStuck`、
> M3 完整未完成 ⇒ **语义冻结门未通过**；详见 [`results/S1-semantic-freeze.md`](../results/S1-semantic-freeze.md)。

---

## 10. 变更规则

- 新增/删除小步规则 ⇒ 必须走 `02` 的 ADR，并同步 `00 §4.8` 与 `spec/ub.md`；
- 新增 UB ⇒ 先改 `00 §8.1`，再改本文件与 `spec/ub.md`（三处逐行一致）；
- 规则的语义变更（例如 `freeze` 可逆、`recover` 跨函数）⇒ 触发 `H-LS-15` 重估，
  不得以「实现方便」为由静默修改；
- 本文件是**可执行规范的基线**，不是「已形式化」的证明：状态升级到 `冻结` 前，
  必须满足 §9 的全部条件。
