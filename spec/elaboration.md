# spec/elaboration.md · surface→core 合同与片段矩阵（草稿）

> **状态**：`草稿`。本文件补齐 G4：每个 EBNF 产生式的归属、surface→core 脱糖、片段边界。
> **上位**：[`langSysQuanta.ebnf`](langSysQuanta.ebnf)（唯一语法权威）、
> [`semantics.md`](semantics.md)（核心 L-Sys₀ / 18 条规则 / R1–R8）、
> [`effects.md`](effects.md)（效果与 cap）、[`04 §14`](../04-S-1-执行计划.md)（G4/W3）。
> **权威**：语法以 EBNF 为准；核心语义以 `semantics.md` 为准；本文件只给**映射**，不新增语言特性。
> **不在本文件**：完整 monomorphization 算法、trait 求解、`comptime` 求值器、后端 ABI。
> **纪律**：本文件是合同草稿，不是已实现的 elaborator；`ls-sem` 落地前不得声称“surface 已全部脱糖”。

---

## 0. 读法

- **surface**：`langSysQuanta.ebnf` 接受的源码；
- **core**：`semantics.md` 的 L-Sys₀ 项（`e ::= v | x | let | move | read | write | …`）；
- **elaboration**：把 surface 程序机械映射到 core（或明确标注“非核心/运行时服务”）；
- **片段**：`F0`（T4a 安全子集）、`F_thr`（线程）、`F_unsafe`（T4b）、`F_ffi`（T4c）等。
- EBNF v2.2 的**测试归一化**（`...`、`iso Queue`、无体 `fn`、缺分号）不是语言语法，
  不进入本合同的 surface 定义；见 [`tests/syntax/README.md`](../tests/syntax/README.md)。

---

## 1. 原则

1. **总性**：对每个通过 EBNF 解析的 surface 程序，elaboration 要么给出 core 项，
   要么给出明确诊断；不得“静默丢弃”。
2. **不新增动态语义**：脱糖只能用 core 已有的构造、`δ` 与内建调用；
   新语义必须先进 `semantics.md` / ADR。
3. **效果/cap 不擦除检查**：`eff(...)`/属性/契约在 elaboration 中保留为检查输入，
   运行期可擦除，但不得在脱糖时丢掉。
4. **片段显式**：每个产生式必须标注属于哪个片段；不在片段内的构造不得偷偷降级。
5. **可差分**：同一 surface 输入在 EBNF 识别器与未来 parser 上必须得到同一接受集；
   GBNF 是 EBNF 的机械派生，不是第二权威。

---

## 2. 核心目标摘要

```text
core value   v ::= () | n | true | false | Loc l | C(v⃗) | val(b) | ref(b)
                 | cap(κ) | handle(d) | raw(l,o) | ⊥
core expr    e ::= v | x | op(e⃗) | let x=e;e | move p | read p | p:=e
                 | e;e | region R{e} | alloc(a,e) | freeze p | recover{e}
                 | borrow mut p as x{e} | drop p | f(e⃗) | return e
                 | spawn(f,e) | atomic(o,p,e) | unsafe{e} | deref_raw e | abort(k)
```

- 静态检查：R1–R8 + `Σ=(Γ,Λ,M,H)` + `⊣ Σ'`；
- 动态规则：S1–S18；
- `F0` 只含 S1–S14 的单线程、无 unsafe/raw/asm/FFI/Mmio/Dma/Irq/shared/cell/static，
  无递归、无 `comptime`。

---

## 3. 产生式归属（全量）

> 每个 EBNF 产生式至少出现在一行；`→` 后是归属或 core 目标。
> “非核心”不等于“可忽略”：它仍需静态检查/诊断，只是不进入 L-Sys₀ 的 18 条规则。

### 3.1 词法

| 产生式 | 归属 |
|---|---|
| `ident` `int_lit` `dec_lit` `hex_lit` `bin_lit` `float_lit` `exponent` `str_lit` `char_lit` `escape` `literal` `letter` `digit` `hex_digit` `bin_digit` `str_char` `char_char` `newline` | 词法 token；elaboration 后消失 |
| `comment` `line_comment` | 词法丢弃，不进 core |
| `any_char` | 仅注释/词法内部；不进 core |

### 3.2 item / 配置 / 属性

