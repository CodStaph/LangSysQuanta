# bootstrap/src · stage1（B-LS）

**当前（2026-10-18）**：活跃 stage1 是 `names_stage.ls`（多字符名字表 + 内置 I/O + 控制流），
已通过 `stage1 -> stage2 -> stage3` 固定点（`stage2 == stage3`）。
`main.ls`/`arith.ls`/`calc.ls`/`funcs.ls`/`slice_stage.ls`/`struct_stage.ls` 是里程碑历史版本。

## 当前状态

| 项 | 状态 |
|---|---|
| stage1 自编译 → stage2 → stage3 | **已完成**；2026-10-23 本地 QEMU SHA-256 `52cced38…688e`（B3-3 Buffer.try_new 后） |
| Int 状态打包（B0.3b-1） | `main` 的 17 个 Int 数组合并为 `ctxi` 视图（`slice_at`）；`sts/css` 删除并改名 `st/cs`，行为不变 |
| 抽 `emit_body`（B0.3b-2） | 语句循环搬进 `emit_body(mem, ps, n)`；`src/code/data` 合并为 `membuf`，`nf/dlen/cd/nbrk` 进 `ctxi`；`main` 只剩输入/布局/ELF 收尾 |
| 语句 AST（B0.3c） | `scan_stmts` 建 6-int `sast`（post[141024..209023]，68000 ints）；`emit_stmt_list` 用显式 frame 发射 `if/while/break/continue`；叶子/`match` 走 `emit_stmt_span`；源码上限 327680 |
| region / `val` / 作用域（B2） | region 活跃重名检查；`val name: T` 按值绑定且赋值检查；Int `let` 支持 block 词法作用域/遮蔽/越界；`ref`、Slice/Str/Array 作用域、所有权未做 |
| arena（B3-1） | `arena_alloc/arena_used/arena_budget/arena_reset`；1 MiB bump、8 字节对齐、失败 `-1` |
| Buffer（B3-2） | 运行态 `buffer_new/len/cap/push/get` + surface `Buffer[Int]`/`Buffer.new`/`.len`/`.cap`/`.push`；`b[i]`/所有权未做 |
| `Buffer.try_new`（B3-3） | `Buffer.try_new[Int](cap, rgn)` → `Result[Buffer[Int], Int]`（成功 `Ok(handle)`，失败 `Err(-1)`，失败不推进 arena）；仅允许 `Result[Buffer[Int], Int]` 注解的 let 初始化器；`b[i]`/release/drop/所有权未做 |
| `slice_at`（B0.3a） | 支持（seed + stage1）：`let v: Slice[T] = slice_at(src, off, len);`，`off` 按元素计 |
| 前端 pass（B0.2） | `scan_funcs` → `check_decls` → `check_calls`（声明表 + body span；emit 仍单遍，见 `results/B0-frontend.md`） |
| 多字符/UTF-8 名字表 | 已实现（`names_stage.ls`） |
| 内置 I/O + argv 动态路径 | 已实现（`stage1_io.ls`） |
| 控制流 + `write` + 表达式实参 | 已实现（`stage1_control.ls`） |
| 一般 `Str` 值（变量/复制/参数/.len/write/I-O 路径） | **已实现** |
| 嵌套调用实参 | **已实现**（显式 call stack；`stage1_nested_call.ls`） |
| struct/Array/Slice 偏移 | **31 位**（`huge_offset.ls` 覆盖 300MB） |
| >256 MiB 数据布局 | **已实现**（31 位偏移；300MB `huge_offset.ls`） |
| Stage 2 `Option[T]`/`Result[T,E]`/`?` | **单态化已实现**（`Int`/`U8`/`Str`/`Slice[U8]`/`Slice[Int]`；构造、`match` 绑定、`?`） |
| 用户自定义泛型 `enum`/`fn`（统一装箱） | **已实现**；`T` 支持 `Int`/`U8`/`Str`/`Slice`；泛型函数体对 `T` 透传 |
| Stage 2 其余（val/ref/effect/契约/comptime/诊断） | **B-LS 未开始**；受限子集已在 `tools/ls-sem` surface checker 实现 |
| `Buffer[T]`/region/所有权、多参数泛型/约束、arena 预算 | **B-LS 未接入**；`tools/ls-sem` 已实现受限源码子集 |

