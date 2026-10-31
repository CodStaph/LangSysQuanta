# bootstrap/ · 无 LLVM / 无 Rust 依赖链

> 计划：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md)；
> 方言：[`spec/bls.md`](../spec/bls.md)。
> 状态：**M1d-2 已完成**——stage1 自编译、`stage2 == stage3` 固定点均通过；
> 当前固定点 **`fb8b8e32…390`**（2026-10-31 R2.2 多参数泛型 struct 后，QEMU/TCG 全量，
> 需 `QEMU_TIMEOUT=7200`，QEMU 全程约 78 分钟）。
> Stage 2 已完成：`Result`/`Option`/`?`、内置泛型单态化、用户泛型统一装箱、
> **B4 多类型参数泛型/约束**（最多 2 参数；`Ord/Eq/Num/Add`，内联/`where`、约束转发）、
> **B5-1 `ref x: Int` 临时借用**、**B5-2 `ref Str/Slice` 只读视图 + 转发**、
> **B5-3 `ref Buffer` + ref Slice 索引**、**B5-4 `ref Str` 写入/`ref Str[i]`**、
> **B5-5 `ref Slice` 赋值/索引写入**、**B5-6 `ref[T]` 局部/返回**、
> **B5-8 `ref` 生命周期/逃逸静态检查**（返回本地 ref、存进更长寿命字段 →
> `E-LS-REGION-ESCAPE`；块级近似，不做区域推断）、
> **B5-9 `ref` 作为数组元素（`Array[ref[T], N]`）与泛型负载**
> （`Option[ref[T]]`/`Result[ref[T], E]` 的构造/`match`/`?`，带逃逸检查）、
> **B5-10 effect/cap/mode**（`eff(...)` 声明与传播、`Cap[...]` 令牌、`let val` 冻结局部）、
> **B5-11 契约与非空 `comptime`**（`requires`/`ensures` 运行期断言、`result`、编译期常量折叠）、
> **B5-12 struct 泛型负载与内置 `Error`**（`Option[Struct]`/`Result[Struct, Error]`、`Error` 四变体）、
> **R3.6 结构化诊断 + fix-it**（5 类×10 站点两行机读格式：
> `stage1: <码>: <line>:<col>: <原文本>` + `  fix-it: <建议>`，列按码点计数；
> 动态数字/效果名/令牌名；新单函数 `diag_pos(src,off,mode)`）、
> **B7 用户 trait/impl + struct 比较派生（R2.3）**（`trait`/`impl Trait for Ty`
> 声明表（≤16/≤12），`Eq`/`Ord` 方法**静态分派**（kind 89/93、callee 拷贝
> 序言），struct 值六比较运算符派生自 `eq`/`lt`，无行 → `E-LS-NO-IMPL`；
> 用户 trait 作泛型 bound（`[A: MyTrait]`））、
> **R2.2 多参数泛型 struct**（`struct S[A,B]{f:A,f2:Int}`：**复用 B4 泛型
> enum 的 `tmpl`/`inst` 表 + `mk_inst` 零新增顶层函数**，`nparams` bit 7
> 区分 struct/enum 模板，实例类型码 `120+ii`、`sv` sidx `70+ii`，
> typed-let 实例化 + 字段读/写（8 字节槽），sast 第三次扩容 115200/守卫
> 18600、`ctxi` 256536、重定位 258656）、
> `Buffer[Int]`/region/所有权、arena 预算与回收、
> 句柄表压缩、`region r(cap)` 硬配额。
>
> **未完成**：泛型函数 `f[T]` 的 ref 实参、`Slice[ref[T]]`、区域推断/完整所有权；
> 模块 `#[cap]`、`iso`/`box` 所有权与 move、效果多态、契约的 `=>`/`old` 形式与静态证明、
> `comptime` 表达式形式与 fuel；
> 非 ref struct 参数与 struct 返回值、trait 关联类型/默认实现/孤儿规则、
> `.eq`/`.lt` 显式调用与 vtable/字典传递、`E-LS-NO-IMPL` 结构化（下个诊断批次）、
> `Error` 错误域/`From`；Stage 3。
> **注意**：seed `MAX_FUNCS = 128`，`names_stage.ls` 现恰 **128** 个顶层函数（R3.6 前 127 +
> 只增 1 个 `diag_pos`）——后续特性**不得再新增顶层函数**，只能内联或扩 seed 表。
> 独立的 [`tools/ls-sem`](../tools/ls-sem/README.md) 覆盖受限源码子集；B-LS stage1
> 已接入其中大部分运行时/资源语义，未接入的语法继续输出 `E-LS-UNSUPPORTED`（B1）。

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

- `src` 必须是 `Slice[T]` 变量或 `Str`（按字节，`T` 必须是 `U8`）；`Array` 源请先用 `slice()` 建成 `Slice[T]`；
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

## 用户 trait / impl（R2.3）

