# spec/t4-proof.md · T4a 执行报告（M0/M1 完成，M2/M3 核心写出）

> **状态**：`草稿 · 执行中`。M0/M1 有纸面证明；M2 的 L-Adequacy/Preservation/L4
> 与 M3 的 call/return/frame/drop 核心已写出（S10/S11 条件、S12 仅 uniq）；
> 完整 M3、Progress/`L-NoStuck`、M4/M5 未完成，T4a **仍未证明**。
> **上位**：[`semantics.md` §5.4](semantics.md)（T4 拆分与路线）、
> [`semantics.md` §2](semantics.md)（静态规则）、[`ub.md`](ub.md)（UB-10 / RTT v1）。
> **性质**：纸面证明 + 证明义务审计；**L3 F0 核心已机器检查**（Lean 4.6.0，2026-10-20，见 §5 与 `lean/README.md`）。
> **纪律**：本文件不把“跑了测试”写成“证明了 T4a”；失败的反例与缺口必须保留。

---

## 0. 执行结论

| 项 | 结果 |
|---|---|
| M0（纯表达式 + let/if/while） | **完成**：L-Adequacy / L-Preservation / L-Progress 全部写出 |
| M1（Array/Slice + 边界 + 初始化） | **完成**：新增 `BOUNDS` 走 `abort(Bounds)`，不产生 UB |
| M2（region/borrow/freeze/recover） | **完成（条件）**：L-Adequacy §3.5/§3.6；Preservation/L4 §3.7；S10/S11 条件，S12 仅 uniq |
| M3（call/return/frame/drop） | **核心完成（条件）**：§3.8；完整 M3（泛型/递归/动态分派/跨模块）未做 |
| T4a | **未证明**（`bad()` 已拒；Progress/`L-NoStuck`、完整 M3、M4/M5 未完成） |
| 机械化 | **L3 F0 核心完成**（Term/State/Adequacy/Progress/Block/T4a；无 `sorryAx`） |

**本次修复的核心**：`semantics.md` §2 已把判断改为

```text
Σ; ρ ⊢ e : T @ m ▷ C ⊣ Σ' ; A        Σ = (Γ, Λ, M, H)
```

`H` 记录每个 place 的值内部持有的别名，`Aliases*`/`Consumed*` 按**别名出现位置**计。
因此 `recover { v }` 能看到聚合字段 `s.f` 里还有一个 `val` 副本；§3.2 的 `bad()`
不再有类型推导（`E-LS-UNIQ`）。

**仍然不能说 T4a 成立**：M2/M3 核心已写出，但 S10 依赖 `CAP_ALLOC_OK`、
S11/S14 依赖 T1a、S12 只覆盖 uniq；完整 M3、Progress/`L-NoStuck` 与 M4/M5 仍缺。

---

## 1. M0：纯表达式片段

### 1.1 语法与类型

```text
v ::= () | n | true | false
e ::= v | x | e₁ + e₂ | e₁ = e₂ | if e then e₁ else e₂
    | let x = e₁; e₂ | x := e | e₁; e₂ | abort

T ::= Unit | Int | Bool
Γ : Var ⇀ T          γ : Var ⇀ Val
```

静态规则（标准）：

```text
(Var)   Γ(x)=T
        ─────────
        Γ ⊢ x : T

(Int)   ─────────────      (Bool)  ─────────────────
        Γ ⊢ n : Int                Γ ⊢ true : Bool

(Add)   Γ ⊢ e₁:Int   Γ ⊢ e₂:Int
        ─────────────────────────
        Γ ⊢ e₁+e₂ : Int

(If)    Γ ⊢ e:Bool   Γ ⊢ e₁:T   Γ ⊢ e₂:T
        ─────────────────────────────────
        Γ ⊢ if e then e₁ else e₂ : T

(Let)   Γ ⊢ e₁:T   Γ[x↦T] ⊢ e₂:U
        ─────────────────────────
        Γ ⊢ let x=e₁; e₂ : U

(Assign) Γ(x)=T   Γ ⊢ e:T
         ─────────────────
         Γ ⊢ x:=e : Unit

(Seq)   Γ ⊢ e₁:T   Γ ⊢ e₂:U
        ────────────────────
        Γ ⊢ e₁;e₂ : U

(Abort) ─────────────
        Γ ⊢ abort : T
```

### 1.2 动态语义与 `WT`

```text
E ::= □ | E+e | v+E | E=e | v=E
    | if E then e₁ else e₂ | let x=E; e | E;e | x:=E

δ(n₁+n₂) = n₁+n₂ (mod 2⁶⁴)      δ(n₁=n₂) = (n₁=n₂)
δ(if true then e₁ else e₂) = e₁
δ(if false then e₁ else e₂) = e₂

⟨E[r], γ⟩ → ⟨E[δ(r)], γ⟩        (r 是 δ-redex)
⟨let x=v; e, γ⟩ → ⟨e, γ[x↦v]⟩
⟨x:=v, γ⟩ → ⟨(), γ[x↦v]⟩
```

`FINAL = v | abort`；`UB(e,γ) ⇔ ¬∃e',γ'. ⟨e,γ⟩→⟨e',γ'⟩ ∧ e ∉ FINAL`。

```text
WT(γ, e) ⇔ ∃Γ,T. (∀x∈dom Γ. γ(x) 有类型 Γ(x)) ∧ Γ ⊢ e : T
```

### 1.3 L-Adequacy（M0）

**引理**：若 `WT(γ,e)` 且 `e` 是某个动态规则的 redex，则该规则前提成立。

证明：对 `Γ ⊢ e : T` 逆推。

- `x`：`Γ(x)=T`，`WT` 给出 `γ(x)` 有类型 `T`，所以 `x` 是值；
- `n/true/false`：值；
- `e₁+e₂`：若两边都是值，`δ` 对 `Int` 全定义；
- `if`：条件为 `Bool` 值，`δ` 选分支；
- `let`/`:=`/`;`：redex 只在子表达式为值时触发，规则直接适用。

没有“静态接受但动态无规则”的 M0 情形。

### 1.4 L-Preservation（M0）

**引理**：`WT(γ,e)` 且 `⟨e,γ⟩→⟨e',γ'⟩` ⇒ `WT(γ',e')`。

证明：对 7 条规则逐例。

- `δ`：`δ` 保持类型（`Int+Int:Int`，`Int=Int:Bool`，`if` 分支同型）；
- `let`：`γ[x↦v]` 后 `x` 的类型是 `T`，其余变量不变；`e` 在 `Γ[x↦T]` 下类型正确；
- `:=`：`γ[x↦v]`，`v:T`，其余不变；
- `;`：丢弃第一段的值，第二段类型不变；
- 上下文规则：子表达式保持类型，上下文拼接保持类型。

### 1.5 L-Progress（M0）

**引理**：`WT(γ,e)` ⇒ `e ∈ FINAL` 或 `∃e',γ'. ⟨e,γ⟩→⟨e',γ'⟩`。

证明：对 `e` 归纳。

- 值/`abort`：`FINAL`；
- `x`：`WT` 保证 `x∈dom γ`，是值；
- `op(e₁,e₂)`：`e₁` 归纳；若 `e₁` 值，`e₂` 归纳；两边值后 `δ` 有定义；
- `if`：条件归纳；`Bool` 值后 `δ` 选分支；
- `let`/`:=`/`;`：子表达式归纳；值为值时规则触发；
- 不存在“所有子表达式都是值但没有规则”的情形，因为 M0 的 redex 覆盖了所有构造。

### 1.6 M0 的 T4a 片段

M0 没有内存、没有 UB-1…UB-15 的运行时构造；`UB` 只可能来自“卡住”，
而 L-Progress 排除了卡住。`abort` 是 `FINAL`，是定义行为。
所以 M0 的 T4a 成立：**well-typed M0 程序不会卡在未定义状态**。

---

## 2. M1：Array / 边界 / 初始化

在 M0 上加：

```text
T ::= … | Array[T, N]
v ::= … | array(v₀, …, v_{N-1})
e ::= … | e[i] | e[i] := e' | Array.zeroed()
```

静态：

```text
(Index)  Γ ⊢ e : Array[T,N]   Γ ⊢ i : Int
         ────────────────────────────────
         Γ ⊢ e[i] : T

(SetIdx) Γ ⊢ e : Array[T,N]   Γ ⊢ i : Int   Γ ⊢ e' : T
         ───────────────────────────────────────────────
         Γ ⊢ e[i] := e' : Unit
```

动态：

```text
i < 0 ∨ i ≥ N  ⇒  ⟨E[array(v⃗)[i]], γ⟩ → ⟨E[abort(Bounds)], γ⟩
0 ≤ i < N      ⇒  ⟨E[array(v⃗)[i]], γ⟩ → ⟨E[v_i], γ⟩
```

`abort(Bounds)` 是 `FINAL`，**不是 UB**（`ub.md` UB-1 的“定义行为”）。
`WT` 增加“数组长度与类型 `N` 一致”；L-Adequacy 的 `Index` 情形由 `WT` 给出
`N` 与运行时长度一致；L-Preservation 的值/数组更新保持类型；L-Progress 对索引
分两支：越界走 `abort`，界内取值/写值。

M1 的 T4a 成立：**越界只会 abort，不会卡住**；初始化由 `Array.zeroed()` 与
`let` 的“绑定即初始化”保证（M1 没有未初始化声明）。

---

## 3. M2 缺口与三例证明：`val` 别名进入聚合字段

### 3.1 需要的静态输出（已补）

要证 M2 的 `L-Adequacy`，`R3-read` 必须把新别名写回 `Σ`，`R1-move` 必须把
moved 写回 `Σ`，`R4-store` 必须把“目标 place 现在持有该别名”写回 `Σ`。
旧判断没有 `⊣ Σ'`，这些信息会在证明里丢失；2026-10-18 已按 §3.4 补入
`semantics.md`，下面的反例只作为“旧规则为何不成立”的记录。