> 下面的 M1c/M1d 小节是历史记录；以本表为准。

## M1c-3b-1（已实现）

`arith.ls`：单字母变量、`let`、`+ - * / %`、比较、括号、`return`。
用 shunting-yard 转后缀；输出 ELF，退出码 12。

## M1d-0a（已实现）

`funcs.ls`：多函数、`Int` 参数、函数调用、`ret`、末尾 trampoline。
测试：`funcs2.ls`，`add(1,2)` 返回 3。嵌套调用暂不支持。

## M1d-0b（已实现）

`slice_stage.ls`：在 funcs 基础上加 `Array[U8/Int, N]` 声明、索引读写、
`Slice[U8/Int]` 参数（base+len 两槽）与 `slice(array, off, len)` 构造。
测试：`bootstrap/bls/tests/stage1_slice.ls`，stage1 编译后退出码 177。
数据段按函数槽布局：Int 变量 208 字节/函数、Slice 16 字节/槽、数组顺序追加。
限制：索引子表达式是独立的非递归解析器；仍只支持单字母名字。

## M1d-0c（已实现）

`struct_stage.ls`：在 slice stage 基础上加 `struct` 声明、字段偏移、
`.field` 读写、`enum` 标签与 tag-only `match`。
测试：`bootstrap/bls/tests/stage1_struct_enum.ls`，退出码 177。
元数据表位于 `post` 高段：struct 定义 5120、struct 变量 6400、enum 定义 7000。
限制：match 的 arm 目前只接受 `{ return <expr>; }`；enum 仅 tag-only。

## M1d-0d（已实现）

`names_stage.ls`：以名字表取代单字母变量与 8 字节打包名。
名字表使用**变长字节池**：

- `post[10000]`：名字数量
- `post[10001]`：池已用字节数
- 条目 `i`：`post[10002 + i*2] = { byte_off, byte_len }`
- 字节池从 `post[12000]`（word）开始，容量约 166 KiB

函数名、参数名、变量名、struct/enum/字段名均使用 name id，支持多字符名字与 UTF-8 标识符。
变量表位于 `post[9000]`；`post` 为 `Array[Int, 32768]`。
测试：`bootstrap/bls/tests/stage1_names.ls`、`stage1_long_name.ls`（256 字节标识符），退出码 177。
限制：名字最长 256 字节；参数仍最多 6 个；match arm 仍仅 `{ return <expr>; }`。
Unicode/UTF-8 编码规则见 [`spec/bls.md`](../../spec/bls.md) §2.3。

## M1d-1a（已实现）

`names_stage.ls` 增加目标语言控制流与 `write`：

- `if/else/else-if`、`while`、`break`、`continue`；
- `write("...")` 字面量（UTF-8 字节）；
- 函数实参支持非递归表达式（算术/比较/括号），如 `add(s, i * 2)`；
- 测试 `bootstrap/bls/tests/stage1_control.ls`，输出 `ctl ok`，退出码 14；
- 限制：实参中的嵌套调用仍未支持；一般 `Str` 变量已在后续补齐。

## M1d-0e（已实现）

`names_stage.ls`：增加 `argc`/`arg_len`/`arg_byte`、`read_file`/`write_file`。
- 输出 ELF 的 runtime 块保存 argc、argv 与 256 字节路径缓冲；
- `read_file`/`write_file` 使用 `openat/read|write/close`，路径参数为 `Slice[U8]`；
- 测试 `bootstrap/bls/tests/stage1_io.ls`：用 argv[1]/argv[2] 读写文件，Linux CI `cmp`；
- 产物 `PT_LOAD` 改为 R|W|X，变量与缓冲区可写；
- 支持最多 256 字节的 argv 路径复制；`arg_byte` 使用固定 helper，避免每个调用占用数据补丁。
- 限制：内置 I/O 的长度/容量表达式使用非递归 `parse_index`；路径超过 256 字节需调用方保证不越界。

## M1c-3b-2（已实现）

`calc.ls`：在 arith 基础上加 `if/else`、`while`、赋值、正确的 `write` 字符串；
可编译 `calc.ls`，输出退出码 14 与 "calc ok"。

## M1c-3b-2 设计记录

stage1 还需：

1. **表达式**：数字/变量/`+ - * / %`/比较/括号；
   - 建议用**显式运算符栈（shunting-yard）→ 后缀**，避免 B-LS 递归；
   - 后缀数组 `Array[Int, N]`，每个 token 两项（kind, value/name/op）。
