# bootstrap/ · 无 LLVM / 无 Rust 依赖链

> 计划：Bootstrap 实施计划（内部文档，未随仓库发布）；
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

- Linux 本地执行已在 `bootstrap/ci/run-qemu.sh`（真 Linux 内核）中实测通过，
  包含 `stage2 == stage3` 固定点（2025 实测，GitHub Actions 结果待归档）；
- stage1（M1c）/固定点（M1d）的正式归档；
- stage1 自举（M1c/M1d）。

## 下一步

1. 把 M1 语法（struct/enum/if/while/函数调用）加进 seed；
2. 在 `bootstrap/src` 写 stage1（B-LS），先编译 `hello.ls`，再自编译；
3. 固定点：`stage1 == stage2`；
4. 按 `05 §5` 逐步加入 L-Sys 特性。
