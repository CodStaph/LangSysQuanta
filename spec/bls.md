# spec/bls.md · B-LS（Bootstrap L-Sys）子集规范

> **状态**：`草稿`，M0 已实现；M1+ 待扩展。
> **上位**：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md)、
> [`00 §5`](../00-LangSysQuanta-设计初稿.md)。
> **定位**：B-LS 是 L-Sys 的**严格子集**，只用于 bootstrap；不是第二门语言，不引入新语义。

---

## 1. 设计原则

| # | 原则 |
|---|---|
| B1 | B-LS 的每个程序都是合法 L-Sys（子集关系，语法/语义一致） |
| B2 | 不要求 region 推断；编译器自身用 arena + `u32` 索引 |
| B3 | 允许 `rawptr`/`unsafe`（编译器是 TCB，内部使用；审计） |
| B4 | 不要求泛型/trait/闭包；用单态容器 + 函数指针 |
| B5 | 整程序编译；第一阶段不产生 `.o`，不需要链接器 |
| B6 | 确定性：同一输入 → 逐位相同的 ELF |

> B-LS 的「安全」不是用户代码的安全承诺；编译器自身可以 unsafe，
> 但必须小、可审计、可复现（`02 ADR-2/29`）。

---

## 2. M0（已实现）

### 2.1 语法

```ebnf
Program   = Fn ;
Fn        = 'fn' 'main' '(' ')' '->' 'Int' '{' { Stmt } '}' ;
Stmt      = Write | Return ;
Write     = 'write' '(' String ')' ';' ;
Return    = 'return' Number ';' ;
String    = '"' { Char | '\\' Escape } '"' ;
Number    = digit { digit } ;
```

### 2.2 语义

- `write(s)`：`write(2)` 到 fd 1，返回字节数；忽略返回值；
- `return n`：`exit(2)`，退出码 `n & 0xff`；
- 无 `return` 时退出码 0；
- 字符串是 UTF-8 字节序列；`write` 原样输出字节，不转码、不校验。

### 2.3 编码、Unicode 与位置

| 项 | 约定 |
|---|---|
| 源文件 | 必须是合法 UTF-8 字节序列；非法 UTF-8 在输入边界报错（UTF-8，无 BOM） |
| 标识符 | ASCII `A-Z a-z 0-9 _`，以及非 ASCII Unicode 标量值（当前 seed 采用宽松规则，不要求完整 XID） |
| 字符串 | UTF-8 字节序列；`Slice[U8]`，不做规范化，`write` 原样输出 |
| 字符串 `.len` | **字符数**（Unicode 标量值，code point）；`"你好".len == 2` |
| `Slice[U8].len` | **字节数**（UTF-8 码元数）；用于字节缓冲/编码视图，不等于字符数 |
| 错误位置 | 1 基行号 + 1 基**字符**列；按 Unicode 标量值计数（code point，不是 grapheme cluster，也不是字节偏移） |
| 转义 | `\n`、`\t`、`\`、`\"`；暂不支持 `\u`/`\x` |

> 示例：`"你好".len` 是 2（2 个字符）；其 UTF-8 编码占 6 字节，`Slice[U8].len` 才是 6。
> 组合字符序列（如 `e` + U+0301）按 2 个字符计数；该规范面向标量值，不做 grapheme 分割。
> seed 与 stage1 均已实现一般 `Str` 值、`.len`、`write` 与 `read_file`/`write_file` 的 `Str` 路径。

#### 2.3.1 `Str` 值

B-LS 引入一般字符串值 `Str`（不可变 UTF-8 视图）：

```ls
let s = "你好";          // 推导为 Str
let t: Str = s;          // 复制 Str 视图
t = "再见";              // 重新绑定
fn f(x: Str) -> Int { return x.len; }
write(s);                // 写字符串值
read_file(s, buf, 4096); // 路径可以是 Str
```

- 运行期表示：`(base, byte_len, char_len)`，共 24 字节；
- `.len` 返回 `char_len`，按 Unicode 标量值计数；`"你好".len == 2`；
- `write(Str)` 写出 `byte_len` 个 UTF-8 字节；
- `read_file`/`write_file` 的路径参数可以是 `Str`（或 `Slice[U8]`、字面量）；
- `Str` 参数占 3 个寄存器槽（base、byte_len、char_len）；
- 字符串字面量存储于数据段；`Str` 变量/参数引用该字节序列；
- 当前限制：`Str` 不可变、不可索引、不可切片、不可比较、不可返回；不做 NFC/NFD 规范化；
- stage1 已实现 `Str` 变量/复制/参数/`.len`/`write` 与 `Str` I/O 路径。

### 2.4 代码生成（x86_64 Linux）

```text
mov eax, 1        ; write
mov edi, 1        ; stdout
lea rsi, [rip+disp]
mov edx, len
syscall

mov eax, 60       ; exit
mov edi, n
syscall
```

ELF：`ET_EXEC`，`EM_X86_64`，单一 `PT_LOAD`（R|W|X；变量与数据同段），entry = `0x400000 + 120`。
不使用 libc/as/ld。