| 产生式 | 归属 |
|---|---|
| `program` `top_item` | 程序根；逐 item 脱糖 |
| `module_item` `module_path` `profile_item` | 编译期配置（crate 图/profile）；运行期擦除 |
| `attrs` `attr` `attr_head` `builtin_attr` `attr_args` `attr_arg` | 编译期属性；封闭集检查；运行期擦除 |
| `struct_item` `field_list` `field` `union_item` | → core `C[T⃗]` 类型/构造；布局按 `00 §6.1` |
| `enum_item` `variant_list` `variant` | → core `C[T⃗]` + tag/负载；`Type.Variant` 唯一构造 |
| `trait_item` `impl_item` `fn_sign` | 静态分派记录/字典；`ref[Trait]` 动态分派**不在 F0** |
| `fn_item` | → core 函数定义；`[unsafe]` 进入 `F_unsafe` |
| `extern_item` | 边界声明；`F_ffi`（T4c），不进 F0 |
| `static_item` | → `static` 区域根；只允许 `val`/`shared`（ADR-13） |
| `const_item` | 编译期常量；擦除/内联 |
| `comptime_fn_item` | elaboration-time 求值；不进运行时 core（`E-LS-COMPTIME`） |
| `generics` `where_clause` | 单态化输入；F0 只允许可单态化的实例 |
| `params` `param` | core 形参绑定；`self` 同普通参数 |

### 3.3 类型

| 产生式 | 归属 |
|---|---|
| `ty` `path_ty` `ty_arg` `path` | → core 类型 `T` / 类型参数 |
| `mode_ty` `mode` | → `box/iso/val/ref/shared/rawptr` 的 core mode（`uniq/frozen/mut/atom/raw`） |
| `tuple_ty` | → core tuple/`C`（实现可内联为多字段布局） |
| `fn_ty` | 函数值/闭包类型；F0 只允许静态函数指针 |
| `range` | 类型参数专用（`Mmio[a..b]`/`Cap[...]`）；不产生运行期 range 值 |

### 3.4 语句与块

| 产生式 | 归属 |
|---|---|
| `block` | core `e;e` / `let` 序列；尾表达式保留 |
| `stmt` `expr_stmt` | core 表达式语句；结果丢弃 |
| `let_stmt` | → core `let x=e;e`；`let x:T;` → `let x=⊥;e` + Q9 初始化分析 |
| `defer_stmt` | 作用域退出 `drop`/`release`；**surface 脱糖**，不进 18 条规则；资源规则见 `resource.md` |
| `block_stmt` `block_expr` | if/while/for/loop/match 作为语句；分号可省略 |
| `if_expr` `while_expr` `loop_expr` | core `if`/`D-While` + `break/continue` |
| `for_expr` | range/Slice/Iterator 协议展开为 `while`；用户自定义 `for` 非目标 |
| `match_expr` `match_arm` | core `match`/`δ`；穷尽性 `E-LS-MATCH` |
| `region_block` | core `region R { e }`；区域退出 S11 |
| `unsafe_block` | core `unsafe { e }`；`Cap[Unsafe]`/模块 cap 上下文；S17 |

### 3.5 表达式

| 产生式 | 归属 |
|---|---|
| `expr` `assign_expr` `assign_op` | 赋值/复合赋值；`p:=e` → R4/R5；复合赋值脱糖为 `p := p op e`（求值一次需临时/`cell` 规则） |
| `logic_or` `logic_and` `bit_or` `bit_xor` `bit_and` `equality` `relational` `shift` `additive` `multiplicative` `unary` | `δ` 纯运算；优先级阶梯；无运算符重载 |
| `postfix` `postfix_op` `args` | 调用/字段/索引/`?`；方法调用 → 内建/函数调用 |
| `primary` | 值/变量/构造/块/控制流/`unsafe`/`recover`/`comptime`/闭包/`spawn`/`asm` |
| `tuple_expr` | core tuple/`C` 构造；`()` 为 Unit |
| `array_lit` | core 数组构造；长度编译期已知 |
| `struct_lit` `field_init` | core `C(v⃗)`；`[mode] path { ... }` 的 mode 作为类型/视图标注 |
| `if_expr` `while_expr` `for_expr` `loop_expr` | 同 §3.4；表达式位置产生值 |
| `match_expr` `match_arm` | 同 §3.4；模式绑定进入 Γ |
| `recover_expr` | core `recover { e }`；R3/S9 |
| `comptime_expr` | elaboration-time 求值；不生成运行期表达式 |
| `closure` | 捕获结构 + 函数；**不在 F0**，需 `box`/`iso` 逃逸规则 |
| `break_expr` `continue_expr` `return_expr` | core 控制流；`return` → R4-return/S14 |
| `move_expr` | core `move p`；R1/S3 |
| `spawn_expr` | core `spawn(f,e)`；R8/S15；不在 F0 |
| `asm_expr` `asm_operand` | `F_unsafe`/T4b；`Asm` 效果；不进 F0 |