### 3.2 反例骨架

```ls
struct S { f: val[Int] }

fn bad() {
    let mut x: Int = 1;
    let v: val[Int] = freeze x;      // R3-freeze：x 变 frozen
    let mut s: S = S { f: v };       // val 句柄进入聚合字段
    recover { v }                    // R3-recover：只看到 v，没看到 s.f
    x = 2;                           // R5-writable：Λ 里没有 s.f
    let y = s.f;                     // 读旧别名
}
```

在**旧规则**（“`val` 可别名”但没有 `H`）下：`S { f: v }` 复制句柄，`s.f` 是独立别名；
`recover { v }` 只消费 `v`，静态接受；动态 `S9` 的 `LIVE_ALIASES(x)` 仍含 `s.f`，
于是 `S9` 粘滞，或 `S5` 写 `x` 时与 `s.f` 冲突 ⇒ **静态接受、动态 UB**。
现行规则下该程序没有推导（§3.5.3 推论）。

在“`val` 仿射（核心 S2）”的读法下：`S { f: v }` 移走 `v`，`recover { v }` 应报
`E-LS-MOVE`；但这个程序在 surface 上是合法的“`val` 可别名”用法。
两种读法必有一个与 `00` 冲突，T4a 无法开证。

> 附注：`S { f: v }` 的结构体构造规则、`s.f` 的字段读取规则已在
> `semantics.md` §2.3 补上（`Construct` + `Place-Field`）；§3.5 的证明按新规则进行。

### 3.3 必须做的选择

| 方案 | 改动 | 代价 |
|---|---|---|
| **A. `val` 仿射** | surface 明确 `val` 不可 Copy；复制必须 `read` 产生新 `val` 并登记 | 与 `00` “`val` 可别名”冲突，需改 `modes.md`/`00` |
| **B. `val` 可别名 + 全别名追踪** | 判断改为 `Σ;ρ ⊢ e : T@m ▷ C ⊣ Σ'`；`Aliases*(p)`/`Consumed*(e)` 覆盖聚合字段；`R3-read`/`R4-store` 写回 `Σ'` | 规则与证明都变大；但保留 surface 语义 |

无论选哪个，**先修静态语义，再谈 T4a**。

### 3.4 静态规则现状（已写入 `semantics.md` §2）

ADR-31 方案 B 已落地，下面是本文件后续证明使用的版本；权威规则以
[`semantics.md` §2](semantics.md) 为准。

```text
Σ = (Γ, Λ, M, H)                    H : Place ⇀ ℘(Bid)
Σ; ρ ⊢ e : T @ m ▷ C ⊣ Σ' ; A       A 是结果值的别名集
```

与早期草案的差异（必须按新版本证明）：

| 项 | 旧草案 | 现行规则 |
|---|---|---|
| `H` 的含义 | place 可达别名 | place 的**值内部**持有的别名 |
| `freeze`/`read` | `H(p) += b` | 新 `b` 放入结果 `A`，由 `let`/存储写入 holder 的 `H` |
| `Aliases*` | 裸 `b` 集合 | `(q,b)` **出现位置**集合，含聚合字段 |
| `Consumed*` | place 的 `H` 并集 | `Σ→Σ'` 中消失的 `(q,b)` 出现 |
| `recover` | `Aliases* ⊆ Consumed*` | `ConsumeResult` 后 `Aliases*(Σ_c,p)=∅` |
| 存储 | `H(p) += H_of(v)` | 强更新 `H(p):=A_v`，并清理祖先 place |

关键规则（简化形式；完整前提见 `semantics.md` §2.3）：

```text
(R3-freeze)
  Σ ⊢ p : T @ uniq at ρ_p    live(Λ,p)=∅    b fresh
  ────────────────────────────────────────────────────
  Σ; ρ ⊢ freeze p : val_{ρ_p}[T] @ frozen ▷ {ρ⊑ρ_p}
      ⊣ Σ[Λ+=(b,p,frozen,ρ_p), mode(p):=frozen] ; {b}

(R3-read-Alias)
  Σ ⊢ p : T @ frozen at ρ_p    ¬COPY(T)    b fresh
  ────────────────────────────────────────────────────
  Σ; ρ ⊢ read p : val_{ρ_p}[T] @ frozen ▷ {ρ⊑ρ_p}
      ⊣ Σ[Λ+=(b,p,frozen,ρ_p)] ; {b}

(R3-recover)
  Σ; ρ ⊢ e : val_{ρ_p}[T] @ frozen ▷ C ⊣ Σ_e ; A_e
  A_e ≠ ∅    ∀b∈A_e. target(b)=p
  Σ_c = ConsumeResult(Σ_e,A_e)
  Aliases*(Σ_c,p) = ∅
  ────────────────────────────────────────────────────
  Σ; ρ ⊢ recover { e } : T @ uniq ▷ C
      ⊣ Σ_c[mode(p):=uniq, H(p):=∅, Λ-=live(Λ_c,p)] ; ∅
```

`Aliases*`、`Holders`、`Consumed*`、`ConsumeResult` 的定义见 `semantics.md` §2.2；
`H` 的粒度可以是根或字段，但规则要求 `H(q) ∩ H(q.f)=∅`，且写字段时同步清理祖先。

### 3.5 M2 的 L-Adequacy：`freeze` / `read` / `recover`

> **范围**：只证这三个动态规则（S8/S4/S9）的静态-动态对应；
> 不碰 call/region/drop，也不宣布 M2 完成。

### 3.5.0 匹配关系 `Match(Σ,S)`

`L-Adequacy` 的载体是静态状态 `Σ` 与动态配置 `S=(γ,σ,β,B,…)` 的匹配：

```text
Match(Σ,S) 当且仅当：
(M1) γ/σ 中每个 place 的类型、mode、区域与 Γ/Σ 一致；
(M2) b ∈ Λ ⇔ b ∈ dom B；B(b)=(m,p,ρ_s) 与 Λ 中的 Borrow 逐字段一致；
(M3) 对每个 place q：H(Σ,q) = { b | q 的值内部含 val(b) 或 ref(b) }；
(M4) M = { root(p) | p 已被 move 从 γ/σ 删除 }；
(M5) 若结果尚未绑定，则其句柄集合恰为 A；若已绑定，A 已写入某个 H(q)。
```

由 M2 得动态别名表与静态 `Λ` 一致；`REFS(root(p)) = { b | B(b).place overlaps p }`，
因此

```text
(M2) ⇒ live(Λ,p)=∅ ⇔ REFS(root(p))=∅
```

还需要两个辅助引理；它们都由 `Match` 与 `WF` 直接展开：

- **L-Holder**：若 `Match(Σ,S)`、`b∈Λ` 且 `b∉A`（不在飞行中），则
  `Holders(Σ,b)≠∅`，且每个 `q∈Holders(Σ,b)` 的动态值确实含 `val(b)`/`ref(b)`（I8/M3）。
- **L-Consume**：若块 `e` 从 `Σ/S` 执行到 `Σ_e/S_e`，且 `ConsumeResult(Σ_e,A_e)=Σ_c`，
  则 `CONSUMED_dyn(e)` 恰好是 `Holders(Σ,·)` 中被 `e` 移除的那些出现。
  证明对 `e` 的归约步归纳：只有 S3 `move`、S5 `write`、S12 `drop` 会移除 holder，
  它们分别对应 `R1-move`/`R4-store`/`R1-drop` 的 `H` 清空；S4/S8 只创建**在飞行中**的
  `b`，由 `A` 承载，不产生 holder。

### 3.5.1 S8 · Freeze

**命题**：若 `Σ;ρ ⊢ freeze p` 通过静态检查，且 `⟨freeze p,S⟩` 是动态 redex，
则 `Match(Σ,S)` 下 S8 的前提成立，且一步后 `Match` 保持。

证明：

1. 静态 `R3-freeze` 给出 `Σ ⊢ p:T@uniq`、`live(Λ,p)=∅`、`b` fresh；
   `Match(M1)` 给出动态 `mode(p)=uniq`；
2. 由 `live(Λ,p)=∅` 与上面的 `(M2)` 等式得 `REFS(root(p))=∅`：
   若动态有 `b'∈REFS(root(p))`，则 `B(b').place` 与 `p` 重叠，故 `b'∈live(Λ,p)`，矛盾；
3. 因此 S8 的 `mode(p)=uniq` 与 `REFS(root(p))=∅` 成立；动态取与静态 `b` 对应的 fresh `b'`；
4. 一步后：动态 `mode:=frozen`、`B+=(b',p,frozen,ρ_scope)`、`REFS(root)+=b'`，结果为 `val(b')`；
   静态 `mode:=frozen`、`Λ+=(b,p,frozen,ρ_p)`、`A={b}`，`H` 不变；
5. `H` 不变是正确的：`b` 只在结果值里，尚未存进任何 place；`A={b}` 由 M5 承载。
   于是 `Match(Σ',S')` 保持。∎

**注**：这一步不需要“`H(p)+=b`”。把 `b` 写进 `H(p)` 反而会制造一个不存在的
“`p` 的值内部含自己的借用”副本；现行规则把写入推迟到 `let`/存储，正好避免该错误。

### 3.5.2 S4 · Read（frozen 分支）

**命题**：若 `Σ;ρ ⊢ read p` 通过静态检查，且 `⟨read p,S⟩` 是动态 redex，
则 S4 的前提成立，一步后 `Match` 保持。

证明分两支：

1. **`COPY(T)`**：静态 `R3-read-Copy` 给出 `A=∅`，不改 `Λ`；动态 S4 的
   `mode(p)=frozen ∧ COPY(read(p))` 分支直接返回 `read(p)`，不登记 `B`。
   `Match(M1/M2/M3)` 均不变。
