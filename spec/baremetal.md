# spec/baremetal.md · 裸机属性、asm、链接与 C ABI（草稿）

> **状态**：`草稿`。**Q6 决定已定**（目标相关数据模型 + v0 不支持跨 FFI 位域）；
> 属性/asm 语法草案；完整后端与 ABI 冻结套件待 S0′/S1。
> **上位**：[`02 ADR-20`](../02-架构评审与ADR.md)（裸机属性/asm/数据驱动生成）、
> [`02 ADR-12`](../02-架构评审与ADR.md)（ABI/edition）、
> [`00 §5.5`](../00-LangSysQuanta-设计初稿.md)（unsafe/底层/契约）、
> [`image.md`](image.md)（镜像/加载）、[`toolchain.md`](toolchain.md)（target 矩阵）。
> **范围**：`#[no_mangle]`/`#[link_section]`/`#[used]`/`#[naked]`/`#[link]`/`#[repr]`、
> `asm`、入口/链接脚本、`extern "C"` 类型映射。
> **不在本文件**：MMIO 语义（`modes.md`/`effects.md`）、中断/DMA 域（`H-LS-16`）、
> 完整 C++ 互操作（明确非目标）。

---

## 1. Q6 决定：C ABI v1

`abi = "ls-c-1"`。v0 的 C ABI 是**目标相关、显式 `#[repr(C)]`、无隐式布局**的子集：

1. `char` 的有符号性按目标 C ABI 固定（见 §5.1）；跨 FFI 建议写 `i8`/`u8`；
2. `long` 宽度按目标数据模型：x86_64 LP64 → `i64`；ARM32/RISC-V32 ILP32 → `i32`；
3. **位域不进入 C ABI v1**：`#[bitfield]` 只用于内部/MMIO；`extern "C"` 结构含位域 ⇒ `E-LS-ABI`；
4. `enum` 跨 FFI 必须有 `#[repr(C)]` + 显式整数 repr；默认 enum 布局 ⇒ `E-LS-ABI`；
5. 结构体跨 FFI 必须有 `#[repr(C)]`；`#[repr(transparent)]` 用于 newtype；
6. 变参、`long double`、complex、VLA、flexible array member、异常/unwind 不支持；
7. 函数符号用 C 名；`#[no_mangle]` 显式；无重载/mangling；
8. ABI 布局哈希进镜像；链接期/加载期不匹配 ⇒ `E-LS-LAYOUT`/`LC-*`。

> Q6 的**规格决定**关闭；实现关闭条件是 ABI 冻结套件（0.2 库 × 0.3 程序）通过。

### 1.1 `ls-sem` 第一版实现

- `tools/ls-sem/src/target.rs`：三目标数据模型/char signedness/long 宽度；
- `tools/ls-sem/src/abi.rs`：`CType` → `LSysType`、size/align、位域/`long double` 拒绝；
- CLI：`ls-sem targets`、`ls-sem abi <triple> <ctype>`；
- 测试：`tools/ls-sem/tests/q2_q6_q7.rs`。

> 这是**标量层面**的实现；结构体/枚举/位域布局、ABI 冻结套件仍未实现。

---

## 2. 属性

| 属性 | 作用 | 约束 |
|---|---|---|
| `#[repr(C)]` | C 布局 | FFI 必需；字段顺序/对齐按目标 ABI |
| `#[repr(transparent)]` | 单字段 newtype | 字段布局与内层相同 |
| `#[repr(align(N))]` | 提高对齐 | N 为 2 的幂；不得降低 `repr(C)` 对齐 |
| `#[no_mangle]` | 保留符号名 | 仅 `fn`/`static`；跨 crate 冲突 ⇒ `E-LS-ABI` |
| `#[link_section = "..."]` | 指定段 | 段名必须由链接脚本/目标白名单允许 |
| `#[used]` | 保留 static | 不改变生命周期/所有权 |
| `#[naked]` | 无 prologue/epilogue | 函数体只能是 asm；调用约定由 asm 负责 |
| `#[link(name)]` | 外部库 | v0 静态链接；动态库不支持 |
| `#[bitfield]` | 位域布局 | 只用于内部/MMIO；不跨 C ABI |
| `#[register(...)]` | 寄存器视图 | 需 `Mmio`/cap；不自动 trusted |

- 属性是**封闭集**；未知属性 ⇒ `E-LS-ATTR`；
- `#[naked]` + `#[no_mangle]` 常用于入口/向量；`#[naked]` 函数不得有普通 L-Sys 语句；
- 代码生成器（SVD/bindgen）产物标 `@generated`，不参与 style，但**不自动 trusted**。

---

## 3. `asm`

```ls
asm("mrs {}, cntpct_el0", out("x0") => t);
asm("wfi");
```

- `asm` 的封闭形式：字符串模板 + 命名操作数 `in/out/inout` + 可选破坏列表；
- 操作数类型限制为标量/`rawptr`；不允许把 `val`/`ref` 句柄直接传入；
- `asm` 需要 `Cap[Unsafe]`（或模块 `#[cap(Unsafe)]`）与 `eff(Asm)`；
- `#[naked]` 函数体只允许 `asm`；
- `asm` 不参与常量折叠/重排；volatile 语义按 `effects.md`/`00 §6.10`；
- 目标寄存器名由 target 矩阵登记；未知名 ⇒ `E-LS-ABI`。

---

## 4. 链接与入口

