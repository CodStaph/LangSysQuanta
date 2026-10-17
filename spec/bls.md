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
- 字符串按字节输出，不做 UTF-8 校验。

### 2.3 代码生成（x86_64 Linux）

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

ELF：`ET_EXEC`，`EM_X86_64`，单一 `PT_LOAD`（R|X），entry = `0x400000 + 120`。
不使用 libc/as/ld。

### 2.4 测试

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

---

## 4. 编译器自身的编码约定

| 项 | 约定 |
|---|---|
| 内存 | arena bump；不释放 |
| 引用 | `u32` 索引，不用 `ref` |
| 容器 | `VecU8`/`VecU32`/`VecPtr`（单态） |
| 字符串 | `Slice[U8]`，字节 |
| 错误 | `ErrorCode` + 全局 `last_error` |
| 入口 | `main`；M0 固定签名 |
| I/O | raw syscall（Linux）；Windows 仅开发宿主 |

---

## 5. 与 L-Sys 的关系

- B-LS 是 L-Sys 的子集：语法一致、语义一致；不得出现 L-Sys 没有的写法。
- B-LS 不承诺 region/mode/cap/effect 的检查；这些由 stage1 实现。
- 当 B-LS 扩展时，必须同步 `spec/langSysQuanta.ebnf` 与 00 的对应章节。
- B-LS 的 `unsafe` 使用必须列入 `tools/checker-spike` 或 `bootstrap` 的审计清单。

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
| M1b-3c（Slice）、M1b-4（文件 I/O） | ⬜ 未开始 |
| M1c stage1（B-LS） | ⬜ 未开始 |
| M1d 固定点 | ⬜ 未开始 |