2. **`¬COPY(T)`**：静态 `R3-read-Alias` 给出 fresh `b`、`Λ+=(b,p,frozen,ρ_p)`、`A={b}`；
   `Match(M1)` 给出动态 `mode(p)=frozen` 且 `read(p)` 非 Copy，故 S4 走 frozen 非 Copy 分支，
   取 fresh `b'`，登记 `B(b')`、`REFS(root)+=b'`，返回 `val(b')`。
   与 §3.5.1 同理，`H` 不变，`A` 承载在飞行中的 `b`，`Match` 保持。

其余前提（`INIT`、`LIVE`、`READABLE`、`BOUNDS`）来自 `Match(M1)` 与 M1 的边界/初始化引理；
`frozen` 本身使 `READABLE` 成立。∎

### 3.5.3 S9 · Recover

**命题**：若 `Σ;ρ ⊢ recover { e }` 通过静态检查，且动态块执行到
`e →* val(b_owner)`、`p=target(b_owner)`、`mode(p)=frozen`，则 S9 的前提
`LIVE_ALIASES(p) ⊆ CONSUMED(e)` 成立，且一步后 `Match` 保持。

证明：

1. 静态 `R3-recover` 给出 `A_e≠∅`、所有 `b∈A_e` 的目标都是 `p`、
   `Σ_c=ConsumeResult(Σ_e,A_e)`、`Aliases*(Σ_c,p)=∅`；
2. 任取动态 `b∈LIVE_ALIASES(p)`。由 `Match(M2)` 得 `b∈Λ`，且 `B(b).place` 与 `p` 重叠；
3. 若 `b∈A_e`（块结果或飞行中的副本），`ConsumeResult` 会消费它：
   若它还有别的 holder，`ConsumeResult` **不**从 `Λ` 删除 `b`（避免破坏 I7），
   于是它属于下面第 4 条；若没有别的 holder，它进入 `CONSUMED(e)`；
4. 若 `b∉A_e` 或它还有 holder：由 **L-Holder**，存在 `q∈Holders(Σ,b)`；
   若 `q` 在 `e` 执行后仍存在，则 `(q,b)∈Aliases*(Σ_c,p)`（因为 `b` 的目标是 `p`），
   与 `Aliases*(Σ_c,p)=∅` 矛盾；所以 `q` 必须被 `e` 移除，
   由 **L-Consume** 得 `b∈CONSUMED(e)`；
5. 因此 `LIVE_ALIASES(p) ⊆ CONSUMED(e)`，S9 前提成立；`mode(p)=frozen` 由 `Match(M1)` 给出；
6. 一步后：动态 `mode:=uniq`、`REFS(root):=∅`、`B-=LIVE_ALIASES(p)`；
   静态 `mode:=uniq`、`H(p):=∅`、`Λ-=live(Λ_c,p)`。由第 3–5 条没有 `p` 的别名
   留在 `B/H` 中，故 `Match(Σ',S')` 保持，结果为 `Loc root(p)`，类型仍为 `T`。∎

**推论（`bad()` 重放：REJECT）**：§3.2 的程序在新规则下没有静态推导。
下面是按 `semantics.md` §2.3 逐条重放的状态表（`b1` 是 `freeze` 分配的别名，
`b1@x` 表示 `B(b1).place = x`）：

| 步骤 | 静态动作 | `Λ` / `H` / `mode(x)` | 结果 |
|---|---|---|---|
| 0 | `let mut x: Int = 1` | `Λ=∅`，`H=∅`，`mode(x)=uniq` | 接受 |
| 1 | `freeze x` → `A={b1}` | `Λ={b1@x}`，`mode(x)=frozen`，`H` 不变 | 接受 |
| 2 | `let v = freeze x` | `H(v)={b1}` | 接受 |
| 3 | `S { f: v }` → `A={b1}` | `H` 仍为 `H(v)={b1}` | 接受 |
| 4 | `let s = S { f: v }` | `H(s)={b1}` | 接受 |
| 5 | `recover { v }`：`A_e=H(v)={b1}` | `ConsumeResult` 删 `v`、清 `H(v)`；`Holders(b1)={s}`，故 `b1` 保留在 `Λ` | — |
| 6 | 检查 `Aliases*(Σ_c,x)` | `live(Λ,x)={b1}`，`Holders(b1)={s}` ⇒ `Aliases*={(s,b1)}` | **REJECT `E-LS-UNIQ`** |

关键点是第 5 步：`ConsumeResult` **不会**因为 `b1` 是块结果就把 `Λ` 中的 `b1` 删掉；
只要 `s` 还持有它，`I7` 要求 `b1` 继续存活，于是第 6 步看到 `(s,b1)`。
如果换回旧的 `Aliases(Λ,p)`（只看裸 `b1`），第 6 步会错误地判空并接受；
这就是本次修复前后的差别。

因此 `bad()` 不是“静态接受、动态粘滞”的反例；它会在检查阶段得到 `E-LS-UNIQ`。
**但“拒掉一个反例”不等于“T4a 已证明”**：§3.10 的状态仍是未证明。
这正是 ADR-31 方案 B 要消除的缺口。

可执行回归（2026-10-18 本机）：

```text
$ cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- tests/conformance/reject
== tests/conformance/reject/E-LS-UNIQ-val-alias-field.ls ==
  OK       E-LS-UNIQ
  detail   E-LS-UNIQ: recover in fn bad leaves alias mut unconsumed
PASS tests/conformance/reject/E-LS-UNIQ-val-alias-field.ls expected=1 actual=1
SUMMARY PASS
```

> 注意：checker-spike 是启发式，本轮它给出的 alias 名是 `mut`（解析 `let mut s` 的已知
> 简化），**不是**上面的 `b1`；它只能证明“该负例被拒”，不能替代 §3.5.3 的 `H` 重放。
> 真正的 `Aliases*(Σ_c,x)={(s,b1)}` 推导以本文表格为准，最终由 `ls-sem` 复现。

### 3.6 M2 余项的 L-Adequacy：move / write / borrow / alloc / region / drop

> **范围**：补 M2 的 Adequacy 情形；不证 Preservation/L4，也不进入 M3。
> 所有证明都使用 §3.5.0 的 `Match`、`L-Holder`、`L-Consume`。

### 3.6.0 共同引理

**L-Writable**：若 `Match(Σ,S)` 且 `Σ⊢writable(p)`，则动态 `WRITABLE(p)` 成立。

证明：静态 `R5-writable` 排除 `(q,b)∈Aliases*(Σ,p)` 中 `B(b).m_b∈{frozen,mut}`
且 `ρ_b⊑ρ_p` 的别名。由 `Match(M2)`/`L-Holder`，这些 `b` 正好是动态 `B` 中
指向 `p` 的活别名；动态 `WRITABLE` 的第 2 条检查同一集合，故成立。
`mode(p)∈{uniq,mut}` 或局部 Copy 槽由 `Match(M1)` 给出；`frozen` 被静态
`R5` 直接拒绝，动态也不会进入 S5。∎

**L-RegionExit**（条件）：若 `Σ;ρ⊢region R { e }` 通过检查，且 `e →* v`，
则在 `T1a` 成立时，`∀l∈Δ*(R). REFS(l)=∅` 且 `¬REFERS_TO(v,R)`。
`¬REFERS_TO` 由 `(Region)` 新增的 `ρ ⊑ Rgn(T)` 与 `ρ_R ⊑ ρ` 给出：
若 `v` 引用 `R`，则 `Rgn(v)=R`，`ρ ⊑ R` 与 `ρ_R ⊑ ρ` 构成环，`solve` 拒绝。
`REFS(l)=∅` 由 R2 的借用作用域（`ρ_s` 是 borrow-site 的 local）与 `Match(M2)` 给出：
任何指向 `R` 内位置的 `ref` 都必须在区域退出前结束（否则它活过了自己的块）。

证明：`REFS(l)≠∅` 意味着有一个 `ref/val` 别名的 `ρ_s` 覆盖 `R` 的退出点；
R2 要求 `ρ_s⊑ρ_target` 且 `ρ_s` 是具体 local，R4 又禁止把短寿命引用存到更长区域。
这与 `T1a`（`solve(C)=Ok ⇒ ¬Escape`）矛盾。返回/值引用逃出 `R` 同理由 R4-return 拒绝。
因此动态 S11 的两个前提成立。**T1a-mono + `Rgn*` 已收口；区域多态不在 F0**，
所以 S11 只算条件完成。∎

### 3.6.1 S3 · Move

**命题**：若 `Σ;ρ⊢move p` 通过检查且 `⟨move p,S⟩` 是 redex，则 S3 前提成立，
一步后 `Match` 保持。

证明：静态 `R1-move` 给出 `p:T@uniq`、`uniqOk(p)`、`¬COPY(T)`；
`Match(M1)` 给出动态 `mode(p)=uniq`，`WF`/`Match(M3)` 给出 `LIVE(root(p))`。
`¬COPY(T)` 保证动态值属于 `{Loc,val,ref}`，S3 可触发。
一步后动态删除 `γ(x)`；静态 `M+=root(p)`、`H⊖Desc*(p)`、`A=H*(Σ,p)`。
`M` 与“已从 γ/σ 删除”对应（M4），结果值的句柄集合正是 `A`（M5）。
∎

### 3.6.2 S6/S7 · Borrow / BorrowEnd