### 2.5 测试

```ls
fn main() -> Int {
    write("hello from L-Sys bootstrap\n");
    return 0;
}
```

位置：`bootstrap/bls/tests/hello.ls`。

---

## 3. M1a（已实现）与 M1b（计划）

### 3.1 M1a 已实现

| 特性 | 形式 |
|---|---|
| 变量 | `let x = expr;`、`x = expr;` |
| 控制流 | `if`/`else`、`while`（无 `break`/`continue`） |
| 运算 | `+ - * / %`、`== != < <= > >=`、括号、一元 `-` |
| 字符串 | `write("...")` 字面量 |
| 返回 | `return expr;` |

测试：`bootstrap/bls/tests/hello.ls`、`calc.ls`。

### 3.2 M1b 计划

| 特性 | 形式 |
|---|---|
| 结构体 | `struct Node { next: Option[USize], value: Int }` |
| 枚举 | `enum Option[T] { Some(T), None }`（B-LS 可先单态） |
| 数组/切片 | `Array[T, N]`、`Slice[T]` |
| 函数 | 已在 M1b-2 实现（Int 参数/返回） |
| 字符串表 | 多个字面量/全局数据 |
| 文件 I/O | `read_file`/`write_file` 内置（stage1 需要） |

### 3.3 明确不支持（M1a/M1b）

- `val`/`ref`/region 推断；
- 泛型/trait/闭包/`match`（可先用 `if` + tag）；
- 契约/效果/`comptime`；
- 宏/turbofish；
- 多文件/包管理。

> 编译器**检查**这些特性是后续阶段的事；B-LS 自身不使用它们。

> **B2（2026-10-23）**：`region` 已做**活跃重名**检查；`val name: T` 作为按值参数接受，
> 且对 `val` 绑定的赋值会报 `val binding is immutable`；Int `let` 已支持 block
> 词法作用域、遮蔽与越界检查。`ref` 仍报 `E-LS-UNSUPPORTED`；Slice/Str/Array 变量
> 作用域、region 生命周期/逃逸、所有权仍未实现。详见
> [`results/B2-scope.md`](../results/B2-scope.md)。