### 3.6 模式、契约、效果

| 产生式 | 归属 |
|---|---|
| `pattern` | core `match` 模式；`Type.Variant` 唯一 |
| `contracts` `contract` | 静态检查输入（`requires/ensures`）；运行期擦除（`debug` 可选断言） |
| `eff_clause` `effect` | 效果行；gate matrix/边界检查；运行期擦除 |
| `attr_*`（已列） | 编译期配置；不生成运行期值 |

---

## 4. 脱糖规则（合同级）

| # | surface | core / 处理 | 状态 |
|---|---|---|---|
| E1 | `module` / `profile` / 属性 | 编译期配置，运行期擦除 | 合同已定 |
| E2 | `fn f(x:T)->U { e }` | core 函数 + 形参绑定 + `return` | 合同已定 |
| E3 | `struct/enum/union` | `C(v⃗)` / tag / 字段偏移 | 合同已定；布局待 `image.md` 冻结 |
| E4 | `let x:T;` | `let x=⊥; e` + Q9 初始化 | 合同已定；路径敏感分析 S0′ |
| E5 | `if` / `match` | core `if` / `match` + `δ` | 合同已定 |
| E6 | `while` / `loop` | `D-While` / `loop` | 合同已定 |
| E7 | `for x in e { b }` | `Range/Slice/Iterator` 协议 → `while` | 合同已定；协议细节 S0′ |
| E8 | `defer e;` | 作用域退出 `Drop`/`release`；恰好一次 | **待 `resource.md`** |
| E9 | `e?` | `match e { Ok(v)=>v, Err(e)=>return Err(e) }` | 合同已定 |
| E10 | `a.alloc(v)` / `x.slice()` / `x.len` | 内建调用/字段投影 | 合同已定 |
| E11 | `spawn f(e)` / `join(h)` | S15 + join（内建） | 合同已定；T4e |
| E12 | 闭包 `\|x\| e` | 捕获结构 + 函数；捕获 mode 按 R2/R4/R5 | **未在 F0** |
| E13 | `recover { e }` | core `recover` | 合同已定 |
| E14 | `requires/ensures/eff` | 检查输入；运行期擦除 | 合同已定 |
| E15 | `unsafe(Cap[Unsafe]) { e }` | S17 + cap 消费 | 合同已定 |
| E16 | `asm(...)` | S17/`Asm`；`F_unsafe` | 合同已定；T4b |
| E17 | `comptime e` | elaboration-time 求值 | 合同已定；求值器 S0′ |
| E18 | `static S: val[T] = c;` | `static` 区域根 | 合同已定 |
| E19 | tuple struct `struct S(T);` | 位置字段 `0` + 构造/投影 | 合同已定 |
| E20 | bitfield `#[bitfield]` 字段 | 位宽/掩码访问器 | 合同已定；布局待 `image.md` |
| E21 | `p.op(a⃗)`（`p : atom`，如 `c.fetch_add(1, Order.SeqCst)`） | core `atomic(ord, op, p, a⃗)`；`op`/`ord` 的封闭表见 `effects.md` §2.1 | 合同已定 |

> `borrow` 是 core 原语（`semantics.md` S6/S7），无脱糖；v2.2 起进 EBNF（`borrow_expr`），
> 操作数限 `postfix`（place），`as` 归 `borrow_expr`，不与 `cast` 共享。

> `E8`/`E12`/`E17` 是当前最大的合同缺口：它们没有进入 L-Sys₀ 的 18 条规则，
> 不能假装已经被 M2/M3 证明覆盖。

---

## 5. 片段矩阵

