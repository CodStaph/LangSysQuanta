# spec/t4-proof.md · T4a 执行报告（M0/M1 完成，M2 阻断）

> **状态**：`草稿 · 执行中`。M0/M1 有纸面证明；M2 的 `L-Adequacy` 失败，T4a **未证明**。
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
| M2（region/borrow/freeze/recover） | **阻断**：静态判断没有输出状态，`val` 别名进入聚合字段后无法追踪 |
| M3（call/return/frame/drop） | 未开始（依赖 M2） |
| T4a | **未证明** |
| 机械化 | 未开始（工具链不可用） |

**阻断的核心**：`semantics.md` §2 的静态判断是

```text
Σ; ρ ⊢ e : T @ m ▷ C
```

但 `Σ` 没有输出。`R1-move` 用 `⊣ M ∪ {root(p)}` 传递 moved 集，`R3-read` 只在
散文里说“把别名加入后续 `Λ`”，`R4-store` 不记录聚合字段里的别名。
证明 `L-Adequacy` 时，`recover` 无法知道 `s.f` 里还有一个 `val` 副本：
静态接受、动态 `S5/S9` 粘滞。**T4a 当前不可证**，必须先修静态语义。

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

## 3. M2 阻断：`val` 别名进入聚合字段

### 3.1 需要的静态输出

要证 M2 的 `L-Adequacy`，`R3-read` 必须把新别名写回 `Σ`，`R1-move` 必须把
moved 写回 `Σ`，`R4-store` 必须把“目标 place 现在持有该别名”写回 `Σ`。
当前判断没有 `⊣ Σ'`，所以这些信息在证明里丢失。

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

在“`val` 可别名（Copy）”的读法下：`S { f: v }` 复制句柄，`s.f` 是独立别名；
`recover { v }` 只消费 `v`，静态接受；动态 `S9` 的 `LIVE_ALIASES(x)` 仍含 `s.f`，
于是 `S9` 粘滞，或 `S5` 写 `x` 时与 `s.f` 冲突 ⇒ **静态接受、动态 UB**。

在“`val` 仿射（核心 S2）”的读法下：`S { f: v }` 移走 `v`，`recover { v }` 应报
`E-LS-MOVE`；但这个程序在 surface 上是合法的“`val` 可别名”用法。
两种读法必有一个与 `00` 冲突，T4a 无法开证。

> 附注：`S { f: v }` 的结构体构造规则、`s.f` 的字段读取规则也没有在
> `semantics.md` §2.3 列出；这属于同一类 `L-Adequacy` 前置缺口。修 §3.5 时一并补。

### 3.3 必须做的选择

| 方案 | 改动 | 代价 |
|---|---|---|
| **A. `val` 仿射** | surface 明确 `val` 不可 Copy；复制必须 `read` 产生新 `val` 并登记 | 与 `00` “`val` 可别名”冲突，需改 `modes.md`/`00` |
| **B. `val` 可别名 + 全别名追踪** | 判断改为 `Σ;ρ ⊢ e : T@m ▷ C ⊣ Σ'`；`Aliases*(p)`/`Consumed*(e)` 覆盖聚合字段；`R3-read`/`R4-store` 写回 `Σ'` | 规则与证明都变大；但保留 surface 语义 |

无论选哪个，**先修静态语义，再谈 T4a**。

### 3.5 方案 B 的最小形式化（用于解除阻断）

把静态状态扩成四元组：

```text
Σ = (Γ, Λ, M, H)
H : Place ⇀ ℘(Bid)        每个 place 当前可达的别名集合
```

判断改为带输出：

```text
Σ; ρ ⊢ e : T @ m ▷ C ⊣ Σ'
```

关键规则的变化（只列与阻断相关的）：

```text
(R1-move)  Σ ⊢ p : T @ uniq at ρ_p   ...
           ────────────────────────────────────────
           Σ; ρ ⊢ move p : T @ uniq ▷ {ρ⊑ρ_p} ⊣ Σ[M+=root(p)]

(R3-read)  Σ ⊢ p : T @ frozen at ρ_p   b fresh
           ────────────────────────────────────────────────
           Σ; ρ ⊢ read p : val_{ρ_p}[T] @ frozen ▷ {ρ⊑ρ_p}
             ⊣ Σ[Λ+=(b,p,frozen,ρ_p), H(p)+=b]

(R4-store) Σ ⊢ p_dst : T_dst @ m_dst at ρ_dst
           Σ; ρ ⊢ v : T_v @ m_v ▷ C_v ⊣ Σ_v
           Rgn(v)=ρ_v
           ────────────────────────────────────────────────
           Σ; ρ ⊢ p_dst := v : Unit @ copy
             ▷ C_v ∪ {ρ_dst ⊑ ρ_v}
             ⊣ Σ_v[H(p_dst) += H_of(v)]

(R3-recover)
           Σ ⊢ p : T @ frozen at ρ_p
           Aliases*(Σ,p) ⊆ Consumed*(Σ,e)
           Σ; ρ ⊢ e : val_{ρ_p}[T] @ frozen ▷ C ⊣ Σ_e
           ────────────────────────────────────────────────
           Σ; ρ ⊢ recover { e } : T @ uniq ▷ C
             ⊣ Σ_e[mode(p):=uniq, H(p):=∅, Λ-=Aliases*(Σ,p)]
```