> **B3-1（2026-10-23）**：运行时 arena 提供 `arena_alloc(n)`（8 字节对齐，成功返回相对 base
> 的偏移，失败 `-1`）、`arena_used()`、`arena_budget()`，并与 `arena_reset()`/`Str +` 共享
> 同一 1 MiB bump 区。见 [`results/B3-arena.md`](../results/B3-arena.md)。
>
> **B3-2（2026-10-23）**：`Buffer[Int]` 运行时布局为 arena 中的
> `header{data_off,len,cap}` + data（B3-4c 起为 `{data_off,len,cap,owner}`，32 B）；
> 内置 `buffer_new/len/cap/push/get`；push 满/ get 越界返回 `-1`。surface 支持
> `let b: Buffer[Int] = Buffer.new[Int](cap, rgn);` 与 `b.len`/`b.cap`/`b.push(v)`；
> `Buffer.new` 仅允许在 typed let 初始化器中。`b[i]`/`release`/`drop`/region 所有权见下。
> [`results/B3-buffer.md`](../results/B3-buffer.md)。
>
> **B3-3（2026-10-23）**：`Buffer.try_new[Int](cap, rgn)` 返回
> `Result[Buffer[Int], Int]`：成功 `Ok(handle)`、失败 `Err(-1)`（失败不推进 arena）；
> 仅允许出现在 `let r: Result[Buffer[Int], Int] = ...` 初始化器中，`Result.Ok(b)` 的
> 绑定保留 `Buffer[Int]` 类型。见 [`results/B3-buffer.md`](../results/B3-buffer.md)。
>
> **B3-4a（2026-10-23）**：`b[i]` 读取索引映射到 `buffer_get`（越界返回 `-1`）；`b[i] = v`
> 写入仍报 `E-LS-UNSUPPORTED`。顺带修正 B3-2a 遗留的 `buffer_push` ModRM：push 曾把
> arena base 当 header，只有 handle = 0 时碰巧正确。见
> [`results/B3-buffer.md`](../results/B3-buffer.md)。
>
> **B3-4b（2026-10-23）**：`b.release()` / `drop b;` 映射到 `buffer_release`，只做 **LIFO**：
> 当分配正好是 arena 栈顶（`base + handle + 32 + cap*8 == current`）时回退 `current`
> 并返回 `0`，否则返回 `-1` 且不改 arena；`drop` 仅限 `Buffer[Int]`。见
> [`results/B3-buffer.md`](../results/B3-buffer.md)。
>
> **B3-4c（2026-10-23）**：Buffer header 升级为 32 B（+`owner`）；`region` 变成运行时帧
> （进入记 mark、生成唯一 owner 序号，退出回退 arena），region 内的分配随退出自动回收；
> `release`/`drop` 要求 owner 与当前 region 一致（跨 region 返回 `-1`）。逃逸路径在编译期
> 拒绝：Buffer 句柄赋值、跳出 region 的 `break`/`continue`（`E-LS-UNSUPPORTED`）。
> region 参数名仍不参与运行时。见 [`results/B3-buffer.md`](../results/B3-buffer.md)。
>
> **B3-5（2026-10-23）**：① `b[i] = v` 映射到 `buffer_set`（`0 <= i < len`；越界返回 `-1`
> 且不写入；仅语句形式，值/索引必须是 `Int`/`U8`）。② 新增类型码 10 `AllocError`，
> `Buffer.try_new` 接受 `Result[Buffer[Int], Int|AllocError]`（错误码仍是 `-1`，
> `AllocError` 暂无构造器/常量）。③ `-> Int` 函数在 region 内 `return` 会先按编译期深度
> unwind region 帧（`depth--` + 回退 `mark`）再返回；返回类型可能携带 Buffer 时仍报
> `E-LS-UNSUPPORTED`。见 [`results/B3-buffer.md`](../results/B3-buffer.md)。
>
> **R4.3（2026-10-23）**：`Str +` / `concat_into` / `append_into` 的预算/容量不足不再
> `exit(70/71)`：`str_try_concat(a, b)` 返回 `Result[Str, AllocError]`，
> `concat_into`/`append_into` 返回 `Result[Slice[T], AllocError]`（失败时不写目标 slice）；
> 泛型 `T + T` 仍是 `T`（失败得到空 `Str`，不 trap），直接 `Str/Slice + ` 报
> `E-LS-UNSUPPORTED`。源码上限 327680→393216（`membuf` 1507328）。对齐统一/通用回收仍是
> R4.2/R4.4。见 [`results/R4.3-str-failure.md`](../results/R4.3-str-failure.md)。
>
> **R4.2/R4.4（2026-10-23）**：arena 元数据扩为 `{base,current,end,high_water,allocs,rejects,reclaims}`
> （56 B）；**所有分配（含 `Str +`）统一 8 字节对齐**；成功/失败/回收分别更新 `allocs`/`rejects`/`reclaims`，
> 并提供 `arena_stat(0..3)`（`high_water`/`allocs`/`rejects`/`reclaims`）。新增 `region_used()`
> （`current - 最内层 region mark`，root 时 = `current-base`）；动态 cap 的 Buffer 由运行时表达式决定。
> region 仍共享同一 1 MiB 预算（无按 region 的硬配额），无通用 `free`。见
> [`results/R4.2-r4.4-arena.md`](../results/R4.2-r4.4-arena.md)。
>
> **R4.4/R4.5（2026-10-23）**：新增 `arena_mark()` / `arena_rewind(m)`——回退到 mark 并释放其上的
> 所有分配（`reclaims` 计数，保留 `high_water`），成功 `0`、越界或在最内层 region mark 之下返回 `-1`。
> R4.5 补齐分配失败回归：`Str`/`Buffer`/`arena_alloc`/`concat_into` 失败路径、`?` 传播 `AllocError`；
> `parse_index` 改用变量真实类型，`Result`/`Option` 变量也可作为 `?` 操作数。通用 `free`、碎片整理、
> 按 region 的硬配额仍不支持（bump arena）。见 [`results/R4.4-r4.5-reclaim.md`](../results/R4.4-r4.5-reclaim.md)。
>
> **R4.6（2026-10-23）**：arena 增加**空闲块表**：`arena_alloc`/Buffer 分配先 first-fit 复用空洞（可切分）；
> `b.release()`/`drop` 改为**任意顺序**释放（栈顶仍回退 `current`，非栈顶进空闲表），新增
> `arena_free(off, size)` 与 `arena_coalesce()`；释放时合并相邻空洞（`arena_reset`/`arena_rewind`/region
> 退出 purge 掉 mark 之上的空洞）。`arena_used()` 仍是 bump 上界。**不移动活对象**（无压缩/整理),
> 空闲表 64 项。见 [`results/R4.6-free.md`](../results/R4.6-free.md)。
>
> **R4.7（2026-10-24）**：① **Buffer 句柄表**（`handle -> {off,size}`，128 槽，`post[17040]`）：
> `Buffer.new`/`try_new` 成功后登记，所有 Buffer 操作先解析 handle；`release`/`drop` 成功使槽失效
> （重复释放返回 `-1`）；`Buffer.try_new` 的 Ok 载荷改为真正的 handle。② **移动式压缩**
> `arena_compact()`：把活 Buffer 块搬进其下方的空闲洞并改写表项/header，旧位置回到空闲表，
> 尾部空洞下调 `current`；`Str`/裸 `arena_alloc` 块 pinned。③ **region 硬配额**
> `region R(cap) { ... }`：进入时保存 `end` 到 `lim[depth]` 并临时把 `end` 设为
> `clamp(mark+cap, mark, 父 end)`，退出/`return` 恢复；`Buffer`/`arena_alloc`/`Str +` 等原有
> `[end]` 检查因此自动受限；新增 `region_limit()`（有效 `end - 最内层 mark`）。
> ④ `return` 的表达式改为**先求值再 unwind**；`arena_rewind`/region 退出/`return` 会用
> `buf_hpurge` 清掉 mark 之上的 handle，`arena_reset` 清空 handle 表。
> 见 [`results/R4.7-handle-quota.md`](../results/R4.7-handle-quota.md)。
>
> **B4（2026-10-25）**：多类型参数泛型与约束。`[A, B]`（最多 2 个）用于泛型函数/enum；
> 约束 `A: Ord/Eq/Num/Add`（内联或 `where`）在调用点检查，并支持从外层泛型函数**转发**；
> 调用点按参数位置统一类型，泛型返回取统一后的实际类型。运行期仍为统一装箱 + typecode
> 分派；泛型转发参数不二次装箱，泛型函数间转发返回值保持 box。`scan_sigs` 预扫描函数签名
> （`post[132000..135711]`），使 forward call 可用；`parse_ty`/`scan_generic_list` 收敛到
> 6 个参数槽（B-LS ABI 上限）。不做泛型 struct、>2 参数、enum 参数约束、trait/关联类型、
> 显式 turbofish。见 [`results/B4-generics.md`](../results/B4-generics.md)。
>
> **B5-1（2026-10-25）**：`ref x: Int` 形参（临时可变借用）。调用点接受**单个可变 Int 变量**，
> 取其槽地址传入；callee 内类型 `Ref Int`（变量类型 11）经 `kind 76` 解引用，赋值写穿 caller；
> 字面量/表达式/数组元素/结构字段/`val` 绑定、同一调用重复借用同一变量、ref→ref 转发、
> 非 Int 的 ref、泛型函数中的 ref 均编译期拒绝。`scan_refmask` 记录参数 ref 位，
> 调用点按源码名 span 解析 mask（不依赖 name id）；顺带修复 `check_decls`
> 未设置 `nsts[0]/[1]` 导致的 arity 表只对 id 0 有效的旧问题。
> 不做引用类型值、`val`/`ref` 字段、生命周期/逃逸分析（借用只在调用期间存在）。
> 见 [`results/B5-1-ref.md`](../results/B5-1-ref.md)。
>
> **B5-2（2026-10-25）**：`ref` 扩展到 `Str`、`Slice[U8]`、`Slice[Int]` 的**只读视图**，
> 并支持 `ref` 转发：`ref Str` 读指针+3 槽（kind 77）、`ref Slice` 读指针+2 槽（kind 78），
> `.len` 用 kind 79/80；普通 Str/Slice 作为 ref 实参时取 Str/Slice 槽地址（kind 81/82），
> ref 变量转发用 kind 75。同一调用重复借用、val、字面量/表达式、类型不匹配仍拒绝；
> `ref Buffer`、通过 ref 写 Str/Slice、`ref_slice[i]`、引用类型值/字段/返回、
> 生命周期/逃逸分析仍未做。stage1 自编译的语句 AST 超限，`sast` 扩到 100000 ints、
> `ctxi` 移到 241024、重定位补丁表移到 248000、`post` 扩到 360000。
> 见 [`results/B5-2-ref-views.md`](../results/B5-2-ref-views.md)。
>
> **B5-3（2026-10-25）**：`ref b: Buffer[Int]`（类型 15）：形参保存 caller handle 槽地址，
> `.len/.cap/.push/b[i]/b[i]=/release` 经 `push_handle` 解引用后走既有 Buffer 运行时；
> ref 转发支持 Buffer（kind 75）。`ref Slice` 增加索引读取（post kind 83/84）。
> 仍不支持 Str/Slice ref 写入、`ref Str[i]`、`drop` ref Buffer、引用类型值/字段/返回、
> 生命周期/逃逸分析；`ref Buffer.release()` 会使 caller 的 handle 失效。
> 见 [`results/B5-3-ref-buffer.md`](../results/B5-3-ref-buffer.md)。
>
> **B5-4（2026-10-25）**：`ref Str` 赋值（字符串字面量或 Str 表达式）写穿 caller 的
> Str 三槽；`ref Str[i]` 读取 UTF-8 字节（post kind 85，返回 U8）。仍不支持
> `ref Slice` 赋值/写入、引用类型值/字段/返回、生命周期/逃逸分析、`ref Buffer` 赋值。
> 见 [`results/B5-4-ref-write.md`](../results/B5-4-ref-write.md)。
>
> **B5-5（2026-10-25）**：`ref Slice[U8/Int]` 支持描述符赋值（`s = t`，写穿 base/len）
> 与索引写入（`s[i] = v`，U8/Int）；值类型不匹配拒绝。仍不支持 `ref Str[i] = v`、
> 引用类型值/字段/返回、生命周期/逃逸分析、`ref Buffer` 赋值。
> 见 [`results/B5-5-ref-slice-write.md`](../results/B5-5-ref-slice-write.md)。
>
> **B5-6（2026-10-25）**：`ref[T]` 局部值（`let r: ref[T] = 普通变量/ref/返回 ref 的调用`）
> 与 `-> ref[T]` 返回（return 只接受单个同类型 ref 变量）。新增 `parse_ref_ty`
> （Int/Str/Slice/Buffer → 11..15）；ref 局部按来源取址/复制指针；返回 ref 用 kind 75。
> ref struct 字段显式拒绝；不做生命周期/逃逸静态分析，`r = other_ref` 仍解释为写穿目标。
> 见 [`results/B5-6-ref-values.md`](../results/B5-6-ref-values.md)。
>
> **B5-7（2026-10-25）**：struct 支持 `ref[Int/Str/Slice/Buffer]` 字段（8 字节指针），
> 字段读取得到 ref 值（需绑定到 ref 局部后解引用；直接运算 `E-LS-UNSUPPORTED`）；
> 字段赋值支持 ref 变量/普通变量取址/返回 ref 的调用。`let r: ref[Int] = Array[Int][i]`
> 通过 kind 86 取元素地址。附带修复 typed let 的 Option/Result/Str/Slice 前缀误判
> （现在要求完整关键字 + kw_end）。Array[U8]/Slice 元素取 ref、引用作为数组元素/泛型负载、
> 生命周期/逃逸分析仍未做。见 [`results/B5-7-ref-fields.md`](../results/B5-7-ref-fields.md)。
>
> **B5-8（2026-10-26）**：`ref` 的**来源寿命跟踪 + 逃逸静态检查**（`spec/modes.md` R4 的
> 局部可判定版本）。每个 ref 值记录 `(origin, send)`：`origin 0` = `ref` 形参的 reborrow
> （寿命无限，可返回/可存字段），`origin 1` = 本地槽地址（寿命 = 作用域 `send`）。
> 记录在 `post[136000 + vi]`（容量 4000，0 = 未知 ⇒ 按最保守处理），
> 调用返回 ref 的寿命由 `ref` 实参 `join` 到 `post[135802]`（取最保守）；
> struct 变量表把 `send` 打包进偏移高位（`off | send << 31`，因 6 参数槽限制）。
> 两条拒绝：`return` 本地 ref、把本地 ref 存进更长寿命的 `struct` 字段
> （`E-LS-REGION-ESCAPE`）。同块/内层块内的本地 ref、形参 reborrow 放行。
> 不做区域推断/并查集、`val`/`box` 所有权、泛型 ref 负载。
> 见 [`results/B5-8-escape.md`](../results/B5-8-escape.md)。
>
> **B5-9（2026-10-26）**：`ref` 作为**数组元素**与**泛型负载**。`Array[ref[Int|Str|Slice|Buffer], N]`
> 元素 8 字节指针，`a[i]` 读出 ref 值（与 `Array[Int]` 的取地址路径区分），
> `a[i] = <ref>` 做逃逸检查（`E-LS-REGION-ESCAPE: ... longer-lived array`）；
> `parse_ty` 接受 `ref[T]`，因此 `Option[ref[T]]`/`Result[ref[T], E]` 可注解、构造、
> `match`（绑定保留 ref 类型）与 `?` 解箱；`push_var_expect` 用 payload 期望类型
> （`st[10]`/`st[11]`）把 ref 变量读成指针。arr 表增加第 3 字段 `send`（`4097 + i*3`，
> send 经 `post[135810]` 传入以保持 `add_arr` 3 参数）；寿命规则沿用 B5-8
> （数组元素读 = origin 1 / send = 数组声明作用域，写入检查 `send(ref) >= send(array)`）。
> `Slice` of ref 元素、泛型函数 `f[T]` 的 ref 实参仍不支持。
> 见 [`results/B5-9-ref-aggregate.md`](../results/B5-9-ref-aggregate.md)。
>
> **B5-10（2026-10-27）**：**effect / cap / mode 三项接入**。① `eff(read, write, alloc, io,
> panic, spawn, unsafe, pure)` 解析为位掩码（首字母大小写不敏感），`eff(pure)` = 空集；
> 声明了 `eff` 的函数其体内**边界效果**（alloc/panic/spawn/unsafe）必须 ⊆ 声明
> （`E-LS-EFFECT`），调用声明了 `eff` 的 callee 时 caller 必须覆盖（强制传播），
> 内部效果（read/write/io）可推断。内置映射：`read_file/write_file/argc/arg_*/write` → io、
> `Buffer.new/try_new/arena_alloc/str_try_concat/*_into/arena_compact` → alloc、
> `buffer_push/b[i]=v/release/drop` → write、`b.len/cap/get`/`arena_*`/`region_*` → read。
> ② `Cap[Alloc|Io|Unsafe|Spawn|…]` 形参与局部令牌（`let c: Cap[Alloc] = 0;`，8 字节占位）；
> 声明 `alloc`/`unsafe` 需要对应 Cap 形参（`E-LS-CAP`）。`main` 是入口，豁免三项检查。
> ③ `let val x = ...` 冻结局部（meta val 位），再赋值 → `val binding is immutable`，
> 传 `ref` 形参 → `ref argument cannot be a val binding`。表：`post[131700+fi]` 声明效果、
> `post[131830+fi]` Cap、`post[131960]` 产出效果、`post[17008]` main 标志。
> 不做模块 `#[cap]`、`iso/box/freeze/recover` move 语义、效果多态、契约。
> 见 [`results/B5-10-effects.md`](../results/B5-10-effects.md)。
>
> **B5-11（2026-10-28）**：**契约 + 非空 `comptime`**。① `requires <expr>` 在函数**入口**
> 断言（形参就绪后），为假 `exit(73)`；`ensures <expr>` 在**每个 `return` 前**断言，
> `result` 指代返回值，为假 `exit(74)`。子句表达式 span 记录于 `post[135741..135744]`，
> `result` 用新 post kind 87（`mov rax,[result_slot]`，槽在 `post[135746]`）；
> 只支持无条件形式，`=> expr` 与 `old(expr)` 未实现。② `comptime { <const-expr>; }`
> 编译期折叠（字面量 + 算术/比较/逻辑/位运算/一元负，局部值栈 `cstk[32]`）：
> 结果为 0 → `E-LS-COMPTIME: comptime assertion failed`；非常量（变量/调用/索引）→
> `E-LS-COMPTIME: ... needs a constant expression`；块内其他语句仍 `E-LS-UNSUPPORTED`。
> ③ **容量**：新增代码把语句 AST 推到 16400 上限，`sast` 扩为 `post[141024..245023]`
> （104000 ints，**17200 节点**守卫），`ctxi` 移到 `post[245024..247135]`（重定位表仍在
> `248000`，余 864）。不做契约静态证明、`comptime` 表达式形式与 fuel。
> 见 [`results/B5-11-contracts-comptime.md`](../results/B5-11-contracts-comptime.md)。
>
> **B5-12（2026-10-29）**：**struct 作为泛型负载 + 内置 `Error`**。① 类型码 `30 + si`
> （`si < 70`）表示用户 struct（要求 `st_size` 为 8 的倍数，即全 `Int`/`ref[...]` 字段）：
> `Option[Code]`/`Result[Point, Error]` 可注解；ctor 的 payload 按**每字段一项**
> `push_post(12, off)` 打包并重标为 struct 类型，`kind 27` 按 `st_size/8` 槽复制；
> `match` 绑定用 `sv_add` 建 struct 变量并逐槽复制；struct 值参与运算报
> `E-LS-UNSUPPORTED: struct value must be used through its fields`。
> ② 内置 `Error`（类型码 20，紧凑 Copy tag）：`Error.Full/NotFound/InvalidCap/OutOfMemory`
> = 1/2/3/4，在 `parse_expr` 与 `parse_index` 两条路径都可作常量；`Result[T, Error]` 的
> `Err` payload 1 槽。不做 `?` 传播 struct、struct 参数/返回值、U8 字段/嵌套 struct 负载、
> `Error` 的 `From`/错误域/格式化。见 [`results/B5-12-struct-error.md`](../results/B5-12-struct-error.md)。
>
> **R3.6（2026-10-30）**：**结构化诊断 + fix-it（B-LS/stage1）**。`names_stage.ls` 的
> 5 类规则诊断（`E-LS-ARITY`×2、`E-LS-CAP`、`E-LS-EFFECT`×2、`E-LS-COMPTIME`×2、
> `E-LS-REGION-ESCAPE`×3，共 10 站点）升级为两行机读结构：
> `stage1: <码>: <line>:<col>: <原文本>` + `  fix-it: <建议>`；列按 Unicode 标量值计数
> （UTF-8 续字节不推进）；诊断码与原消息**逐字保留**，既有 grep 断言不变。动态片段
> （期望/实际参数个数、缺失效果名、缺失 Cap 令牌名）由新单函数
> `diag_pos(src, off, mode)`（mode 0 = 位置，mode 1 = 十进制数字）分段 `write` 输出；
> seed `MAX_FUNCS = 128` 与原 127 个函数决定**只能新增 1 个顶层函数**（现恰 128）。
> fix-it 遵循 `modes.md` §5 顺序（缩作用域→复制→ref 参数），不建议 unsafe（LS-P17）。
> 新测试 `reject/diag_location.ls`（两位行号 + CJK 码点列 19，字节计数会误报 27）
> 与 CI R3.6 断言段。38 处 `E-LS-UNSUPPORTED` 不在本次范围。锚点精度分级
> （COMPTIME 语句 span 精确；数组/字段站点用发射游标近似）见
> [`results/R3.6-structured-diag.md`](../results/R3.6-structured-diag.md)。

