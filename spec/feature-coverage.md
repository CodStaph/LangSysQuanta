# spec/feature-coverage.md · 特性 × 证明覆盖表

> **状态**：`草稿`（W0 交付物）。
> **上位**：[`04 §14.6`](../04-S-1-执行计划.md)（冻结门与枪毙条件）、
> [`00 §12`](../00-LangSysQuanta-设计初稿.md)（`H-LS-*` 诚实降级表）、
> [`semantics.md §5.4`](semantics.md)（T4 拆分与 `F0`）、
> [`t4-proof.md`](t4-proof.md) 的「语义冻结条件审计」章节。
> **作用**：把「M3 完整」从语义冻结门里移出，改成可审计的**覆盖表**。
> 本文件只登记缺口，不生产新事实；级别一律以 `00 §12` 为准。

---

## 0. 规则（先读这一节）

1. **冻结分三层**（表 1）；`04 §14.6` 的两道门分别对应 L1 与 L2。
2. **L1 只要求 `F0` 内的规则与正负例**。`F0` 之外的特性能否进冻结门，只能通过
   「登记 `H-LS-*` + 一句可测判据」降级，不能靠补证明。
3. **「已实现」≠「已证明」**。`B-LS` 里已经跑通的泛型/装箱，在本文一律标为
   `F0` 之外；对外表述必须写「实现超出已证核心」。
4. **规则语料 ≠ 定理覆盖**。R6/R8 讲的是 `shared`/`atom` 与跨域，二者都在 `F0` 之外；
   它们仍必须有正负例（L1 是规则集冻结），但不进 T4a（L2）。
5. 改 `F0` 或改本表，必须走 `04 §9` 的变更规则，并在 §7 记一笔。

### 表 1 · 三层冻结

| 层 | 判定对象 | 成本 | 阻塞实现 | 出口 |
|---|---|---|---|---|
| **L1 规范冻结** | `F0` 内规则 + R1–R8 正负例 + `Σ'` 规则 | 4–6 周 | **是**（S0′ 入场券） | `tag spec-freeze-v0` |
| **L2 定理冻结** | T4a 纸面证明无缺口（Progress / `L-NoStuck`） | +8–12 周 | 否（可降级） | `semantics.md §5.5` 全绿 |
| **L3 机械化冻结** | Lean 4 无 `sorry` | 6–18 个月 | 否 | 机器检查 |

> 本机 Lean 工具链受网络阻塞（`t4-proof.md §5` 已记录）。**L3 不阻塞任何门**；
> 替代手段是 M4 参考解释器 + 反例搜索，见 §5。

---

## 1. `F0` 的精确定义

权威定义：[`f0.md`](f0.md)。**只允许缩小，不允许扩大**；
任何扩大都要新增一条对应引理，并登记 `H-LS-*`（见 `f0.md` §2/§4）。

**推论**：既然 `F0` 已排除泛型、区域多态、递归、动态分派、跨模块，
`t4-proof.md` 审计里的「M3 完整性」就**不可能也不应该**是 L1 的条件。
它属于 L2 的扩展义务，按 §5 降级。

---

## 2. 覆盖表

`F0`：`✅` 在安全子集内；`❌` 在扩展片段。
`定理义务`：`F0` 内指向 T4a 的子引理；`F0` 外指向 T4b–T4e 或显式假设。
`实现现状`：`B-LS` / `ls-sem`（仅 surface）/ `checker-spike`（子集）/ `未实现` / `spec-only`。
`阻塞 L1`：只对「规则集冻结」而言，与定理无关。

### 2.1 核心（`F0` 内）

| # | 特性 | `F0` | 定理义务 | 实现现状 | 降级/假设 | 阻塞 L1 |
|---|---|---|:--:|---|---|---|:--:|
| C-1 | `let` / 赋值 / 初始化（Q9） | ✅ | S2；Q9 首次赋值 = 初始化 | `B-LS` | — | 是 |
| C-2 | `move` / `read` / `write` / `drop` | ✅ | S3/S4/S5/S12 | `B-LS`（整变量）/ `ls-sem` | — | 是 |
| C-3 | `region` / `Alloc` / 区域退出 | ✅ | S10/S11；T1a-mono | `ls-sem` surface | T1a-mono | 是 |
| C-4 | `borrow` / reborrow（R2） | ✅ | S6/S7 | `ls-sem` surface | — | 是 |
| C-5 | `freeze` / `recover`（R3） | ✅ | S8/S9；T3 | `ls-sem` surface | — | 是 |
| C-6 | `call` / `return` / frame | ✅ | S13/S14 | `B-LS` | `CAPS(f)` | 是 |
| C-7 | `Array` / `Slice` / 索引与边界 | ✅ | M1；`BOUNDS` → `abort` | `B-LS` | — | 是 |
| C-8 | `struct` / `enum` / `match` | ✅ | M0/M1 片段 | `B-LS` | — | 是 |
| C-9 | 定义好的 trap（`abort`） | ✅ | `FINAL` | `B-LS` | — | 是 |
| C-10 | `COPY(T)` / 值语义 | ✅ | S1/S2 | `B-LS` | — | 是 |