**S6**：静态 `R2-borrow` 给出 `p:T@uniq`、`uniqOk(p)`、`b`/`y` fresh、
`ρ_s` 为具体 local 且 `ρ_s⊑ρ_p,ρ_s⊑ρ`。`Match(M1)` 给 `mode(p)=uniq`；
`live(Λ,p)=∅` 与 `REFS(root(p))=∅` 等价（§3.5.0）。动态取同一 `ρ_s` 与 fresh `b`，
S6 前提成立。一步后动态 `γ[y↦ref(b)]`、`B+=b`、`REFS+=b`；
静态 `H(y):={b}`、`Λ+=b`。`Match` 在进入块体时保持。∎

**S7**：静态 `R2` 的输出要求 `b∉A_e` 且 `Holders(Σ_e,b)={y}`。
设块体执行到值 `v`；由 M5，`v` 的句柄集合是 `A_e`，故 `ref(b)∉REACH(v)`，
动态 S7 前提成立。一步后动态删 `B(b)`、`REFS(root)-=b`、`γ-=y`；
静态清 `H(y)`、`Λ-=b`。`Match` 保持。∎

> 这两个证明只覆盖“进入/退出借用块”的一步；块体内部的小步由归纳假设处理。

### 3.6.3 S5 · Write

**命题**：若 `Σ;ρ⊢p:=v` 通过检查且 `⟨p:=v,S⟩` 是 redex，则 S5 前提成立，
一步后 `Match` 保持。

证明：静态 `R5-write` 给出 `Σ⊢writable(p)`；由 **L-Writable** 得动态 `WRITABLE(p)`。
`Match(M1)` 给出 `p` 的类型/mode/区域，`BOUNDS(p)` 由 M1 的数组/边界引理给出；
`v` 是值。故 S5 可触发。
一步后 `Write(S,p,v)` 先 `DropOld` 再替换；静态强更新清 `Desc*(p)`、
`H(p):=A_v`、清理祖先与无 holder 的旧别名。由 M5，`A_v` 是 `v` 内部句柄集合；
动态旧值的别名随 `DropOld` 删除，新值句柄进入 `H(p)`。故 `Match` 保持。∎

### 3.6.4 S10 · Alloc

**命题**：若 `Σ;ρ⊢alloc(a,e)` 通过检查且 `⟨alloc(a,v),S⟩` 是 redex，
则 S10 前提成立，一步后 `Match` 保持。

证明：静态 `(Alloc)` 给出 `a:Alloc[ρ_a]`、`e` 的类型与 `ρ⊑ρ_a`，结果为
`box_{ρ_a}[T]@uniq`、`A=∅`、`H(l):=A_e`。`Match(M1)` 给出 `a` 的 allocator 类型；
`CAP_ALLOC_OK` 由 F0/gate matrix 的 allocator 前提提供（**条件**，不在本证明内证）。
取 fresh `l` 后 S10 可触发。动态 `σ[l]:=v`、`β(l):=(uniq,∅,live)`、`D(l)=dom`；
静态 `H(l)=A_e` 与 `v` 内部句柄一致（M5），结果 `Loc l` 的 `A=∅`。
`Δ/ D` 的更新与 `ρ_a`/当前域对应。故 `Match` 保持。∎

### 3.6.5 S11 · RegionExit

**命题**：若 `Σ;ρ⊢region R { e }` 通过检查且 `e→*v`，则在 T1a 的条件下
S11 前提成立，一步后 `Match` 保持。

证明：由 **L-RegionExit** 得 `∀l∈Δ*(R). REFS(l)=∅` 与 `¬REFERS_TO(v,R)`，
S11 可触发。`Free(S,lₙ..l₁,R)` 置 `σ=⊥`、`β.st:=dead`、`Δ(R):=∅` 并删除
指向这些位置的 `B` 条目。静态 `(Region)` 输出 `Σ_e⊖Desc*(locals(R))`，
正好清掉被释放区域的 `H`；`v` 不引用 `R`，故结果句柄集合不变。
`Match` 保持。∎

> **条件**：S11 的 Adequacy 依赖 T1a 的
> “引用不逃出区域”结论；T1a-mono 已收口（site-bound + ceiling），A-5 已由 `Rgn*` 收口（§5.5）。
> 在 F0 内 S11 不再依赖未证条件。

### 3.6.6 S12 · Drop

**命题**：若 `Σ;ρ⊢drop p` 通过检查且 `⟨drop p,S⟩` 是 redex，
则 S12 前提成立，一步后 `Match` 保持。

证明：静态 `R1-drop` 给出 `p:T@uniq`、`uniqOk(p)`；`Match(M1/M2)` 给
`mode(p)=uniq`、`REFS(root(p))=∅`、`LIVE(root(p))`。S12 可触发。
`DropVal` 递归析构字段并释放根；静态清 `Desc*(p)` 的 `H`，并只删除
`Holders` 已空的内部别名（与 `R1-drop` 一致）。`Match` 保持。
∎

> `iso` 的 core mode 是 `uniq`（`semantics.md` §2.1/§3.9.2），S12 与 `R1-drop`
> 共用；域转移由 R8 另行检查。旧版本这里写“iso 未证”是笔误，已由 §3.12.1 复核纠正。

### 3.6.7 S2 · Let（已初始化）

**命题**：若 `Σ;ρ⊢let x=e₁;e₂` 通过检查且 `e₁` 已求值为值 `v`，
则 S2 前提成立，绑定后 `Match` 保持。

证明：静态 `(Let)` 给出 `Σ₁`、`A₁`，并写 `H(x):=A₁`。动态 `S2` 绑定
`γ[x↦v]`（Copy 或仿射值）。由 M5，`A₁` 是 `v` 的句柄集合；`H(x)=A₁`
与动态值一致。其他 `Γ/γ` 项不变。M1–M4 保持。∎

> 未初始化 `let x:T;` 不在 S2 的值绑定分支内；它属于 Q9 的初始化分析
> （`modes.md`），本节的 S2 只覆盖“声明即初始化”。

### 3.6.8 M2 Adequacy 小结

| 规则 | L-Adequacy | 条件/说明 |
|---|---|---|
| S2 Let | 完成（已初始化） | uninit 由 Q9 初始化分析 |
| S3 Move | 完成 | R1/`M` 写回 |
| S4 Read | 完成（frozen 分支） | §3.5.2；其余读为 M1 |
| S5 Write | 完成 | R5/`Aliases*`/强更新 |
| S6 Borrow | 完成（进入借用块） | 块体内归纳 |
| S7 BorrowEnd | 完成（退出借用块） | `b∉A_e`/`Holders={y}` |
| S8 Freeze | 完成 | §3.5.1 |
| S9 Recover | 完成 | §3.5.3 |
| S10 Alloc | **条件完成** | 依赖 `CAP_ALLOC_OK`（F0/gate matrix） |
| S11 RegionExit | **完成（F0）** | T1a-mono + `Rgn*` |
| S12 Drop | 完成（uniq） | `iso` 分支未证 |

**下一步**：M2 Preservation/L4 见 §3.7；M3 核心见 §3.8。
S10 仍依赖 `CAP_ALLOC_OK`；S11 已由 T1a-mono + `Rgn*` 收口；
S12 的 `iso` 与 `uniq` 共用 core mode；
Progress/`L-NoStuck` 见 §3.12，T4a 相对 `CAP_ALLOC_OK`/`CAPS(f)` 纸面成立。

### 3.7 M2 Preservation 与 L4

> **范围**：M2 的 S2–S12；类型/匹配/不变量。Progress 与 T4a 见 §3.12。

### 3.7.0 陈述

**L-Preservation-M2**：若 `Match(Σ,S)`、`Σ;ρ⊢e:T@m▷C`、`solve(C)=Ok`，
且 `⟨e,S⟩→⟨e',S'⟩` 是 S2–S12 的一步，则存在 `Σ'` 使
`Σ';ρ⊢e':T@m'▷C'`（`m'` 与规则一致），且 `Match(Σ',S')`。

**L4-M2**：同一前提下，`S'` 满足 `WF(S')` 的 I1–I8。

证明分两层：

1. **类型/效果**：S2–S12 的结论类型由静态规则直接给出（S5/S12 为 `Unit`，
   S9 恢复为 `T`，S10 为 `box`，S11 为块结果类型）；动态规则只替换值/place，
   不改类型。
2. **Match 与不变量**：逐条规则检查下表；`H` 的写回与动态 `B/REFS` 同源。

### 3.7.1 逐规则表

| 规则 | 类型保持 | `Match` 关键点 | L4 触及 |
|---|---|---|---|
| S2 Let | 绑定值类型 | `H(x):=A₁` 与 `γ[x↦v]` 对齐 | I2/I7/I8 |
| S3 Move | 值类型不变 | 删 `γ(x)`，`M+=root(p)`，`H⊖Desc*`，`A=H*` | I2/I6/I7/I8 |
| S4 Read | `T`/`val(b)` | frozen 非 Copy 新增 `b`；`A` 在飞行 | I2/I3/I4/I7/I8 |
| S5 Write | `Unit` | 强更新 `H(p):=A_v`，清祖先；`DropOld` 对应 | I2/I3/I6/I7/I8 |
| S6 Borrow | 块结果类型 | `H(y)={b}`，`Λ/B/REFS` 同步 | I2/I3/I4/I7/I8 |
| S7 BorrowEnd | 块结果类型 | `b∉A_e`、`Holders={y}`；退出清 `H(y)` | I2/I3/I4/I7/I8 |
| S8 Freeze | `val(b)` | `mode:=frozen`，`Λ/B/REFS+=b` | I2/I3/I4/I7/I8 |
| S9 Recover | `T` | `ConsumeResult` 后 `Aliases*=∅`；清 `H(p)` | I2/I3/I6/I7/I8 |
| S10 Alloc | `box_ρ[T]` | `H(l):=A_e` 与 `σ[l]:=v` 对齐 | I1/I5/I7/I8 |
| S11 RegionExit | 块结果类型 | 清 `Desc*(locals(R))`；`v` 不引用 `R` | I1/I2/I5/I6/I7/I8 |
| S12 Drop | `Unit` | 清 `Desc*(p)`，只删无 holder 的内部别名 | I2/I3/I6/I7/I8 |