---

## 3.4 M1c 前置（stage1 需要）

- 函数参数支持 `Slice[U8]` 或显式 `(ptr,len)`；
- `&&`/`||`、位运算、`break`/`continue`；
- `enum` 负载 + `match`（至少 tag 分支）；
- `argv` 或动态路径；
- `seed --run` 解释器（本地调试）：已实现，见 `05 §14`。

## 4. 编译器自身的编码约定

| 项 | 约定 |
|---|---|
| 内存 | 1 MiB arena bump；`arena_alloc/arena_used/arena_budget/arena_reset/arena_stat/arena_mark/arena_rewind/arena_free/arena_coalesce/arena_compact` + `region_used/region_limit`；`Buffer[Int]` 运行态 `buffer_new/len/cap/push/get` + surface `Buffer.new/.len/.cap/.push`/`b[i]` 读与写/`b.release()`/`drop`；Buffer 句柄表（128 槽）+ 移动式压缩；`region r(cap)` 硬配额（有效 `end`）；`Buffer.try_new` → `Result[Buffer[Int], Int|AllocError]`；`str_try_concat` → `Result[Str, AllocError]`、`concat_into`/`append_into` → `Result[Slice[T], AllocError]`；`region` 运行时帧 + owner 校验 + `-> Int` return unwinding（先求值再 unwind）；失败/越界/重复释放/跨 region/配额或预算不足均以 `-1`/`Err` 返回（B3-1…B3-5、R4.3、R4.7） |
| 引用 | `u32` 索引，不用 `ref` |
| 容器 | `VecU8`/`VecU32`/`VecPtr`（单态） |
| 字符串 | `Slice[U8]`，字节 |
| 错误 | `ErrorCode` + 全局 `last_error` |
| 入口 | `main`；M0 固定签名 |
| I/O | raw syscall（Linux）；Windows 仅开发宿主 |

