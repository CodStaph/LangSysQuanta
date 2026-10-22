# bootstrap/ · 无 LLVM / 无 Rust 依赖链

> 计划：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md)；
> 方言：[`spec/bls.md`](../spec/bls.md)。
> 状态：**M1d-2 已完成**——stage1 自编译、`stage2 == stage3` 固定点均通过（GitHub Actions 实测）。
> Stage 2 的 `Option[T]`/`Result[T,E]`/`?` 部分已完成：单态化（`Int`/`U8`/`Str`/`Slice`）；用户泛型 enum/fn 统一装箱（见下）。
>
> **边界**：独立的 [`tools/ls-sem`](../tools/ls-sem/README.md) 已实现受限源码子集的
> `Buffer[T]`/region/所有权、泛型多参数与约束、`val`/`ref`/effect/契约/`comptime`、
> `Result` 分配失败与 arena 预算/回收；B-LS stage1（本目录）**尚未接入这些语义**，
> 但已对相关语法输出稳定的 `E-LS-UNSUPPORTED` 诊断（B1），仍只保证下表的解释/编译/固定点能力。

## Unicode / UTF-8

源文件必须是合法 UTF-8；字符串是 UTF-8 字节序列，`write` 原样输出。
seed 的 `Str` 支持变量、复制/赋值、参数、`write`、I/O 路径与 `.len`。
stage1 已支持变量/复制/参数/`.len`/`write`/I/O 路径。
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

## Slice 子视图（seed 侧，B0.3a-1）

```ls
let s: Slice[U8] = slice(buf, 0, 8);   // slice(arr, off=字节, len=元素)
let t: Slice[U8] = slice_at(s, 2, 3);  // slice_at(src, off=元素, len=元素)
let u: Slice[Int] = slice_at(si, 1, 2);
```

- `src` 可以是 `Slice[T]` 变量、`Str`（按字节，`T` 必须是 `U8`）或 `Array` 名（等价的 `slice`）；
- **`off` 以元素计**（`slice()` 的 `off` 仍是字节，历史语义）；
- 不做运行期边界检查（与 B-LS 现有数组/切片一致）；
- **seed 与 stage1 均已实现**（`--run`、seed 产物、stage1 产物）；stage1 侧验证见
  `results/B0.3a-slice-at.md`（QEMU：`PASS compiled slice_at stage1 -> exit 88`）。

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

## Stage 2：Result / Option / ?（单态化）

当前 stage1 支持 `Option[T]`/`Result[T,E]`，`T`/`E` 可为 `Int`、`U8`、`Str`、
`Slice[U8]`、`Slice[Int]`：

```ls
enum Option { Some(Int), None }
enum Result { Ok(Int), Err(Int) }

fn inc(x: Int) -> Result[Int, Int] {
    if x < 0 { return Result.Err(7); }
    return Result.Ok(x + 1);
}

fn twice(x: Int) -> Result[Int, Int] {
    let a = inc(x)?;
    let b = inc(a)?;
    return Result.Ok(b + 10);
}
```

测试：`result_option.ls`（13）、`result_err.ls`（7）、`option_chain.ls`（6）、
`option_none.ls`（9）、`option_u8.ls`（200）、`result_u8_err.ls`（5）、
`option_str.ls`（3）、`result_str_ok.ls`（2）、`option_slice.ls`（10）等。
限制：内置 `Option`/`Result` 支持 `Int`/`U8`/`Str`/`Slice`；
用户自定义泛型采用统一装箱：enum 负载/泛型函数 `T` 支持 `Int`/`U8`/`Str`/`Slice`。
`?` 负载类型需与函数返回类型一致；struct 负载/`Error`/结构化诊断与 fix-it 待后续；
`match` arm 仍只接受 `{ return expr; }`。

## 用户自定义泛型（统一装箱）

```ls
enum Box[T] { Box(T), Empty }
fn id[T](x: T) -> T { return x; }
```

- enum 值统一为 `[tag, payload...]` 块，`T` 支持 `Int`/`U8`/`Str`/`Slice`；
- `Box[Int]`/`Box[Str]`/`Box[Slice[U8]]` 可构造、`match`、类型化 `let`、函数返回；
- 泛型函数实参/返回值装箱，支持 `Int`/`U8`/`Str`/`Slice` 透传；
- `T` 上的算术/比较用运行时 typecode 分派：
  `Int`/`U8` 算术/比较；`Str +` 拼接、`Str` 比较按 Unicode 字符；
  `Slice` 逐元素比较；`Slice +`/算术编译期拒绝，拼接/追加用 `concat_into`/`append_into`；
- 推断：`let o = Option.Some(1);`；`Option.None` 仍需标注；
- 负例：`bootstrap/bls/tests/reject/`，由 `run-stage1.sh` 验证编译失败。