### 3.7.2 不变量论证

- **I1（区域分配）**：只有 S10 增 `Δ(ρ)`、S11 释放 `Δ(R)`；`alloc` 用 `ρ_a`，
  `region` 释放子区域逆序，故区域归属与嵌套不变。
- **I2（`B`/`β` 对应）**：S4/S6/S8 新增 `b` 时同步写 `β.refs`；S5/S7/S9/S12
  删除 `b` 时同步删 `B` 与 `refs`。`H` 的 holder 写回与 `B(b).place` 一致（M2/M3）。
- **I3（mut/frozen 互斥）**：S6 借出 `mut` 前要求 `REFS=∅`；S7 归还；S8 只在
  `REFS=∅` 时转 `frozen`；S9 清空后回 `uniq`。S5 的 `WRITABLE` 排除同区域
  `frozen/mut` 别名，故写不会与别名共存。
- **I4（引用作用域）**：S6 只取具体 `ρ_s` 且 `ρ_s⊑ρ_p`；后续规则不修改 `ρ_s`。
  S4/S8 的 `val` 别名用同一 `ρ_p`；S9 不延长作用域。
- **I5（`Δ` 逆序）**：S10 追加新根；S11 的 `Free` 按全局分配序号逆序，先子区域后父。
- **I6（无悬垂）**：S11 前提 `REFS(l)=∅` 与 `¬REFERS_TO(v,R)`；S12 前提
  `REFS(root)=∅`；S5 的 `WRITABLE` 排除活别名。故释放/写后不存在活引用指向 dead。
- **I7（`H ⊆ Λ`）**：S5/S12 的 `H` 清空与 `Λ` 删除在同一规则内；S9 的
  `ConsumeResult` 只在 `Holders` 为空时删 `b`，不会留下无主 `H`。
- **I8（活 `b` 有 holder）**：S4/S8/S9 的 `A` 承载飞行中的 `b`；S2/S5/S10 的
  绑定/存储把 `A` 写入 `H`；S3/S7/S9/S12 删除 holder 时同步删 `b`。

### 3.7.3 条件与未覆盖

- S10 的 `CAP_ALLOC_OK`、S11 的 T1a 仍是条件前提；
- S12 只覆盖 `uniq`，`iso` 的 `DropVal` 需要单独规则；
- S2 的未初始化 `let` 由 Q9 初始化分析处理，不在 S2 的值绑定分支；
- **Progress / `L-NoStuck` 未证**：本节只证“走一步后仍良构”，不证“总能走一步”。

因此 M2 的 Preservation/L4 是**纸面条件完成**，不能据此宣布 T4a。

### 3.8 M3：call / return / frame / drop

### 3.8.0 frame 匹配

动态帧：

```text
F = (γ_F, ret_F, locals_F, ρ_F)
```

`MatchFrame(Σ,S,F)` 在 `Match(Σ,S)` 基础上要求：

1. `γ_F` 的变量与 `Γ` 的局部/形参类型一致，`ret_F` 的槽类型等于函数返回类型；
2. `locals_F` 是当前帧的局部 place 集，`ρ_F` 是帧区域；
3. 调用者帧的 `γ/σ/β/B` 不被当前帧修改；
4. 帧退出时 `locals_F` 按声明逆序删除/析构（S14 的 `PopDrop`）。

### 3.8.1 S13 · Call

**命题**：若 `Σ;ρ⊢f(v⃗)` 通过检查且 `⟨f(v⃗),S⟩` 是 redex，则 S13 前提成立，
push 帧后 `MatchFrame` 保持。

证明：静态 `(Call)` 给出 `f=fn(x⃗:T⃗)→T`、实参类型、`C_call` 与效果/cap；
`Match(M1)` 给出实参是值。动态 S13 还要求 `solve(C_f∪C_call)=σ_r` 与 `CAPS(f)`：
前者由静态 `solve` 与 `C_call` 的方向给出；后者由 gate matrix/模块 `#[cap]` 的
`CAPS(f)` 前提提供（**条件**）。取 fresh 帧 `F=(γ[x⃗↦v⃗],ret,locals,local(call))`。
静态 `Σ' = Σ_v[H_f(x_i):=A_i]`；动态形参绑定 `v_i`，`H_f(x_i)` 与 `A_i` 对齐。
调用者帧不变，故 `MatchFrame` 保持。∎

### 3.8.2 S14 · Return

**命题**：若 `Σ;ρ⊢return v` 通过检查且 `⟨return v,S⟩` 是 redex，则 S14 前提成立，
pop 帧后 `MatchFrame` 保持。

证明：静态 `R4-return` 给出 `v:T_v`、`Rgn(v)=ρ_v`、`ρ_ret⊑ρ_v`；
动态 S14 要求 `¬REFERS_TO(v,F.ρ)`，由 T1a 的区域逃逸结论与 `R4-return` 给出
（T1a-mono + `Rgn*`；区域多态不在 F0）。`PopDrop(S,F)` 按 `locals_F` 逆序调用 S12，
其前提由 S12 的 L4-M2 与 `MatchFrame` 的局部线性性给出；随后恢复调用者 `γ` 与返回槽。
静态输出清掉帧局部的 `H`，动态删除对应 `B/β`，故 `MatchFrame` 保持。∎

### 3.8.3 S13/S14 的 Preservation/L4

- **I1/I5**：`push` 建立新帧区域，`pop` 逆序释放；不改变调用者 `Δ` 的树形结构；
- **I2/I3/I6**：形参/局部按 `MatchFrame` 绑定；`PopDrop` 复用 S12，故无重复 drop、
  无悬垂；`¬REFERS_TO(v,F.ρ)` 保证返回值不指向已释放帧；
- **I7/I8**：形参 `H_f(x_i):=A_i` 与实参 `A_i` 对齐；返回值的 `A_v` 由调用者继续持有；
  帧局部的 `H` 在 pop 时清空；
- **类型**：S13 进入函数体时形参/返回槽类型与签名一致；S14 返回值类型与 `R4-return` 一致。

### 3.8.4 M3 小结

| 对象 | 状态 | 条件/缺口 |
|---|---|---|
| S13 Call | **核心 Adequacy/Preservation 纸面完成** | `CAPS(f)`/gate matrix；无区域多态 |
| S14 Return | **核心 Adequacy/Preservation 纸面完成** | 依赖 T1a；`PopDrop` 依赖 S12（uniq） |
| frame/L4 | **核心完成** | I1–I8 的帧部分；不走递归/动态分派 |
| 完整 M3 | **未完成** | 泛型单态化、区域多态、递归、`ref[Trait]` 动态分派、跨模块/FFI unwind |

M3 的核心调用/返回/帧/析构已经进入证明；但**T4a 仍不成立**：Progress/`L-NoStuck` 未证，
完整 M3 与 M4/M5 未完成。

### 3.9 语义冻结条件审计

> 04 §14.6: **语义冻结 = M2/M3 纸面证明 + R1–R8 正负例 + `Σ'` 规则**。
> 本节只审计这扇门，不把“写了证明”当作“冻结通过”。

### 3.9.0 M3 完整性

| 项 | 状态 | 缺口/条件 |
|---|---|---|
| S13 Call / S14 Return / frame / PopDrop | **核心完成（条件）** | §3.8 |
| 泛型单态化 | 未证 | 需要 ground instantiation / 无 polymorphic recursion 引理 |
| 区域多态 | **不在 F0** | T1a-mono 覆盖 site-bound；多态函数值需新定理（`H-LS-1` 缺口） |
| 递归 | 不在 F0 | `F_boot` 仅 `#[recursion(bound)]`；无界递归 `E-LS-RECURSION` |
| `ref[Trait]` 动态分派 | 不在 F0 | vtable ABI（ADR-17/12）未进 M3 |
| 跨模块调用 | 未证 | 依赖 `Trusted` 闭包与 ABI；本地帧证明不能直接复用 |
| 闭包 / `defer` / `comptime` | 不在 M3 | surface→core 合同（`elaboration.md`）尚未执行 |

结论：M3 只完成 **call/return/frame/drop 核心**；完整 M3 未完成。

### 3.9.1 Progress / `L-NoStuck`

**陈述（F0 核心）**：若 `Match(Σ,S)`、`Σ;ρ⊢e:T@m▷C`、`solve(C)=Ok`，
且 `e∉FINAL`，则存在 `e',S'` 使 `⟨e,S⟩→⟨e',S'⟩`。

证明骨架（对 `e` 归纳，条件是 §3.9.2 的前提）：

| 构造 | 为什么能走一步 |
|---|---|
| 值 / `abort` | `FINAL`，不需步进 |
| 变量/place | `Match` 给出绑定；`INIT`/`M`/`READABLE`/`BOUNDS` 排除 stuck |
| `let` / `move` / `read` / `write` | S2/S3/S4/S5 前提由 R1/R5 + L4 给出 |
| `freeze` / `recover` | S8/S9 前提由 R3 + `Aliases*` 检查给出 |
| `borrow` / 退出 | S6/S7 前提由 R2 + `Holders` 给出 |
| `alloc` | S10 前提 = `CAP_ALLOC_OK`（条件） |
| `region` | S11 前提 = `REFS=∅`/`¬REFERS_TO`（T1a 条件） |
| `drop` | S12 前提 = `LIVE`/`REFS=∅`（R1 + L4） |
| call / return | S13/S14 前提 = `solve`/`CAPS`/`¬REFERS_TO`（条件） |
| `unsafe`/`raw`/`asm`/FFI | **不在 F0** |

