# spec/t4-proof.md · T4a 执行报告（M0/M1 完成，M2/M3 核心写出）

> **状态**：`草稿 · 执行中`。M0/M1 有纸面证明；M2 的 L-Adequacy/Preservation/L4
> 与 M3 的 call/return/frame/drop 核心已写出（S10/S11 条件、S12 仅 uniq）；
> 完整 M3、Progress/`L-NoStuck`、M4/M5 未完成，T4a **仍未证明**。
> **上位**：[`semantics.md` §5.4](semantics.md)（T4 拆分与路线）、
> [`semantics.md` §2](semantics.md)（静态规则）、[`ub.md`](ub.md)（UB-10 / RTT v1）。
> **性质**：纸面证明 + 证明义务审计；**未机械化**（本机无 Lean/Coq，见 §5）。
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
| 机械化 | 未开始（工具链不可用） |

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
**但“拒掉一个反例”不等于“T4a 已证明”**：§3.9 的状态仍是未证明。
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

证明：`REFS(l)≠∅` 意味着有一个 `ref/val` 别名的 `ρ_s` 覆盖 `R` 的退出点；
R2 要求 `ρ_s⊑ρ_target` 且 `ρ_s` 是具体 local，R4 又禁止把短寿命引用存到更长区域。
这与 `T1a`（`solve(C)=Ok ⇒ ¬Escape`）矛盾。返回/值引用逃出 `R` 同理由 R4-return 拒绝。
因此动态 S11 的两个前提成立。**该引理依赖 T1a，T1a 的区域多态缺口仍未关闭**，
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
> “引用不逃出区域”结论；T1a 仍有区域多态缺口（§5.5）。不得把 S11 写成无条件完成。

### 3.6.6 S12 · Drop

**命题**：若 `Σ;ρ⊢drop p` 通过检查且 `⟨drop p,S⟩` 是 redex，
则 S12 前提成立，一步后 `Match` 保持。

证明：静态 `R1-drop` 给出 `p:T@uniq`、`uniqOk(p)`；`Match(M1/M2)` 给
`mode(p)=uniq`、`REFS(root(p))=∅`、`LIVE(root(p))`。S12 可触发。
`DropVal` 递归析构字段并释放根；静态清 `Desc*(p)` 的 `H`，并只删除
`Holders` 已空的内部别名（与 `R1-drop` 一致）。`Match` 保持。
∎

> S12 的 `iso` 分支不在 `R1-drop` 内；当前只证 `uniq` 分支，`iso` 的 drop
> 需要单独规则（M3/M5 处理）。

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
| S11 RegionExit | **条件完成** | 依赖 T1a（区域多态缺口） |
| S12 Drop | 完成（uniq） | `iso` 分支未证 |

**下一步**：M2 Preservation/L4 见 §3.7；M3 核心见 §3.8。
S10 的 cap 前提、S11 的 T1a、S12 的 `iso` 分支仍是条件；
Progress/`L-NoStuck` 未证，因此 **T4a 仍未证明**。

### 3.7 M2 Preservation 与 L4

> **范围**：M2 的 S2–S12；类型/匹配/不变量。仍不证 Progress 与完整 T4a。

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
（**条件**：T1a 的区域多态缺口未关）。`PopDrop(S,F)` 按 `locals_F` 逆序调用 S12，
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

### 3.9 对 T4a 的影响与当前状态

`bad()` 重放的结果是 **REJECT `E-LS-UNIQ`**（§3.5.3）。它证明的是：
“§3.2 的反例不再能穿过静态检查”，而不是 T4a 成立。

| 项 | 状态（2026-10-18） |
|---|---|
| `bad()`（`val` 进聚合后 `recover`） | **REJECT**：`Aliases*(Σ_c,x)={(s,b1)}` |
| M2 `freeze` L-Adequacy | 纸面证明（§3.5.1） |
| M2 `read`（frozen 分支）L-Adequacy | 纸面证明（§3.5.2） |
| M2 `recover` L-Adequacy | 纸面证明（§3.5.3） |
| M2 `S3 Move` L-Adequacy | 纸面证明（§3.6.1） |
| M2 `S5 Write` L-Adequacy | 纸面证明（§3.6.3） |
| M2 `S6/S7 borrow` L-Adequacy | 纸面证明（§3.6.2） |
| M2 `S10 Alloc` L-Adequacy | **条件完成**（§3.6.4，依赖 `CAP_ALLOC_OK`） |
| M2 `S11 RegionExit` L-Adequacy | **条件完成**（§3.6.5，依赖 T1a） |
| M2 `S12 Drop` L-Adequacy | 完成（uniq 分支，§3.6.6） |
| M2 Preservation / L4 | **纸面条件完成**（§3.7；S10/S11 条件，S12 仅 uniq） |
| M3 Call/Return/Frame/Drop | **核心完成**（§3.8；`CAPS`/T1a 条件） |
| M3 完整（泛型/递归/动态分派/跨模块） | 未完成 |
| `L-NoStuck` / Progress | 未证明 |
| **T4a** | **未证明** |