其中：

```text
Aliases*(Σ,p) = H(p) ∪ ⋃{ H(q) | q 从 p 可达（字段/索引） }
Consumed*(Σ,e) = 块 e 内被 move/drop/显式消费的 place 的 H 并集
H_of(v) = {b}          若 v = val(b)/ref(b)
        = ∅             若 v 是标量/Copy
```

这套规则把 `s.f` 里的 `val(b)` 写进 `H(s.f)`，`recover { v }` 的
`Aliases*(x)` 就能看到它；除非 `s.f`（或其根 `s`）在块内被消费，否则拒绝。
它保留 `00` 的“`val` 可别名”，但要求实现做**聚合级别的别名追踪**。

代价：`H` 是 flow-sensitive 的，`R4-store` 要做 `H` 的并集，`R1-move` 要转移
`H`；RTT v1 的 `Witness` 与 `H` 的关系需要再加一条“raw 写清空 H”的规则。
这不是小改，但没有它，`L-Adequacy` 的 S9 例过不去。

### 3.4 对 T4a 的影响

- `L-Adequacy` 的 `S9 Recover` 与 `S5 Write` 两例无法通过；
- 因此 `L-NoStuck` 无法证；
- T4a **不成立/不可证**，不是“还没写到”。

---

## 4. 18 条规则的证明义务表

| 规则 | Adequacy 需要 | Preservation 需要 | 状态 |
|---|---|---|---|
| S1 Pure | `δ` 全定义 | 类型保持 | M0 完成 |
| S2 Let | 值类型 | `γ`/`Γ` 扩展 | M0/M2 部分 |
| S3 Move | `uniqOk`、`LIVE` | `M` 更新 | M2 待 `Σ'` |
| S4 Read | `INIT`/`READABLE` | 类型/`Λ` | M1/M2 |
| S5 Write | `WRITABLE` | 旧值析构、`Λ` | M2，受 §3 阻断 |
| S6 Borrow | `uniqOk`、`ρ_s ⊑ ρ_p` | `B/β` 更新 | M2 |
| S7 BorrowEnd | 作用域 | 别名归还 | M2 |
| S8 Freeze | `uniq`、`REFS=∅` | `froz` 状态 | M2 |
| S9 Recover | `Aliases`/`Consumed` | 唯一性恢复 | **阻断** |
| S10 Alloc | `Cap[Alloc]`、`ρ ⊑ ρ_a` | `Δ/D` | M2 |
| S11 RegionExit | `REFS=∅`、`¬REFERS_TO` | `Free`/I5/I6 | M2 |
| S12 Drop | `LIVE`、`uniq/iso` | `DropVal` | M2 |
| S13 Call | `solve(C)`、cap/effect | 帧/γ | M3 |
| S14 Return | `¬REFERS_TO` | `PopDrop` | M3 |
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
- 因此 **没有机器检查**，M0/M1 只是纸面证明。

**不得**把本文件写成“T4a 已机械化”。恢复工具链后，按 §6 的顺序把 M0/M1 先搬进 Lean。

---

## 6. 下一步（严格顺序）

1. **修静态语义**：判断加输出 `⊣ Σ'`；`R3-read`/`R4-store`/`R1-move` 显式写回；
2. **定 `val` 策略**：A（仿射）或 B（可别名 + `Aliases*`），并同步 `00`/`modes.md`；
3. **补 M2 的 L-Adequacy**：先只做 `freeze`/`read`/`recover`，不碰 call/region；
4. **M3**：call/return/frame/drop；
5. **M4**：参考解释器 + conformance 反例；
6. **M5**：T4b–T4e 扩展（MMIO/FFI/栈/线程）；
7. 工具链可用后，把 M0/M1/M2 搬进 Lean；没有 `sorry` 才更新 `semantics.md` 的 T4 状态。

**当前结论**：T4a **未证明**；执行计划停在 M2 的 `L-Adequacy`，并已定位到一个具体的
`val` 别名/聚合字段缺口。先修这个缺口，继续往下才是有效工作。