**未完成的归纳步骤**：S9/S11/S14 的 `e →* v` 块闭包需要“块内 Progress”的强归纳。
分类表见 §3.11；度量 `(w,r)` 与 L-Term 单步证明见 §3.12。块闭包本身仍**未证明**，所以 `L-NoStuck` 仍是条件骨架。

### 3.9.2 条件前提收口

| 前提 | 处置 | 状态 |
|---|---|---|
| `CAP_ALLOC_OK` | gate matrix 的 allocator 前提；定义 `L-AllocCap`：`a:Alloc[ρ]` + 目标 profile 的 allocator 条目 ⇒ `CAP_ALLOC_OK` | **假设**，不在语言内核证明 |
| T1a | `T1a-mono`：site-bound + `ceil` 截断 + `Rgn*` 足迹 | **完成** |
| S12 `iso` | `iso` 的 core mode 是 `uniq`，与 `box` 共用 R1-drop/S12；域转移由 R8 另行检查 | **已收口**（不再单列 `iso` 缺口） |
| S13 `CAPS(f)` | gate matrix/模块 `#[cap]` 的入口检查 | **条件** |
| M3 泛型/动态分派 | 单态化与 vtable ABI | **未证，移出 F0** |

### 3.9.3 R1–R8 正负例审计

| 规则 | 正例 | 负例 | 状态 |
|---|---|---|---|
| R1 `uniq`/move | `dossiers/slab/accept.ls` | `E-LS-MOVE-use-after-move.ls` | 有 |
| R2 borrow | `accept-unsafe-termination`（借用代理） | `dossiers/views/reject.ls` 的 `ref` 逃逸 | 部分 |
| R3 freeze/recover | `accept-unsafe-termination` 的 cap 消费 | `E-LS-UNIQ-val-alias-field.ls` | 有 |
| R4 store/return | `dossiers/views/accept.ls` | `E-LS-REGION-ESCAPE` 负例（views/slab） | 有 |
| R5 write permission | `accept-r5-two-regions-disjoint` 等 | `E-LS-ALIAS-r5-*` | 可执行（ls-sem） |
| R6 `atom`/race | `accept-r6-atomic-fetch-add` | `E-LS-RACE-r6-*`、`E-LS-IRQ-r6-lock-rank` | 可执行（ls-sem） |
| R7 unsafe/cap | `accept-unsafe-termination.ls` | `E-LS-CAPCTX` / `E-LS-EFFECT-*` | 有（spike） |
| R8 cross-domain | `accept-r8-*` | `E-LS-RACE-r8-*` | 可执行（ls-sem） |

> R5/R6/R8 已由 `ls-sem` 覆盖（L1，2026-10-19）；本节保留冻结前的审计记录。

### 3.9.4 冻结门判定

| 条件 | 状态 |
|---|---|
| `Σ'`/`H` 规则 | **完成**（§2） |
| M2 L-Adequacy/Preservation/L4 | 核心完成（S10/S11 条件，S12 已收口） |
| M3 核心 | 完成（条件） |
| M3 完整（泛型/区域多态/递归/动态分派/跨模块） | **不在 L1**（`f0.md` §2） |
| Progress / `L-NoStuck` | **条件骨架**；分类表见 §3.11，归纳次序见 §3.12，L-Term/L-Block 未证 |
| R1–R8 正负例 | **齐备**（L1，2026-10-19；见 `results/S1-semantic-freeze.md`） |
| T4a | **纸面证明（条件：`CAP_ALLOC_OK`/`CAPS`）** |

**结论：L1 与 L2 均已通过（2026-10-19）；T4a 条件成立；L3 F0 核心已于 2026-10-20 机械化。**

### 3.10 对 T4a 的影响与当前状态

`bad()` 重放的结果是 **REJECT `E-LS-UNIQ`**（§3.5.3）。它证明的是：
“§3.2 的反例不再能穿过静态检查”，而不是 T4a 成立。

| 项 | 状态（2026-10-19） |
|---|---|
| `bad()`（`val` 进聚合后 `recover`） | **REJECT**：`Aliases*(Σ_c,x)={(s,b1)}` |
| M2 `freeze` L-Adequacy | 纸面证明（§3.5.1） |
| M2 `read`（frozen 分支）L-Adequacy | 纸面证明（§3.5.2） |
| M2 `recover` L-Adequacy | 纸面证明（§3.5.3） |
| M2 `S3 Move` L-Adequacy | 纸面证明（§3.6.1） |
| M2 `S5 Write` L-Adequacy | 纸面证明（§3.6.3） |
| M2 `S6/S7 borrow` L-Adequacy | 纸面证明（§3.6.2） |
| M2 `S10 Alloc` L-Adequacy | **条件完成**（§3.6.4，依赖 `CAP_ALLOC_OK`） |
| M2 `S11 RegionExit` L-Adequacy | **完成（F0）**（§3.6.5；T1a-mono + `Rgn*`） |
| M2 `S12 Drop` L-Adequacy | 完成（`uniq`/`iso` 共用 core mode，§3.6.6/§3.9.2） |
| M2 Preservation / L4 | **完成（条件：S10 `CAP_ALLOC_OK`）**（§3.7） |
| M3 Call/Return/Frame/Drop | **完成（条件：`CAPS`）**（§3.8） |
| M3 完整（泛型/递归/动态分派/跨模块） | **不在 L1/L2**（`f0.md` §2） |
| `L-NoStuck` / Progress | **完成（纸面）**：§3.12 的 L-Term/L-Block/L-Progress/L-NoStuck |
| R1–R8 正负例 | **齐备**（L1，2026-10-19） |
| 语义冻结门 | **L1/L2 均通过（纸面，2026-10-19）** |
| **T4a** | **纸面证明（条件：`CAP_ALLOC_OK`/`CAPS`）** |

结论：L1 与 L2 均于 2026-10-19 通过（纸面）；T4a 相对 `CAP_ALLOC_OK`/`CAPS(f)`
成立；T4b–T4e 是显式扩展。L3 的 F0 核心已机械化（`lean/LSys/T4a.lean`）；
仍不得把 T4b–T4e 写成“已机械化”。

---

### 3.11 L-Redex · 分类表

> 目的：把 core 语法**逐产生式**分成 FINAL / 上下文 / redex 三类，
> 供 L-Redex 与 L-Progress 使用。机器检查：`python tools/grammar-coverage`
> 对照 `semantics.md` §1.2 的 `e ::= …`，要求每个产生式恰好一行、无多余行。

| `e` 构造 | 分类 | 规则 / 理由 | 在 F0 |
|---|---|---|---|
| `v`（`()`/`n`/`true`/`false`/`Loc`/`C(v⃗)`/`val(b)`/`ref(b)`/`cap(κ)`/`handle(d)`/`raw(l,o)`） | FINAL | 值不再归约（若 `κ` 有待弹 Borrow 帧，先由 S7 弹出） | ✅ |
| `x` | place-redex | 按 place 读（S4）；`INIT`/`¬moved` 由 L-Adequacy | ✅ |
| `op(e⃗)` | 上下文 / S1 | 有非值实参 ⇒ `op(v⃗,E,e⃗)`；全值 ⇒ δ（S1）或 `abort` | ✅ |
| `let x = e; e₂` | 上下文 / S2 | `e` 非值 ⇒ `let x = E; e₂`；`e=v` ⇒ S2 | ✅ |
| `move p` | redex S3 | `p` 是 place | ✅ |
| `read p` | redex S4 | `p` 是 place | ✅ |
| `p := e` | 上下文 / S5 | `e` 非值 ⇒ `p := E`；`e=v` ⇒ S5 | ✅ |
| `e₁; e₂` | 上下文 / S1 | `e₁` 非值 ⇒ `E; e₂`；`e₁=v` ⇒ S1 | ✅ |
| `region R { e }` | 上下文 / S11 | `e` 非值 ⇒ 块内求值；`e=v` ⇒ S11；`e=abort` ⇒ S-Abort | ✅ |
| `alloc(a, e)` | 上下文 / S10 | `e` 非值 ⇒ `alloc(a,E)`；`e=v` ⇒ S10 | ✅ |
| `freeze p` | redex S8 | `p` 是 place | ✅ |
| `recover { e }` | 上下文 / S9 | `e` 非值 ⇒ 块内求值；`e=val(b)` ⇒ S9；`abort` ⇒ S-Abort | ✅ |
| `borrow mut p as x { e }` | 上下文 / S6,S7 | 进入借用作用域；`e=v` ⇒ S7；`abort` ⇒ S-Abort | ✅ |
| `drop p` | redex S12 | `p` 是 place | ✅ |
| `f(e⃗)` | 上下文 / S13 | 任一实参非值 ⇒ `f(v⃗,E,e⃗)`；全值 ⇒ S13 | ✅ |
| `return e` | 上下文 / S14 | `e` 非值 ⇒ `return E`；`e=v` ⇒ S14；`abort` ⇒ S-Abort | ✅ |
| `spawn(f, e)` | 上下文 / S15 | 不在 F0 | ❌ |
| `atomic(o, p, e)` | 上下文 / S16 | 不在 F0 | ❌ |
| `unsafe { e }` | 上下文 / S17 | 不在 F0 | ❌ |
| `deref_raw e` | 上下文 / S18 | 不在 F0 | ❌ |
| `abort(k)` | FINAL | trap 终点 | ✅ |

读法：

1. **FINAL** 行不参与 Progress；
2. **上下文** 行在子项非值时由同余/上下文规则走一步；
3. **redex** 行（或上下文子项到达值后）用对应 S 规则；前提由 L-Adequacy 给出；
4. `region`/`recover`/`return` 的 `e →* v` 由 §3.12 的 L-Block 供给，
   `abort` 由 §3.4 的 S-Abort 传播。

### 3.12 L-Term · 度量与逐条核对

