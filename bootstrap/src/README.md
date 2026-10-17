# bootstrap/src · stage1（B-LS）

**当前**：`main.ls` 实现 hello 子集（`write` + `return`），可被 seed 编译并由 `--run` 调试。

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

## M1d-0e（已实现）

`names_stage.ls`：增加 `argc`/`arg_len`/`arg_byte`、`read_file`/`write_file`。
- 输出 ELF 的 runtime 块保存 argc、argv 与 256 字节路径缓冲；
- `read_file`/`write_file` 使用 `openat/read|write/close`，路径参数为 `Slice[U8]`；
- 测试 `bootstrap/bls/tests/stage1_io.ls`：用 argv[1]/argv[2] 读写文件，Linux CI `cmp`；
- 产物 `PT_LOAD` 改为 R|W|X，变量与缓冲区可写；
- 限制：内置 I/O 的长度/容量表达式使用非递归 `parse_index`；路径复制测试上限 16 字节。

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

## 约束

- 无递归：表达式用运算符栈，语句用显式块栈；
- 变量最多 64 个，表达式 token 最多 1024；
- 只支持 `Int`；数组/结构/枚举暂不进入 stage1 的第一版。