限制：`Slice` 支持比较、不支持算术；`Str +` 使用 1 MiB 运行时 bump heap（`arena_reset()` 可重置）；
`concat_into`/`append_into` 写入调用者目标 Slice；泛型函数内算术结果使用静态 box；
多类型参数、约束、完整统一仍待后续；这些规则目前由独立 `tools/ls-sem` surface checker
验证，B-LS 前端尚未共享。

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

## 本地 Linux CI：QEMU（无需 VT-x / WSL / Docker）

`bootstrap/ci/run-linux.sh` 与 `run-stage1.sh` 需要真实 Linux 内核来**执行** seed 生成的裸 ELF。
在没有 VT-x/SLAT 的机器上（嵌套云主机、Windows 10 1809），VirtualBox、Hyper-V、WSL2、Docker Desktop 都不可用，
`run-qemu.sh` 改用 QEMU 的纯软件模拟（TCG）在本地跑同一套 CI：

```bash
./bootstrap/ci/run-qemu.sh
```

首次运行下载约 240 MiB（Alpine netboot 内核、Ubuntu 24.04 base rootfs、便携版 QEMU），缓存在
`.qemu-cache/`（已 git 忽略）；之后每次约 1 分钟跑完。

分工：

| 阶段 | 位置 | 做什么 |
| --- | --- | --- |
| 宿主 | `run-qemu.sh` | 下载 kernel/rootfs；用 `clang --target=x86_64-unknown-linux-gnu -nostdlib -static`（与 `build.sh` Linux 分支相同 flags）交叉编译 seed.c；把工作区快照打进 initramfs |
| guest | `ci/qemu/init` + `ci/qemu/guest-run.sh` | 用预置 seed（`SKIP_SEED_CC=1`）跑 `bootstrap/build.sh`，再执行 `run-linux.sh`（其中已链入 `run-interp.sh`、`run-stage1.sh` 与固定点 `stage2 == stage3`） |

所以除“编译 seed 自身”之外，所有构建与断言都在真 Linux 内核里完成。

要点：

- 不改工作区：guest 拿到的是 `.qemu-cache/work/repo` 里的副本，构建产物不会回到仓库；
- 快照会把文本文件的 CRLF 归一为 LF，与 Linux 检出（`.gitattributes` 的 `eol=lf`）一致；
- `ci/qemu/mkinitramfs.py` 把 rootfs tarball 直接流式打成 cpio/newc（MSYS 没有 `cpio`，
  且 `bsdtar` 在 Windows 上无法记录 POSIX 权限位，会让 `/init`、`/bin/bash` 丢失执行位）；
- Linux 宿主上脚本自动改为直接跑原生 CI，`QEMU_FORCE=1` 可强制走 QEMU。

环境变量：

| 变量 | 默认 | 说明 |
| --- | --- | --- |
| `QEMU_CACHE` | `<repo>/.qemu-cache` | 缓存与临时目录（路径不能含空格） |
| `QEMU_SYSTEM` | 自动安装 | 指定已有的 `qemu-system-x86_64` |
| `QEMU_TIMEOUT` | 1200 | 秒；超时终止 VM |
| `QEMU_MEM` / `QEMU_SMP` | 1024 / 2 | guest 内存（MiB）与 vCPU 数 |
| `CC` | `clang` | 交叉编译 seed 的宿主编译器 |
| `KERNEL_URL` / `ROOTFS_URL` | Alpine 3.20 virt / Ubuntu 24.04 base | 可换成内网镜像 |

日志：`.qemu-cache/qemu.log`（宿主运行时会实时回显）。判定只看 `QEMU-GUEST: RESULT=` 与脚本退出码。

已知噪音：`run-stage1.sh` 的 `trap ... ERR` 在 `set +e` 区间里也会触发，因此日志会出现
`run-stage1 FAILED at line N`，这是预期非零退出码（177、202 等）造成的，不是失败。

## 布局

```text
bootstrap/
  seed/seed.c          # stage0 C seed（M0）
  bls/tests/hello.ls   # 第一个 B-LS 程序
  src/                 # stage1（B-LS 编写）
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

- 完整 L-Sys 自举（当前只验证 B-LS 子集的固定点）；
- 数据布局超过 2 GiB 的寻址路线（需基址寄存器/movabs）。

## 下一步

1. Stage 2 剩余：把 `tools/ls-sem` 已验证的 `Buffer[T]`/region、多类型参数/约束、`val`/`ref`、
   effect/契约/`comptime`、`Result` 分配失败与 arena 预算接入 B-LS stage1；
   再补 `mode`/cap、结构化诊断/fix-it；
2. 每加一项特性都重跑固定点（`bootstrap/ci/run-qemu.sh` 或 GitHub Actions）；
3. 与 S-1 主线（类型/region/mode/cap/effect 检查）并行。