```ls
impl Eq for Point {
    fn eq(a: ref Point, b: ref Point) -> Int { ... }
}
impl Ord for Point {
    fn lt(a: ref Point, b: ref Point) -> Int { ... }
}
trait Show { fn render; }                    // 声明只登记（≤16）
fn report[A: Show](v: Int) -> Int { ... }     // 用户 trait 作 bound
fn mk[A: Copy](v: ref A, out: ref A) -> Int { ... }
```

- struct 值的六比较运算符 `==`/`!=`/`<`/`<=`/`>`/`>=` 派生自 impl 的 `eq`/`lt`
  （**静态分派**：`==`→eq、`!=`→eq+取反、`<`→lt(a,b)、`<=`→¬lt(b,a)、
  `>`→lt(b,a)、`>=`→¬lt(a,b)）；无 impl → `E-LS-NO-IMPL`；
- 方法形参写法 `ref a: Point`（struct 槽须 8 字节对齐）；方法进扁平命名空间，
  `eq`/`lt` 名同样受 `E-LS-DUP` 复查；`(trait, type)` 至多一个 impl
  （`E-LS-COHERENCE`）；内置名 Eq/Ord/Num/Add/Copy 不可作 trait 名；
- bound：`[A: Copy]` 全过；`[A: MyTrait]` 扫 impl 行（无实现即拒）；
- 详见 [`results/B7-traits.md`](../results/B7-traits.md)。

## 多参数泛型 struct（R2.2）

```ls
struct S[A, B] { f0: A, f2: Int }   // ≤2 参数、≤4 字段

fn main() -> Int {
    let p: S[Int, Str];      // 实例化（类型码 120+ii；sv sidx 70+ii）
    p.f0 = 11;               // 泛型参数位写字段（8 字节槽）
    p.f2 = 22;               // 具体 Int 字段写
    if p.f0 != 11 { return 1; }   // 字段读（kind 12 slot load）
    let q: S[Str, Int];
    q.f2 = 33;
    if q.f2 != 33 { return 3; }
    return 7;
}
```

- 模板/实例**复用** B4 泛型 enum 的 `tmpl`（123000）/`inst`（124000）表与
  `mk_inst`：**零新增顶层函数**（`MAX_FUNCS=128` 不变）；
- `nparams` **bit 7** 区分 struct 模板与 enum 模板（`parse_user_desc`
  遇该位即回退，`S[Int,Str]` 不再被 enum 描述路径抢占）；
- 字段每槽固定 **8 字节**（`off = 基址 + fi*8`）；写字段校验实参类型 =
  实例具体化 fty（`struct: field type mismatch`）；
- 结构声明后仍由 `scan_funcs` 预登记 `st` 表，故 typed-let/`parse_ty`
  以 bit 试探优先于非泛型 `st` 行；
- 不做：泛型 struct 作函数实参/返回、整体比较、Str 字面量字段存
  （与非泛型 struct 同边界）、`>2` 参数、`>4` 字段（模板表宽 12 所限）；
- 详见 [`results/R2.2-generics-struct.md`](../results/R2.2-generics-struct.md)。

## Buffer / region（R4.7）

```ls
let b: Buffer[Int] = Buffer.new[Int](4, heap);
b.push(11);
region R(128) {                       // 可选硬配额：cap 是运行期 Int 表达式
    let c: Buffer[Int] = Buffer.new[Int](2, heap);
    if region_limit() != 128 { ... }
}
if arena_compact() > 0 { ... }        // 句柄表 + 移动式压缩（Str 块 pinned）
```

- `Buffer` handle 是 **128 槽句柄表的下标**；`arena_compact()` 搬动活 Buffer 并改写表项，
  因此 handle 在压缩后仍然有效；`Str`/裸 `arena_alloc` 块不移动；
- `region R(cap)` 把有效 `arena end` 临时限制为 `mark + cap`（不超过父 region/全局），
  退出或 `-> Int` 内 `return` 时恢复；`Buffer`/`arena_alloc`/`Str +` 的失败返回 `-1`/`Err`；
- `b.release()`/`drop` 成功会使 handle 失效（重复释放返回 `-1`）；
- 详见 [`results/R4.7-handle-quota.md`](../results/R4.7-handle-quota.md)。

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

1. ref 泛型负载、区域推断（B5-8 已做块级生命周期/逃逸）；
   再 `mode`/cap/effect；契约/非空 `comptime`；
   表达式两阶段 IR（B0.3d）；trait 关联类型/默认实现与 `.eq`/`.lt` 显式调用；
   多诊断聚合与最小不可满足核（`modes.md` §5 求解器项）仍待；
2. Stage 3：切换去种子构建路径 → ARM64/裸机 → 双 C 编译器 + DDC → stage1 模块拆分；
3. 每加一项特性都重跑固定点（`bootstrap/ci/run-qemu.sh` 或 GitHub Actions），并与 S-1 并行。

> AI生成