### 2.2 扩展（`F0` 之外）

| # | 特性 | `F0` | 定理义务 | 实现现状 | 降级/假设 | 阻塞 L1 |
|---|---|---|:--:|---|---|---|:--:|
| E-1 | 泛型单态化 | ❌ | ground instantiation / 无多态递归引理 | `B-LS`（装箱） | **H-LS-18** | 否 |
| E-2 | 区域多态 | ❌ | T1a 扩展 | 未实现 | 收缩为 `T1a-mono` | 否 |
| E-3 | 递归 | ❌ | T4d 栈上界 | 未实现 | **H-LS-29** | 否 |
| E-4 | `ref[Trait]` 动态分派 | ❌ | vtable ABI | 未实现 | **ADR-17** | 否 |
| E-5 | 跨模块调用 | ❌ | `Trusted` 闭包 + ABI | 未实现 | **H-LS-5** / **H-LS-24** | 否 |
| E-6 | 闭包 / `defer` | ❌ | `elaboration.md` 合同 | 未实现 | 待 S0′ | 否 |
| E-7 | `comptime` | ❌ | fuel / 能力边界 | `ls-sem` surface | **H-LS-17** | 否 |
| E-8 | `cell` | ❌ | 别名边界（M-3 未决） | 未实现 | 未决 | 否 |
| E-9 | `static` | ❌ | 初始化顺序 / 无运行期初始化 | 未实现 | **H-LS-19** | 否 |
| E-10 | `shared` / `atom`（R6） | ❌ | T2 草稿 | 未实现 | **H-LS-3** | 规则语料：**是** |
| E-11 | `spawn` / `join`（R8） | ❌ | T2 / T4e | 未实现 | **H-LS-3** | 规则语料：**是** |
| E-12 | `Irq` / `Dma` 域 | ❌ | T4e | 未实现 | **H-LS-16** | 否 |
| E-13 | `unsafe` / `rawptr`（R7） | ❌ | T4b | `checker-spike` 子集 | **H-LS-4** | 规则语料：**是** |
| E-14 | `asm` / `Mmio` | ❌ | T4b | 未实现 | **H-LS-6** | 否 |
| E-15 | FFI / `extern "C"` | ❌ | T4c | 未实现 | **H-LS-5** | 否 |
| E-16 | `panic` / 错误模型 | ❌ | abort（不 unwind） | `Result` 已实现 | **H-LS-19** | 否 |
| E-17 | `profile`（`agent` / `kernel`） | ❌ | 效果并集 | 未实现 | 待 S0′ | 否 |
| E-18 | `#[boundary]` trampoline | ❌ | 效果并集 | `checker-spike` 子集 | 见 `effects.md` | 否 |

> `E-10` / `E-11` / `E-13` 的「规则语料：是」只表示 R6/R8/R7 的正负例是 L1 的条件，
> **不**表示这些特性进入 T4a。R7 的语料已存在（Q4 spike），R5/R6/R8 见 §3。

---

## 3. R1–R8 语料矩阵

| 规则 | 正例 | 负例 | 状态 |
|---|---|---|---|
| R1 `uniq` / move | `dossiers/slab/accept.ls` | `E-LS-MOVE-use-after-move.ls` | 有 |
| R2 borrow | `pending/accept-r2-borrow-then-write.ls` | `pending/E-LS-ALIAS-r2-write-during-borrow.ls` | 语料已写（pending），待 ls-sem surface + 检查器 |
| R3 freeze / recover | `accept-unsafe-termination.ls` | `E-LS-UNIQ-val-alias-field.ls` | 有 |
| R4 store / return | `dossiers/views/accept.ls` | `views/reject.ls` 的 `ref` 逃逸 | 有 |
| R5 write permission | `pending/accept-r5-two-regions-disjoint.ls`、`pending/accept-r5-sibling-index-write.ls` | `pending/E-LS-ALIAS-r5-nested-write-site.ls`、`pending/E-LS-ALIAS-r5-frozen-place-write.ls` | 语料已写（pending），待 ls-sem surface + 检查器 |
| R6 `atom` | `pending/accept-r6-atomic-fetch-add.ls` | `pending/E-LS-RACE-r6-shared-plain-write.ls`、`pending/E-LS-RACE-r6-shared-plain-read.ls` | 语料已写（pending）；rank 用例同 |
| R7 `raw` / `Unsafe` | `accept-unsafe-termination.ls` | `E-LS-CAP` / `E-LS-EFFECT-*` | 有（spike） |
| R8 cross-domain | `pending/accept-r8-iso-spawn.ls`、`pending/accept-r8-val-static-spawn.ls` | `pending/E-LS-RACE-r8-box-across-spawn.ls`、`pending/E-LS-RACE-r8-ref-across-spawn.ls`、`pending/E-LS-RACE-r8-val-local-region-spawn.ls` | 语料已写（pending），待 ls-sem surface + 检查器 |