---

## 5. 与 L-Sys 的关系

- B-LS 是 L-Sys 的子集：语法一致、语义一致；不得出现 L-Sys 没有的写法。
- B-LS 对 region/mode/cap/effect 只做有限的入口检查：B2 已做 region 活跃重名、
  `val` 按值参数与 Int 词法作用域；B5-1/B5-2/B5-3 已做 `ref Int/Str/Slice/Buffer`
  的调用期借用（Str/Slice/Buffer 可读写，Slice/Str 可索引；ref 局部/返回/字段/Int 数组元素
  已接入）；B5-8 增加 `ref` 来源寿命跟踪与两条逃逸拒绝（返回本地 ref、存进更长寿命字段，
  `E-LS-REGION-ESCAPE`），但仍是块级近似、不做区域推断；B3-4c/B3-5c 已做 region 运行时帧、
  Buffer owner、逃逸拒绝与 `-> Int` return unwinding；R4.7 增加 `region r(cap)` 硬配额与
  句柄表压缩。完整所有权（`val`/`box`/`iso`）与 `mode`/cap/effect 仍由后续阶段实现。
- 当 B-LS 扩展时，必须同步 `spec/langSysQuanta.ebnf` 与 00 的对应章节。
- B-LS 的 `unsafe` 使用必须列入 `tools/checker-spike` 或 `bootstrap` 的审计清单。