结论：M2 的 L-Adequacy/Preservation/L4 与 M3 核心均已写出，但仍有条件前提；
Progress/`L-NoStuck` 与完整 M3 缺失，因此 **T4a 仍未证明**。
不得把本节写成“M2/M3 完成”或“T4a 已证”。

---

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
| S11 RegionExit | `REFS=∅`、`¬REFERS_TO` | `Free`/I5/I6 | **条件完成**（§3.6.5/§3.7；依赖 T1a） |
| S12 Drop | `LIVE`、`uniq/iso` | `DropVal` | 完成（uniq，§3.6.6/§3.7）；`iso` 分支未证 |
| S13 Call | `solve(C)`、cap/effect | 帧/γ | **Adequacy/Preservation 核心完成（§3.8）**；`CAPS` 条件 |
| S14 Return | `¬REFERS_TO` | `PopDrop` | **Adequacy/Preservation 核心完成（§3.8）**；依赖 T1a |
| S15 Spawn | 不在 `F0`；T4e | — | T4e |
| S16 Atomic | 不在 `F0`；T4e | — | T4e |
| S17 Unsafe | 不在 `F0`；T4b | — | T4b |
| S18 Raw | 不在 `F0`；T4b | — | T4b |

---

## 5. 机械化状态

本机尝试安装 Lean 4：

- `lean`/`lake`/`coq` 均未安装；
- `elan` 安装器可获取，但 Lean 4.6.0 工具链（216MB）从 GitHub 下载被限速，
  10 分钟只到 17MB，超时；
- 因此 **没有机器检查**，M0/M1 与 §3.5/§3.6 的 M2 Adequacy 都只是纸面证明。

**不得**把本文件写成“T4a 已机械化”。恢复工具链后，按 §6 的顺序把 M0/M1 与
§3.5/§3.6 的 Adequacy、§3.7 的 Preservation/L4、§3.8 的 M3 核心先搬进 Lean；
`Match`/`ConsumeResult`/`MatchFrame` 需要显式定义，不能只靠自然语言。

---

## 6. 下一步（严格顺序）

1. ~~**修静态语义**：判断加输出 `⊣ Σ'`；`R3-read`/`R4-store`/`R1-move` 显式写回~~（2026-10-18 完成）；
2. ~~**定 `val` 策略**：B（可别名 + `Aliases*`）~~（ADR-31；`modes.md` Q8/Q9 已同步）；
3. ~~**补 M2 的 L-Adequacy**：`freeze`/`read`/`recover`~~（2026-10-18 完成，§3.5）；
4. ~~**补 M2 余项 Adequacy**：`S2/S3/S5/S6/S7/S10–S12`~~（2026-10-18 完成，§3.6；S10/S11 条件，S12 仅 uniq）；
5. ~~**M2 Preservation / L4**：S1–S18 的保持性与 I1–I8~~（2026-10-18 完成 M2 子集，§3.7）；
   ~~**M3 核心**：call/return/frame/drop~~（§3.8，条件完成）；
6. **M3 完整 + Progress/`L-NoStuck`**：泛型/递归/动态分派/跨模块；
7. **M4**：参考解释器 + conformance 反例；
8. **M5**：T4b–T4e 扩展（MMIO/FFI/栈/线程）；
9. 工具链可用后，把 M0/M1/M2/M3 核心搬进 Lean；没有 `sorry` 才更新 `semantics.md` 的 T4 状态。

**当前结论**：§3.2 的 `val` 别名/聚合字段缺口已解除；M2 的 L-Adequacy/Preservation/L4
与 M3 核心已写出（S10/S11 条件、S12 仅 uniq）。T4a **仍未证明**：完整 M3、
Progress/`L-NoStuck` 与 M4/M5 仍缺。