> **可执行性缺口（2026-10-19）**：`ls-sem` 的 `ExprKind`/`Ty` 还没有
> `borrow` / `freeze` / `spawn` 的节点，也没有 `shared` / `atom` 的类型包装；
> `Lock[T, Rank]` / `Order.x` 能按 Named/路径解析，但缺语义模型。
> 所以 `pending/` 不是「只差规则实现」，而是**连解析都进不去**。
> 详见 `results/S1-semantic-freeze.md`。

**R5 的两个 region 用例**（W1 的核心）：

- 正例 `pending/accept-r5-two-regions-disjoint.ls`：`val` 别名在 region A，写入的 place 在兄弟
  region B ⇒ **必须接受**。它测的是「别名表不是全局的」（过拒绝）；
- 正例 `pending/accept-r5-sibling-index-write.ls`：冻结 `p[0]` 后写 `p[1]` ⇒ 必须接受。
  它测的是「区域级 ≠ 整块区域只读」；
- 负例 `pending/E-LS-ALIAS-r5-nested-write-site.ls`：写入点在嵌套 region B 内，但 place 的
  区域是 A，别名 `r` 的 `ρ_s = local(borrow-site) ⊑ A` ⇒ `E-LS-ALIAS`。
  它测的是「R5 看 place 的区域，不看写入点」；
- 负例 `pending/E-LS-ALIAS-r5-frozen-place-write.ls`：`freeze p[0]` 后写 `p[0]`；
  R5-writable 的模式前提与别名前提都失败 ⇒ `E-LS-ALIAS`。

**surface 决议（v2.2，已落地）**：

- **`lock` → Guard 形式**：跟 `00 §4.3` 走 `let g = m.lock();`，不引入 `lock` 关键字
  （否则 `m.lock()` 的方法名会被保留字吃掉）。`semantics.md` 的 `lockCtx` 从
  「`lock g { □ }` 内」改成「`E` 处存在活跃 `Guard` 绑定」，`rankOk` 改成活跃 `Guard`
  集上的两两检查；规则见 `modes.md` §2.2。rank 用例仍留在 `pending/`，原因从
  「surface 不存在」变成「检查器还没追踪 Guard」——这是实现缺口，不是规范缺口；
- **`atomic` → 方法形式**：surface 保留 `c.fetch_add(1, Order.SeqCst)`（`00 §5.7`），
  core 保留 S16 的 `atomic(ord, op, p, v)`，由 `elaboration.md` **E21** 连接。
  `atomicCtx(E)` 改名 **`atomicOp(E)`**（判的是 redex，不是语法上下文）；
  R5-atom 与 R6-atom 统一为 `atomicOp(E) ∨ (lockCtx(E) ∧ rankOk(E))`，
  `op`/`ord` 的合法性表在 `effects.md` §2.1；
- **`freeze` → 一元前缀形式**：`freeze postfix`（与 `move p` 同形，符合 `00 §4.3`
  的 `freeze q`）。这修正了既有语料 `E-LS-UNIQ-val-alias-field.ls` 用 `freeze x`
  却无法被 EBNF 解析的问题；`freeze(p)` 的写法在规范中统一为 `freeze p`；
- **`borrow` / `as` → 补进 EBNF v2.2**：`borrow_expr = "borrow" [ "mut" ] postfix "as"
  ident block`，`cast = unary [ "as" ty ]`。R2/R5 语料现在可解析；
  语法回归见 `tests/syntax/00-s5/s5-03b-borrow-cast.ls`。

---

## 4. 诊断优先级（语料可判定的前提）

同一程序可能触发多个码。语料要求「一个文件只测一个错误」，因此必须先约定首个检查点。
**以下顺序是提案，冻结前要写进 [`diagnostics.md`](diagnostics.md) 或一条 ADR**：

1. 语法 / 属性（`E-LS-ATTR`、`E-LS-MATCH`）
2. 未初始化（`E-LS-INIT`）
3. 已 move（`E-LS-MOVE`）
4. 借用与写权限（R2/R5 ⇒ `E-LS-ALIAS`）
5. 逃逸（R4 ⇒ `E-LS-REGION-ESCAPE`）
6. 跨域（R8 ⇒ `E-LS-RACE`）——**在 `spawn` 入口先于 R4**
7. 原子 / 锁（R6 ⇒ `E-LS-RACE`；rank ⇒ `E-LS-IRQ`）
8. `unsafe` / cap（R7 ⇒ `E-LS-UNSAFE` / `E-LS-CAP`）
9. 效果与边界（`E-LS-EFFECT`）
10. 约束求解失败 ⇒ 映射回生成该约束的规则（R2/R3/R4/R5）