- v0 只支持**静态镜像**，不支持动态链接/PLT/GOT；
- 入口符号由链接脚本/`#[entry]` 约定（v0 用 `#[no_mangle] fn _start` 或 target entry）；
- `#[link_section]` 的段必须存在于链接脚本；未知段 ⇒ `E-LS-LAYOUT`；
- `static` 允许 `val`/`shared`；裸 `static mut` 不存在（ADR-13）；
- 向量表/启动代码由 `#[naked]` + `#[link_section = ".vectors"]` + `#[used]` 构成；
- 栈/堆边界由链接脚本/镜像 header 给出；栈上界由 `#[stack]`/递归上界检查（`H-LS-29`）。

---

## 5. C ABI 类型映射

### 5.1 标量

| C 类型 | x86_64-linux (LP64) | thumbv7em (ILP32) | riscv32imac (ILP32) |
|---|---|---|---|
| `char` | `i8`（signed） | `u8`（unsigned, AAPCS） | `u8`（unsigned psABI） |
| `signed char` | `i8` | `i8` | `i8` |
| `unsigned char` | `u8` | `u8` | `u8` |
| `short` | `i16` | `i16` | `i16` |
| `int` | `i32` | `i32` | `i32` |
| `long` | `i64` | `i32` | `i32` |
| `long long` | `i64` | `i64` | `i64` |
| `size_t` | `usize` | `usize` | `usize` |
| `ptrdiff_t` | `isize` | `isize` | `isize` |
| `_Bool`/`bool` | `u8` | `u8` | `u8` |
| `float` | `f32` | `f32` | `f32`（软浮点） |
| `double` | `f64` | `f64` | `f64`（软浮点） |
| `void*` | `rawptr[U8]` | `rawptr[U8]` | `rawptr[U8]` |
| 函数指针 | `fn(...)` | `fn(...)` | `fn(...)` |

- `char` 的 signedness 是**目标 C ABI 事实**，不是 L-Sys 默认；新 FFI 代码应显式 `signed char`/`unsigned char`；
- `long double`、`_Complex`、`wchar_t`、`__int128` v0 不支持；
- `bool` 在 C ABI 是 1 字节；L-Sys `Bool` 的内部表示不承诺与 C `_Bool` 相同，跨 FFI 用 `U8`。

### 5.2 聚合类型

| C 构造 | L-Sys | 规则 |
|---|---|---|
| `struct` | `#[repr(C)] struct` | 字段顺序/对齐按目标 ABI；布局哈希 |
| `union` | `#[repr(C)] union` | 必须显式 repr；读非活跃成员是 unsafe |
| `enum` | `#[repr(C)] enum` + 显式整数 | 无 repr/无整数 ⇒ `E-LS-ABI` |
| 位域 | **不支持跨 FFI** | 用整数 + 显式 mask/shift 访问器 |
| 数组 | `Array[T,N]` / 指针 + len | 数组按值传递时按 C 布局；Slice 不按值传 |
| 函数 | `extern "C" fn` | nounwind；无变参；无重载 |
| 回调 | `#[no_mangle] extern "C" fn` | 函数指针 + `Cap[Ffi]`/边界 |

### 5.3 所有权/边界

- `extern "C"` 调用需要 `Cap[Ffi]` + `eff(Ffi)`；
- 指针参数用 `rawptr[T]`，长度显式传递，不假设 NUL 终止；
- `iso`/`val`/cap 按值传递；`ref` 不作为 FFI 参数/返回；
- 跨 FFI 的 unwind 是 UB-15；`extern "C"` 隐含 `nounwind`（模型与显式信任：
  `lean/LSys/Ffi.lean` 的 `Exit`/`FfiEvent`/`HonorsNounwind`，登记于 `spec/trust.md`）；
- FFI 结构布局必须与 C 头文件逐字段一致；生成/校验由 `ls bindgen`/`ls abi-check`。

---

## 6. 诊断

| 情形 | 诊断 |
|---|---|
| 未知属性/段/寄存器 | `E-LS-ATTR` / `E-LS-ABI` |
| 非 `repr(C)` 结构跨 FFI | `E-LS-ABI` |
| 位域跨 FFI / enum 无 repr | `E-LS-ABI` |
| 布局哈希不匹配 | `E-LS-LAYOUT` |
| `asm` 无 `Cap[Unsafe]`/`Asm` | `E-LS-UNSAFE`/`E-LS-CAP`/`E-LS-EFFECT` |
| FFI unwind | `E-LS-ABI`（UB-15；运行时模型见 `results/T4c-ffi.md`） |

---

## 7. 示例

```ls
#[repr(C)]
struct Timespec { sec: I64, nsec: I32, _pad: I32 }

#[no_mangle]
extern "C" fn ls_clock_gettime(clk: I32, out: rawptr[Timespec]) -> I32 eff(Ffi) {
    // C ABI: int(long long, int, int) 的布局必须与头文件一致
    ...
}
```

```ls
#[naked]
#[no_mangle]
#[link_section = ".vectors"]
fn reset_handler() {
    asm("b _start");
}
```

---

## 8. 未完成

| # | 项 | 归属 |
|---|---|---|
| B-1 | `ls abi-check` / C 头文件导入 | S1 |
| B-2 | 三目标布局/ABI 冻结套件 | S1/S2 |
| B-3 | 真实板的 entry/向量/链接脚本 | S2 |
| B-4 | SVD/bindgen 生成物与 cap/trusted 归属 | `toolchain.md` |
| B-5 | C++ 互操作（仅 `extern "C"` 包装） | S4+ / 非目标 |

> Q6 规格决定已关闭；B-1/B-2 通过前不得声称“C ABI 已冻结”。
