# bootstrap/ · 无 LLVM / 无 Rust 依赖链

> 计划：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md)；
> 方言：[`spec/bls.md`](../spec/bls.md)。
> 状态：**M0 + M1a + M1b 已落地**（hello/calc/funcs/arrays ELF）；Slice/结构/枚举/文件 I/O 与 stage1 未开始。

## Unicode / UTF-8

源文件必须是合法 UTF-8；字符串是 UTF-8 字节序列，`write` 原样输出。
一般 `Str` 值支持变量、复制/赋值、`Str` 参数、`write`、I/O 路径与 `.len`（字符数，`"你好".len == 2`）。
`Slice[U8].len` 仍是字节数。诊断列按字符计数。
详见 [`spec/bls.md`](../spec/bls.md) §2.3。

## 依赖

- 构建 seed：一个 C 编译器（`CC` 环境变量，默认 `clang`）；
- 运行 seed：宿主 OS；
- **不需要**：libc（Linux 路径）、`as`、`ld`、LLVM、Rust、Cargo、Make/CMake。

## 解释器（M1c-0e）

```bash
./bootstrap/seed/seed.exe --run bootstrap/bls/tests/slice_params.ls
# 输出 sparam ok，退出码 177
```

## 动态路径

`read_file`/`write_file` 的路径可以是 `Slice[U8]` 变量；编译产物会复制到 NUL 结尾的临时缓冲区。

## argv

`argc()`、`arg_len(i)`、`arg_byte(i, pos)` 在 `--run` 与编译产物中都可用。

## enum 负载 + match

```ls
enum Option { None, Some(Int) }
let x = Option.Some(42);
match x {
    Option.Some(v) => { return v; },
    Option.None => { return 0; }
}
```

## match（tag-only）

```ls
match c {
    Color.Red => { ... },
    Color.Green => { ... }
}
```

## 运算与控制流

支持 `&&`/`||`（短路）、`& | ^ << >>`、`break`/`continue`。

## 函数参数

支持 `Int` 与 `Slice[U8]`/`Slice[Int]`；Slice 以 base+len 两个寄存器传递，函数内生成局部 Slice 块。

## 解释器（M1c-0e）

```bash
./bootstrap/seed/seed.exe --run bootstrap/bls/tests/calc.ls
# 输出 calc ok，退出码 14
```

用于在宿主（含 Windows）调试 B-LS / stage1；不生成 ELF。

## stage1（M1c）

```bash
./bootstrap/seed/seed --run bootstrap/src/main.ls   bootstrap/bls/tests/hello.ls bootstrap/build/hello_stage1
```

stage1 里程碑：`main.ls`（hello）→ `arith.ls` → `calc.ls` → `funcs.ls`（多函数）
→ `slice_stage.ls`（Array/Slice 参数与索引）
→ `struct_stage.ls`（struct 字段 + tag-only enum/match）
→ `names_stage.ls`（多字符名字/名字表 + 内置 I/O）。

## 快速开始

```bash
./bootstrap/build.sh
```

- Windows/MSYS：构建 `seed/seed.exe`，生成 `build/hello`（ELF64），不执行；
- Linux：构建 `seed/seed`（freestanding），生成并执行 `build/hello`；
- 可选：`llvm-readelf`/`llvm-objdump` 验证 ELF。

## 布局

```text
bootstrap/
  seed/seed.c          # stage0 C seed（M0）
  bls/tests/hello.ls   # 第一个 B-LS 程序
  src/                 # stage1（B-LS，未开始）
  build.sh             # 唯一构建脚本
  build/               # 产物（git 忽略）
```

## 当前能力

```ls
fn main() -> Int {
    write("hello from L-Sys bootstrap\n");
    return 0;
}
```

生成 x86_64 Linux 静态 ELF：`write(2)` + `exit(2)`，不依赖 libc/as/ld。

M1a/M1b-2 还支持函数：

```ls
fn add(a: Int, b: Int) -> Int { return a + b; }

fn main() -> Int {
    let x = 2 + 3 * 4;
    let i = 0;
    while i < x { i = i + 1; }
    if i == 14 { write("calc ok
"); }
    return i;
}
```

## 已验证

- `clang` 在 Windows 宿主构建 seed，生成 ELF64；
- `llvm-readelf` 显示 `ET_EXEC` / `EM_X86_64` / `PT_LOAD`，entry 正确；
- `llvm-objdump` 反汇编确认 `write`/`exit` 系统调用与字符串地址；
- `clang --target=x86_64-unknown-linux-gnu -nostdlib` 交叉构建 seed 通过。

## 未验证

- Linux 本地执行（由 `bootstrap/ci/run-linux.sh` / GitHub Actions 完成）；
- stage1（M1c）/固定点（M1d）；
- stage1 自举（M1c/M1d）。

## 下一步

1. 把 M1 语法（struct/enum/if/while/函数调用）加进 seed；
2. 在 `bootstrap/src` 写 stage1（B-LS），先编译 `hello.ls`，再自编译；
3. 固定点：`stage1 == stage2`；
4. 按 `05 §5` 逐步加入 L-Sys 特性。