### 5.1 B-LS 诊断码（实现状态）

> 这些码**不是** L-Sys 语言诊断（[`diagnostics.md`](diagnostics.md)）的一部分，而是 B-LS 工具链的
> “入口约束 / 实现进度”。登记在此，使 `tools/doc-lint` 能校验使用处。
> 语言级诊断（如 `E-LS-DUP`、`E-LS-ARITY`）仍登记在 [`diagnostics.md`](diagnostics.md)；
> B-LS 只是它们的第一批实现。

| 码 | 含义 | 触发点 | fix-it |
|---|---|---|---|
| `E-LS-UNSUPPORTED` | B-LS 已识别该语法，但语义尚未实现（B1：不得静默忽略） | `bootstrap/src/names_stage.ls` 的 B1 入口 | 改用 B-LS 子集 / 等待实现 |
| `E-LS-MAIN` | `main` 必须无参数且返回 `Int` | B-LS 入口检查 | 修正 `main` 签名 |
| `E-LS-REGION-ESCAPE` | `ref` 逃出其来源寿命（返回本地 ref / 存进更长寿命字段） | B5-8 逃逸检查 | 改为 reborrow `ref` 形参、缩短目标作用域或复制值 |

- 两者都只保证“稳定诊断 + 非零退出码”，不承诺 L-Sys 的语义检查；
- 新增 B-LS 专属码必须先加到此表，再在 `names_stage.ls` 中落地。