`S9/S11/S14` 的 `→*` 前提不做同余化，改用**终止性**消除。度量定义在**配置**上
（把 continuation 插回整项），`M = (w, r)` 取字典序：

```text
w(v) = 0                     (* 所有值；变量 x 也记 0 *)
w(x) = 0
w(op(e⃗)) = 1 + Σ w(eᵢ)
w(let x=e; e₂) = 1 + w(e) + w(e₂)
w(move p) = 1
w(read p) = 1
w(p := e) = 1 + w(e)
w(e₁; e₂) = 1 + w(e₁) + w(e₂)
w(region R{e}) = 1 + w(e)
w(alloc(a,e)) = 1 + w(e)
w(freeze p) = 1
w(recover{e}) = 1 + w(e)
w(borrow p as x{e}) = 1 + w(e)
w(drop p) = 1
w(f(v⃗)) = 1 + Σ w(vᵢ) + w(e_f)     (* 调用体展开一次；F0 无递归 ⇒ 有定义 *)
w(return e) = 1 + w(e)
w(spawn(f,e)) = 1 + w(e)
w(atomic(o,p,e)) = 1 + w(e)
w(unsafe{e}) = 1 + w(e)
w(deref_raw e) = 1 + w(e)
w(abort(k)) = 0
w(κ[e]) = w(κ[□]) + w(e)            (* continuation 插回 *)
r(κ) = |{ Borrow(b,p) ∈ κ }|        (* 待弹出的块帧数 *)
```

**为什么不是 `(d,|e|)`**：S13 进入被调体时 `|e|` 可增，S14 返回时 `d` 可增；
两个分量交替上升，字典序不成立。`w` 把调用体展开进权重，S13/S14 都严格下降。

**L-Term（单步）**：`WT(S,e)` 且 `⟨e,S⟩ → ⟨e',S'⟩` ⇒ `M(e',S') < M(e,S)`。
证明：对 `→` 的推导做归纳（S6′ 用前提步的 IH）。

| 规则 | 归约 | `w` 前 | `w` 后 | 下降分量 |
|---|---|---:|---:|---|
| S1 | `E[r] → E[r']`（δ 到值或 abort） | `w(E[□])+1` | `w(E[□])+0` | w |
| S2 | `let x=v; e → e` | `1+w(e)` | `w(e)` | w |
| S3 | `move x → v` | 1 | 0 | w |
| S4 | `read p → v` | 1 | 0 | w |
| S5 | `p := v → ()` | 1 | 0 | w |
| S6 | `borrow{e} → e`（进入 + 压帧） | `1+w(e)` | `w(e)` | w |
| S6′ | 借用体内一步 | `w(e)` | `w(e')` | w（IH） |
| S7 | `v`（弹借用帧） | `w(v)` | `w(v)` | **r**（减 1） |
| S8 | `freeze p → val(b)` | 1 | 0 | w |
| S9 | `recover{val(b)} → Loc` | 1 | 0 | w |
| S10 | `alloc(a,v) → Loc` | 1 | 0 | w |
| S11 | `region R{v} → v` | 1 | 0 | w |
| S12 | `drop p → ()` | 1 | 0 | w |
| S13 | `κ[f(v⃗)] → κ[e_f]` | `w(κ[□])+1+w(e_f)` | `w(κ[□])+w(e_f)` | w |
| S14 | `κ[return v] → κ[v]` | `w(κ[□])+1` | `w(κ[□])` | w |
| S-Abort | `E[abort] → abort` | `w(E[□])` | 0 | w |

`r` 只由 S7 减 1、只由 S6 增 1；但 S6 同时让 `w` 减 1，所以字典序不会因 `r` 回增而失败。
S7 是唯一的“项不变”步，靠 `r` 严格下降。

**L-Term\***：`e →+ e'` ⇒ `M(e') < M(e)`（字典序传递）。

**L-Block / L-Progress / L-NoStuck（对 `M=(w,r)` 强归纳，互证）**：

固定 `M`，假设两个引理对所有 `M' < M` 成立。

```text
L-Progress(M):
  WT(S,e) ∧ ¬FINAL(e,S) ⇒ ∃e',S'. ⟨e,S⟩ → ⟨e',S'⟩ ∧ M(e',S') < M(e,S)。

L-Block(M):
  WT(S,e) ∧ ¬FINAL(e,S) ⇒ ∃f,S'. e →* f ∧ FINAL(f,S')。
```

**L-Progress(M) 的证明**（按 §3.11 分类）：

1. `v` / `abort(k)`：若 `κ` 无 `Borrow` 帧则 `FINAL(e,S)`，与前提矛盾；
   若有 `Borrow` 帧，S7 弹出（项不变），`r` 减 1 ⇒ `M` 下降。
   （F0 的静态检查保证函数体以 `return` 结束，所以调用帧下不会出现裸值。）
2. **上下文**（`op` / `let` / `p:=` / `e₁;e₂` / `alloc` / `f(…)` / `E.f` / `E[i]` /
   `return` / `unsafe` / `deref_raw` / `atomic` / `spawn`）：
   被求值的子项非 final；`w(子项) < w(e)`，故 `M(子项) < M(e)`。
   由 IH（L-Progress）得到一步，按上下文抬升。
3. **redex**（子项全为值）：S1–S5/S8/S10/S12/S13 的前提由
   L-Adequacy（§3.5/§3.6/§3.8）给出；L-Term 给出 `M` 下降。
4. `region R { e }` / `recover { e }` / `return e`：
   内层 `w(e) = w(outer) - 1 < w(outer)`，故 `M(e) < M(outer)`。
   由 IH（**L-Block**）得 `e →* f` 且 `FINAL(f,S')`：
   - `f = v` ⇒ S11/S9/S14 的前提由 §3.12.1 给出（T1a-mono + `Rgn*`、T3）；
   - `f = abort(k)` ⇒ S-Abort。
5. `borrow mut p as x { e }`：S6 的前提由 L-Adequacy（R2 + `Match`）给出；
   一步进入（压 `Borrow` 帧），`w` 减 1。

**L-Block(M) 的证明**：由 L-Progress(M) 得 `e → e'` 且 `M(e') < M`；
对 `e'` 用 IH（L-Block）得 `e' →* f`；拼接 `e → e' →* f`。

**L-NoStuck**：

```text
WT(S,e) ⇒ ¬UB(e,S)。
证明：若 FINAL(e,S)，由 UB 定义直接 ¬UB；否则由 L-Progress 得 ∃step，¬UB。
```

**T4a（F0）**：

> 若 `P ∈ F0`、`Safe(P)`、静态检查通过、`solve(C)=Ok`，
> 则 `P` 不触发 UB-1…UB-4、UB-8…UB-10、UB-12、UB-14；
> UB-6/7 是定义行为（trap），UB-5/11/13/15 在 F0 内 vacuous。

证明：

1. **L-NoStuck**：程序不会停在非 final 状态。
2. **T1（无悬垂）**：T1a-mono + `Rgn*` 给出静态无逃逸；L4（§3.7）每步保持 I1–I8，
   `WF(S)` 由初始配置归纳得到，故活引用的目标未 `dead`。
3. **T3（`recover` 唯一性）**：§3.5.3 的 `H⇔B` + L-Consume；F0 内无 `shared/cell`。
4. **UB 映射**：
   - UB-1：`BOUNDS` ⇒ `abort(Bounds)`（定义行为）；
   - UB-2 悬垂 / UB-3 double free：T1 + S12 `LIVE` + 静态 `E-LS-DROP`；
   - UB-4 未初始化：S4 `INIT` + `E-LS-INIT`；
   - UB-5 竞争：F0 单线程，vacuous；
   - UB-6 溢出：wrapping 是定义行为；UB-7 除零/移位：`abort`；
   - UB-8/9/10 raw/unsafe：F0 无，vacuous；
   - UB-11 MMIO：F0 无（T4b）；
   - UB-12 求值序：`E` 左到右，`δ` 确定；
   - UB-13 栈：F0 无递归/循环，vacuous；
   - UB-14 drop 中使用：S12 + A9（`abort`，不 unwind）；
   - UB-15 FFI：F0 无（T4c）。

**条件**（显式假设，不是缺口）：

- `CAP_ALLOC_OK`：S10 的 allocator 前提（gate matrix）；
- `CAPS(f)`：S13 的 cap/effect 入口检查。

两者都不在语言内核证明；T4a 是**相对这两个假设**的条件定理。

**结论**：T4a 在 F0 上成立且已机器检查（F0 核心模型，见 §5）；T4b–T4e 仍是显式假设/扩展。

### 3.12.1 复核：S9/S11/S14 的 L-Adequacy

| 规则 | 需要的动态前提 | 静态来源 | 用到的引理 | 状态 |
|---|---|---|---|---|
| S9 Recover | `mode(p)=frozen`；`LIVE_ALIASES(p) ⊆ CONSUMED(e)` | R3-recover：`Aliases*(Σ_c,p)=∅` | `Match(M1/M2)`、L-Holder、L-Consume、T3 的 `H⇔B` | **完成**（模 T3 的 `H⇔B`） |
| S11 RegionExit | `∀l∈Δ*(R). REFS(l)=∅`；`¬REFERS_TO(v,R)` | `(Region)` 的 `ρ ⊑ Rgn(T)`；R2 借用作用域 | T1a-mono、`Match(M2)`、I6 | **完成（F0）** |
| S14 Return | `¬REFERS_TO(v,F.ρ)`；`PopDrop` | R4-return：`ρ_ret ⊑ ρ_v` | T1a 返回分支、S12（`iso` 共用 `uniq` core mode） | **条件**（T1a） |

**复核发现并已修正的两处**：

