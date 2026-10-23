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
> **B3-2a（2026-10-23）**：`Buffer[Int]` 运行时布局为 arena 中的
> `header{data_off,len,cap}` + data；内置 `buffer_new/len/cap/push/get`；push 满/ get 越界
> 返回 `-1`。源码级 `Buffer[Int]` / `Buffer.new` / `.len` / `.push` 语法与 `try_new`
> 仍未实现（B3-2b/B3-3），见 [`results/B3-buffer.md`](../results/B3-buffer.md)。

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
| 内存 | 1 MiB arena bump；`arena_alloc/arena_used/arena_budget/arena_reset`；`Buffer[Int]` 运行态 `buffer_new/len/cap/push/get`；失败返回 `-1`（B3-1/B3-2a） |
| 引用 | `u32` 索引，不用 `ref` |
| 容器 | `VecU8`/`VecU32`/`VecPtr`（单态） |
| 字符串 | `Slice[U8]`，字节 |
| 错误 | `ErrorCode` + 全局 `last_error` |
| 入口 | `main`；M0 固定签名 |
| I/O | raw syscall（Linux）；Windows 仅开发宿主 |

---

## 5. 与 L-Sys 的关系

- B-LS 是 L-Sys 的子集：语法一致、语义一致；不得出现 L-Sys 没有的写法。
- B-LS 对 region/mode/cap/effect 只做有限的入口检查：B2 已做 region 活跃重名、`val` 按值参数与 Int 词法作用域；
  完整所有权/生命周期/`ref` 仍由后续阶段实现。
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

- 两者都只保证“稳定诊断 + 非零退出码”，不承诺 L-Sys 的语义检查；
- 新增 B-LS 专属码必须先加到此表，再在 `names_stage.ls` 中落地。

---

## 6. 变更规则

1. 新增 B-LS 特性必须：① 在 L-Sys 中存在；② 有 seed 支持计划；③ 有黄金测试。
2. 不得为 bootstrap 方便引入 L-Sys 没有的语法/语义（否则就是第二门语言）。
3. 每加一个特性，必须保持 `stage1 == stage2` 固定点。
4. B-LS 的删减（为了缩小 seed）必须记录在 `05 §9` 的风险表。

---

## 7. 当前实现状态

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
| B3-2a（Buffer[Int] 运行态） | ✅ 2026-10-23；`results/B3-buffer.md` |
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
| M1d 固定点 | ⬜ 未开始 |