---

## 6. 变更规则

1. 新增 B-LS 特性必须：① 在 L-Sys 中存在；② 有 seed 支持计划；③ 有黄金测试。
2. 不得为 bootstrap 方便引入 L-Sys 没有的语法/语义（否则就是第二门语言）。
3. 每加一个特性，必须保持 `stage1 == stage2` 固定点。
4. B-LS 的删减（为了缩小 seed）必须记录在 `05 §9` 的风险表。

---

## 7. 当前实现状态（2026-10-24）

| 项 | 状态 |
|---|---|
| M0 seed（C） | ✅ 可构建；ELF 结构验证通过 |
| M0 `hello.ls` | ✅ 生成 ELF；Linux 执行由 CI 验证 |
| M1a（let/算术/if/while） | ✅ 已实现；`calc.ls` 生成 ELF |
| M1b-2（函数调用） | ✅ 已实现；`funcs.ls` |
| M1b-1（Array） | ✅ 已实现；`arrays.ls` |
| M1b-3a（enum 标签） | ✅ 已实现；`enums.ls` |
| M1b-3b（struct） | ✅ 已实现；`structs.ls` |
| M1b-3c（Slice） | ✅ 已实现；`slices.ls` |
| M1b-4（文件 I/O） | ✅ 已实现；`io.ls` |
| M1c-0e（解释器） | ✅ `seed --run`；`run-interp.sh` |
| B2（region 重名 + `val` + Int 词法作用域） | ✅ 2026-10-23；`results/B2-scope.md` |
| B3-1（arena 元数据/分配） | ✅ 2026-10-23；`results/B3-arena.md` |
| B3-2（Buffer[Int] 运行态 + surface） | ✅ 2026-10-23；`results/B3-buffer.md` |
| B3-3/B3-4/B3-5（try_new、索引读写、release/drop、region 所有权） | ✅ 2026-10-23；`results/B3-buffer.md` |
| R4.2/R4.3（arena 计量/对齐、Str/切片失败 → `Result`） | ✅ 2026-10-23；`results/R4.2-r4.4-arena.md`、`R4.3-str-failure.md` |
| R4.4/R4.5（mark/rewind、失败注入回归） | ✅ 2026-10-23；`results/R4.4-r4.5-reclaim.md` |
| R4.6（通用 free/空洞复用/合并） | ✅ 2026-10-23；`results/R4.6-free.md` |
| R4.7（Buffer 句柄表 + `arena_compact`、`region r(cap)` 硬配额） | ✅ 2026-10-24；`results/R4.7-handle-quota.md` |
| B4（多类型参数泛型/约束/统一） | ✅ 2026-10-25；`results/B4-generics.md` |
| B5-1（`ref x: Int` 临时借用） | ✅ 2026-10-25；`results/B5-1-ref.md` |
| B5-2（`ref Str/Slice` 只读视图 + 转发） | ✅ 2026-10-25；`results/B5-2-ref-views.md` |
| B5-3（`ref Buffer` + ref Slice 索引） | ✅ 2026-10-25；`results/B5-3-ref-buffer.md` |
| B5-4（`ref Str` 写入 + `ref Str[i]`） | ✅ 2026-10-25；`results/B5-4-ref-write.md` |
| B5-5（`ref Slice` 赋值 + 索引写入） | ✅ 2026-10-25；`results/B5-5-ref-slice-write.md` |
| B5-6（`ref[T]` 局部/返回；字段拒绝） | ✅ 2026-10-25；`results/B5-6-ref-values.md` |
| B5-7（ref 字段 + ref Int 数组元素） | ✅ 2026-10-25；`results/B5-7-ref-fields.md` |
| B5-8（`ref` 生命周期/逃逸静态检查） | ✅ 2026-10-26；`results/B5-8-escape.md` |
| B5-9（ref 数组元素 + 泛型负载） | ✅ 2026-10-26；`results/B5-9-ref-aggregate.md` |
| B5-10（`eff(...)` / `Cap[...]` / `let val`） | ✅ 2026-10-27；`results/B5-10-effects.md` |
| B5-11（`requires`/`ensures` + 非空 `comptime`） | ✅ 2026-10-28；`results/B5-11-contracts-comptime.md` |
| B5-12（struct 泛型负载 + 内置 `Error`） | ✅ 2026-10-29；`results/B5-12-struct-error.md` |
| R3.6（结构化诊断 + fix-it，B-LS/stage1） | ✅ 2026-10-30；`results/R3.6-structured-diag.md` |
| M1c-0a（Slice 参数） | ✅ `slice_params.ls` |
| M1c-0b（逻辑/位运算/break） | ✅ `ops.ls` |
| M1c-0c-1（tag-only match） | ✅ `match.ls` |
| M1c-0c-2（enum 负载 + 绑定） | ✅ `payload.ls` |
| M1c-0d-1（argv） | ✅ `argv.ls` |
| M1c-0d-2（动态路径） | ✅ `dynpath.ls` |
| M1c-1/2/3（stage1 hello） | ✅ `bootstrap/src/main.ls` |
| M1c-3b-1（arith stage1） | ✅ `bootstrap/src/arith.ls` |
| M1c-3b-2（calc stage1） | ✅ `bootstrap/src/calc.ls` |
| M1d-0a（多函数 stage1） | ✅ `bootstrap/src/funcs.ls` |
| M1d-0b（Array/Slice stage1） | ✅ `bootstrap/src/slice_stage.ls`；`stage1_slice.ls` 退出码 177 |
| M1d-0c（struct/enum stage1） | ✅ `bootstrap/src/struct_stage.ls`；`stage1_struct_enum.ls` 退出码 177 |
| M1d-0d（名字表 stage1） | ✅ `bootstrap/src/names_stage.ls`；`stage1_names.ls` 退出码 177 |
| M1d 固定点 | ✅ 2026-10-30 QEMU/TCG 全量 `stage2 == stage3`，`76c7cfe0…da72`（R3.6 后；需 `QEMU_TIMEOUT=7200`，QEMU 全程约 71 分钟，自编译产物 860322 B / 源码 518006 B） |

> AI生成