> 第 6 条与第 5 条的顺序是 R8 负例能报 `E-LS-RACE` 而不是 `E-LS-REGION-ESCAPE` 的前提；
> 没有这条约定，`E-LS-RACE-r8-ref-across-spawn.ls` 的期望码就有歧义。

---

## 5. 扩展义务（T4b–T4e）

| 命题 | 覆盖 | 处置 | 登记 |
|---|---|---|---|
| T4b | `unsafe` / `rawptr` / `Mmio` / `asm` | 后端 volatile 模型，或显式信任 | H-LS-4 / H-LS-6 |
| T4c | FFI / `extern "C"` | ABI + `nounwind` 假设；安全承诺跨边界失效 | H-LS-5 |
| T4d | 递归 / 栈 | 静态栈上界（`#[recursion(bound)]`） | H-LS-29 |
| T4e | 线程 / `Irq` / `Dma` / `Trusted` | 域模型 + Iris；未证则登记 | H-LS-3 / H-LS-16 / H-LS-24 |

**替代机械化（L3 之前）**：M4 参考解释器 + 反例搜索。做法是生成 `F0` 小程序的
随机组合，跑解释器断言「要么到 `FINAL`，要么能步进」，用来在纸面证明前证伪。
测试不能替代证明，但能在 W3–W4 提前发现规则漏洞。

---

## 6. L1 冻结清单

勾选全部后，才允许 `tag spec-freeze-v0` 并进入 S0′：

- [x] `Σ = (Γ,Λ,M,H)` + `⊣ Σ'` 规则（`semantics.md §2`）
- [x] M2 L-Adequacy / Preservation / L4（条件，见上表降级列）
- [x] M3 核心：call / return / frame / drop（`t4-proof.md` 的 M3 章节）
- [x] `F0` 收缩已写出（`semantics.md §5.4`）
- [ ] R2 正负例可执行（语料在 `pending/`；ls-sem 缺 `borrow`/`freeze` surface）
- [ ] R5 正负例可执行（含两个 region 的 4 个用例，语料在 `pending/`；ls-sem 缺 `borrow` + 区域级 `H`/`Aliases*`）
- [ ] R6 正负例可执行（全部语料在 `pending/`；ls-sem 缺 `shared`/`atom`/`Guard`）
- [ ] R8 正负例可执行（语料在 `pending/`；ls-sem 缺 `spawn` + 域模型）
- [ ] 最小不可满足核 1 个可复现样例（`modes.md §5`；**无样例**，`foundations.md` 标「未开始」）
- [ ] fix-it 不得建议 `unsafe` 的负例（LS-P17；**无语料**）
- [x] 检查器回归：`accept/` 4 条、`reject/` 7 条零漏过（2026-10-19，checker-spike rc=0）
- [x] `F0` 外特性全部登记 `H-LS-*` + 可测判据（本文件 §2.2）
- [x] `semantics.md §5.5` 与 `results/S1-semantic-freeze.md` 的判定与本文一致（结论一致：T4/T4a 未证明，L2 未通过）

> 勾选状态是**事实记录**，不是计划。任何一项未勾就写「已冻结」都按 `H-LS-1` 处理。

---

## 7. 变更记录

| 日期 | 变更 | 影响 | 依据 |
|---|---|---|---|
| 2026-10-19 | 建立本表；把「M3 完整」移出 L1 | L1 可独立于 L2 出口 | `04 §14.6` 的 T4a 门允许「明确降级」 |
| 2026-10-19 | 登记 `lock`/`Guard` 与 `atomicCtx` 两处 surface 缺口 | R6 rank 用例进 `pending/` | EBNF v2.1 无 `lock` |
| 2026-10-19 | `comptime` 块作语句（`comptime_block`，免分号），表达式形式不变 | EBNF 117 产生式；GBNF 114 规则；`tests/syntax` 86/86；B-LS `comptime { }` 进语法门 | `00 §5.10` + B-LS stage1 `names_stage.ls` |
| 2026-10-19 | **v2.2 surface 决议**：`lock`→Guard（`let g = m.lock()`）、`atomic`→方法形式（core `atomic(...)`，E21）、`borrow`/`as` 进 EBNF | EBNF 117 产生式；GBNF 114 规则；`tests/syntax` 86/86；R2/R5 语料可解析 | `00 §4.3`「`lock` 返回 `Guard`」；`00 §5.7` 方法形式 |