1. **`(Region)` 原先没有结果区域约束**。旧规则只写 `ρ_R ⊑ ρ`，因此
   `region R { box @ R }` 可以静态通过，动态 S11 却因 `REFERS_TO(v,R)` 粘滞——
   这是静态规则的真实漏洞，不是证明缺口。已补 `ρ ⊑ Rgn(T)`：
   结果必须比区域块活得久，`box @ R` 被拒绝。
2. **S12 的 `iso` 注记与 §3.9.2 的「已收口」矛盾**。结论：`iso` 的 core mode 是
   `uniq`，S12 与 `R1-drop` 共用；域转移由 R8 检查。旧注记已删除。

**仍需保留的条件**：

- S11/S14 的 `¬REFERS_TO` 依赖 **T1a-mono**（site-bound + ceiling）与 **`Rgn*`**（A-5）；
  二者已在 F0 内完成，不再有未证字段缺口。
- S9 依赖 T3 的 `H ⇔ B` 与 L-Consume；L-Consume 的归纳已写出（§3.5.0），
  但 T3 的 `shared`/`cell` 不在 F0，F0 内可用。
- `→*` 前提按 `FINAL(f,S')` 理解：块内若留下 `Borrow` 帧，`e →* f` 不会到 FINAL；
  S6/S7 的静态作用域保证借用在块值返回前退出。

**状态**：L-Term、L-Block、L-Progress、L-NoStuck 均已写出；S9/S11/S14 的
L-Adequacy 在 F0 内完成（T1a-mono + `Rgn*` + T3）。**L2 通过（纸面）**；
T4a 相对 `CAP_ALLOC_OK`/`CAPS(f)` 成立，并已由 `lean/LSys/T4a.lean` 机器检查（F0 核心）。

## 4. 18 条规则的证明义务表

| 规则 | Adequacy 需要 | Preservation 需要 | 状态 |
|---|---|---|---|
| S1 Pure | `δ` 全定义 | 类型保持 | M0 完成 |
| S2 Let | 值类型 | `γ`/`Γ` 扩展 | Adequacy/Preservation 完成（已初始化，§3.6.7/§3.7）；uninit 走 Q9 |
| S3 Move | `uniqOk`、`LIVE` | `M` 更新 | Adequacy/Preservation 完成（§3.6.1/§3.7） |
| S4 Read | `INIT`/`READABLE` | 类型/`Λ` | Adequacy/Preservation 完成（frozen 分支，§3.5.2/§3.7）；其余读为 M1 |
| S5 Write | `WRITABLE` | 旧值析构、`Λ` | Adequacy/Preservation 完成（§3.6.3/§3.7） |
| S6 Borrow | `uniqOk`、`ρ_s ⊑ ρ_p` | `B/β` 更新 | Adequacy/Preservation 完成（§3.6.2/§3.7） |
| S7 BorrowEnd | 作用域 | 别名归还 | Adequacy/Preservation 完成（§3.6.2/§3.7） |
| S8 Freeze | `uniq`、`REFS=∅` | `froz` 状态 | Adequacy/Preservation 完成（§3.5.1/§3.7） |
| S9 Recover | `Aliases*`/`Consumed*` | 唯一性恢复 | Adequacy/Preservation 完成（§3.5.3/§3.7） |
| S10 Alloc | `Cap[Alloc]`、`ρ ⊑ ρ_a` | `Δ/D` | **条件完成**（§3.6.4/§3.7；依赖 `CAP_ALLOC_OK`） |
| S11 RegionExit | `REFS=∅`、`¬REFERS_TO` | `Free`/I5/I6 | **条件完成**（§3.6.5/§3.7；`(Region)` 已补 `ρ ⊑ Rgn(T)`，仍依赖 T1a） |
| S12 Drop | `LIVE`、`uniq/iso` | `DropVal` | 完成（`uniq`/`iso` 同 core mode，§3.6.6/§3.7） |
| S13 Call | `solve(C)`、cap/effect | 帧/γ | **Adequacy/Preservation 核心完成（§3.8）**；`CAPS` 条件 |
| S14 Return | `¬REFERS_TO` | `PopDrop` | **Adequacy/Preservation 核心完成（§3.8）**；依赖 T1a |
| S15 Spawn | 不在 `F0`；T4e | — | T4e |
| S16 Atomic | 不在 `F0`；T4e | — | T4e |
| S17 Unsafe | 不在 `F0`；T4b | — | T4b |
| S18 Raw | 不在 `F0`；T4b | — | T4b |

---

## 5. 机械化状态（2026-10-20 更新）

Lean 4.6.0 已装入 `.tools/lean/`（gitignored）；CI 用 elan 安装同一版本。
`bash lean/check.sh` 按依赖顺序构建十三个模块：

| 模块 | 内容 |
|---|---|
| `lean/LSys/Term.lean` | `Expr`/`Ctx`/`State`、`M=(w,r)`、`Step`、**L-Term**、**L-Term\*** |
| `lean/LSys/State.lean` | `Σ=(Γ,Λ,M,H)`、`Match(M1–M5)`、`ConsumeResult`、**L-Holder**、**L-Consume** |
| `lean/LSys/Adequacy.lean` | `WT`、`Rgn*`/T1a-mono、S3/S4/S5/S8/S9/S10/S11/S12/S14 的 L-Adequacy 逆推 |
| `lean/LSys/Progress.lean` | **L-Progress**（`progress_any`、`WT` 形式 `progress`）、**L-NoStuck** |
| `lean/LSys/Block.lean` | **L-Block**：`Mlt` 良基 + 每步下降 ⇒ `terminates` |
| `lean/LSys/Runtime.lean` | **T4a 地基片段**：真实 heap/btab/flight、I1–I4、`RStepCore`、**L4** `wf_preserved_core`、**T1** `t1_no_dangling`、**T3** `t3_recover_unique` |
| `lean/LSys/Runtime.lean` | 真实 heap/btab/flight、I1–I4、`RStepCore`（含 drop/regionExit）、L4/T1/T3 片段 |
| `lean/LSys/Env.lean` | 环境、`let`/`move`/`borrow`、`WFE` |
| `lean/LSys/Holders.lean` | 动态 `H`/`ConsumeResult` |
| `lean/LSys/TypedStep.lean` | premise-carrying `StepP`/`RedexOK`、`progressP` |
| `lean/LSys/Unified.lean` | 统一 `ConfE`、`WFU`（完整 H⇔B）、`ConsumeResultU` |
| `lean/LSys/Path.lean` | `Path`/`Prefix`/`Desc`/`Anc`/`Overlap`；`State.Place = Path` |
| `lean/LSys/T4aSafe.lean` | `Safe`/`SafeP`/`RuntimeSafe`/`RecoverSafe` 组装 |
| `lean/LSys/T4a.lean` | **T4a**：`¬UB ∧ 终止 ∧ F0 事件均为定义行为` |

```bash
bash lean/check.sh
# PASS lean: L3 + T4a foundation (steps 1-6; no sorry, no sorryAx)
```

`#print axioms`：`step_decreases` 仅 `propext`；`progress_any`/`progress`/
`l_no_stuck_wt`/`adequacy_*` 无公理或仅 `propext`；`l_consume`/`terminates`/`t4a`/`wf_preserved_core`
为 `propext, Quot.sound`；`t1_no_dangling` 无公理；**没有 `Classical.choice`、没有 `sorryAx`**。

**建模边界**（详见 `lean/README.md`）：F0 核心把 place 视为不透明 id；
`Step` 在 F0 语法上是全的，因此 `progress_any` 比论文的“良类型 ⇒ redex”更强，
`progress` 仍以 `WT` 为参数；`F0Event` 只覆盖 bounds/overflow/div-zero/eval-order/drop-use；
其余 UB 由 T1/T3/静态检查承担。Runtime 地基仍是片段：`RStepCore` 只覆盖
read/write/alloc/freeze/recover，`drop`/region exit、环境/`let`/`move`、holder/H 追踪、
premise-carrying `Step` 仍待。**仍不得**把 T4b–T4e 写成“已机械化”。

---

## 6. 下一步（严格顺序）

1. ~~**修静态语义**：判断加输出 `⊣ Σ'`；`R3-read`/`R4-store`/`R1-move` 显式写回~~（2026-10-18 完成）；
2. ~~**定 `val` 策略**：B（可别名 + `Aliases*`）~~（ADR-31；`modes.md` Q8/Q9 已同步）；
3. ~~**补 M2 的 L-Adequacy**：`freeze`/`read`/`recover`~~（2026-10-18 完成，§3.5）；
4. ~~**补 M2 余项 Adequacy**：`S2/S3/S5/S6/S7/S10–S12`~~（2026-10-18 完成，§3.6；S10/S11 条件，S12 `uniq`/`iso` 已收口）；
5. ~~**M2 Preservation / L4**：S1–S18 的保持性与 I1–I8~~（2026-10-18 完成 M2 子集，§3.7）；
   ~~**M3 核心**：call/return/frame/drop~~（§3.8，条件完成）；
6. ~~**L2**：B1 `L-Term` → B2 `L-Block` → B4 `L-Progress` → B5 `L-NoStuck`~~（2026-10-19 完成，§3.12）；T4a 纸面成立；L1/L2 均已过。
7. **M4**：参考解释器 + conformance 反例；
8. **M5**：T4b–T4e 扩展（MMIO/FFI/栈/线程）；
9. ~~工具链可用后，把 M0/M1/M2/M3 核心搬进 Lean~~（2026-10-20：L3 F0 核心六个模块全部机器检查）。

**当前结论**：L1 与 L2 均于 2026-10-19 通过（纸面）；T4a 相对
`CAP_ALLOC_OK`/`CAPS(f)` 成立；T4b–T4e 是显式扩展；L3 F0 核心已机械化；M4 参考解释器、M5 扩展仍未开始。