2. **变量**：名字打包为 8 字节 Int；变量槽在输出 ELF 数据段分配，`[rip+disp]` 回填。
3. **语句**：`let`、赋值、`if/else`、`while`；
   - 控制流用 `je/jmp` 占位 + 回填；
   - 复用 loop 栈处理 `break/continue`。
4. **codegen**：表达式走机器栈（push/pop），语句用 `dpos`/`jpos` 补丁表。
5. **验证**：
   - `--run` 跑 stage1 编译 `calc.ls`；
   - CI 执行 stage1 产物，校验 `calc ok` 与退出码 14。

## 约束（当前）

- 无递归：表达式用运算符栈，语句用显式块栈；
- 名字最长 256 字节；参数最多 6 个；match arm 仍仅 `{ return <expr>; }`；
- 目标语言实参支持表达式与嵌套调用；

- struct/Array/Slice 元数据偏移均为 31 位；>2 GiB 有编译期守卫；300MB `huge_offset.ls` 已验证；
- 仅 x86_64 Linux ELF；Stage 2/3 多目标未开始。


## Stage 2 首两项（`Option[T]`/`Result[T,E]`/`?`，单态化已实现）

- 内置 `Option[T]`/`Result[T,E]`，`T`/`E` 支持 `Int`、`U8`、`Str`、
  `Slice[U8]`、`Slice[Int]`；
- 构造 `Option.Some(v)`/`Option.None`、`Result.Ok(v)`/`Result.Err(v)`；
- 函数返回类型 `Option[T]`/`Result[T,E]`；
- `expr?` 成功解出负载，失败原样提前返回；
- `match Variant(v)` 支持标量、`Str`、`Slice` 负载绑定；
- 类型化 `let`：`let o: Option[Str] = ...`、`let s: Str = ...?` 等；
- 生成函数统一使用 `rbp` 帧，保证 `?` 提前返回前能丢弃表达式栈。

运行期：Option/Result 值指向 `[tag, payload...]` 数据块；标量 1 槽、`Str` 3 槽、
`Slice` 2 槽。测试覆盖 `Int`/`U8`/`Str`/`Slice` 与成功/失败路径。

### 用户自定义泛型（统一装箱）

- 用户泛型 enum 值统一为 `[tag, payload...]` 块；`T` 支持 `Int`/`U8`/`Str`/`Slice`；
- `enum Box[T] { Box(T), Empty }` 支持构造、`match`、类型化 `let`、函数返回；
- 泛型函数 `fn id[T](x: T) -> T` 的实参/返回值为 box 指针，调用点装箱/解包；
- 支持 `Int`/`U8`/`Str`/`Slice` 的泛型函数透传；
- `T` 上的 `+ - * / %` 与比较使用运行时 typecode 分派：
  `Int`/`U8` 算术/比较；`Str +` 拼接、`Str` 比较按 Unicode 标量值；
  `Slice` 逐元素比较；`Slice` 的 `+`/算术在调用点编译期拒绝；
  显式 `concat_into`/`append_into` 写入调用者目标 Slice（容量不足 trap）；
- 构造器推断：`let o = Option.Some(1);` 可用；`Option.None` 仍需类型标注；
- `?` 按内层表达式类型解包，并在编译期检查与函数返回类型一致；
- 负例：`qmark_mismatch`、`none_no_type`、`gen_enum_payload`。

限制：`Slice` 支持比较，不支持 `+`/算术；`Str +` 使用 1 MiB 运行时 bump heap，
`arena_reset()` 可显式重置；`Slice` 的 `concat_into`/`append_into` 不分配，写入调用者目标；
泛型函数内算术结果使用静态 box，适合非递归/立即消费；多类型参数、约束、完整统一、
struct 负载、`Error`、结构化诊断/fix-it 仍待后续。
源码级的 `Buffer[T]`/region/所有权、多参数泛型/约束、`val`/`ref`/effect/契约/`comptime`、
`Result` 分配失败与 arena 预算/回收已在独立 `tools/ls-sem` surface checker 中实现并测试；
本目录 stage1 尚未接入这些规则。
函数上限 128；array/slice 元数据 `fn` 为 7 位、长度位移 42；code/out 缓冲 1 MiB。