| 片段 | 允许的 surface 产生式 | 排除/延后 |
|---|---|---|
| **F0**（T4a） | `fn_item`（无 unsafe）、`let/if/while/match`、struct/enum/tuple、Array/Slice、`move/read/write/freeze/recover/drop`、`region/alloc`、call/return | `spawn`/`asm`/`extern`/`static`/`rawptr`/`unsafe`/`shared`/`atom`/`cell`/`Mmio`/Dma/Irq/闭包/`comptime`/递归 |
| **F_thr**（T2） | F0 + `spawn`/`join` + `shared`/`atom` + `atomic`/锁 | `Irq`/`Dma`/`unsafe`/FFI |
| **F_unsafe**（T4b） | F0/F_thr + `unsafe`/`rawptr`/`asm`/`Mmio` | FFI unwind、深层 soundness（`H-LS-4`） |
| **F_ffi**（T4c） | `extern`/`#[boundary]` | 跨 FFI unwind（UB-15）；退出分类见 `lean/LSys/Ffi.lean` |
| **F_boot**（T4d） | 有界递归/静态栈 | 无界递归（`E-LS-RECURSION`）；运行时 depth 预算见 `lean/LSys/Stack.lean` |

- F0 之外每个构造都必须显式标注其片段；不得“因为 parser 接受”就进入 F0。
- `for`/闭包/`ref[Trait]` 的脱糖若引入堆分配或动态分派，必须移出 F0。
- B-LS 是 surface 子集：`write`/`read_file`/`write_file`/`argc`/`arg_len`/`arg_byte`
  作为内建调用；不引入模块/属性/profile。B-LS 测试是语法证据，不是 L-Sys 语义 conformance。

---

## 6. 与 B-LS 的差异

| 项 | B-LS | L-Sys surface |
|---|---|---|
| 模块/profile | 无 | `module`/`profile` |
| 函数 | 单文件、少函数 | 泛型/ trait/ impl |
| 字符串 | `Str` 子集 | `val[Str]`/`Slice[U8]` |
| I/O | `write`/`read_file` 内建 | 库/边界 API |
| 属性 | 无 | 封闭属性集 |
| `let x:T;` | v2.1 起可解析 | Q9 初始化规则 |
| `iso Queue` 等 | 不要求 | **测试归一化**，不是正式语法 |

> B1（“B-LS 每个程序都是合法 L-Sys”）在 v2.1 后仍只对**规范形**成立；
> B-LS 源码中的 `let p: Point;` 已由 EBNF v2.1 接受，但语义由 Q9 约束。

---

## 7. 未完成 / 风险

| # | 缺口 | 影响 | 归属 |
|---|---|---|---|
| G4-1 | trait/impl 的单态化/字典与 `ref[Trait]` 动态分派 | M3 完整、T4a | S0′/S1 |
| G4-2 | 闭包捕获与逃逸（E12） | F0 之外；T1 | S1 |
| G4-3 | `defer`/`#[must_release]` 脱糖（E8） | 泄漏/UB-14 | `resource.md` |
| G4-4 | `comptime` 求值器与 fuel（E17） | `E-LS-COMPTIME` | S0′ |
| G4-5 | 泛型单态化与区域多态 | M3/T1a | S1 |
| G4-6 | `for` 的 Iterator 协议细节（E7） | 语法/语义边界 | S0′ |
| G4-7 | `#[boundary]` 跨 profile 的 trampoline/效果并集 | T4c/Q4 | `cap-context.md` |
| G4-8 | 位域/tuple struct 布局与 ABI | `image.md`/FFI | S1 |
| G4-9 | 每个产生式的**可执行** elaborator | G4 仍为纸面合同 | `ls-sem` |

---

## 8. 验证

- `tests/syntax/run.py`：14 个 00 §5 片段（经测试归一化）+ 72 个 B-LS 测试 = 86/86；
- `tests/syntax/gbnf_diff.py`：EBNF→GBNF golden diff；生成结果必须等于
  `spec/langSysQuanta.gbnf`；
- 本文件的产生式归属表覆盖 EBNF v2.2 的 117 个产生式；
- **尚未实现**：`ls-sem` elaborator、GBNF 引擎解码差分、trait/闭包/`defer`/`comptime` 脱糖。

---

## 9. 变更规则

- 新增/删除 surface 产生式 ⇒ 同步本文件 §3、EBNF 与 `tests/syntax`；
- 新增脱糖规则 ⇒ 必须说明目标 core 构造/片段；不得引入未在 `semantics.md` 定义的动态语义；
- 修改 GBNF 生成器 ⇒ 重新生成 `spec/langSysQuanta.gbnf` 并跑 `gbnf_diff.py`；
- 本文件状态升级到 `冻结` 前，必须满足 §7 的 G4-1…G4-9（或明确登记为 out-of-scope）。
