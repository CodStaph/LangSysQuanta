# spec/toolchain.md · target 矩阵、SVD/bindgen 与可复现构建（草稿）

> **状态**：`草稿`。**Q7 决定已定**（v0 三目标、little-endian、静态镜像）；
> 具体工具链 pin、QEMU/HIL 套件待 S1/S2。
> **上位**：[`02 ADR-20`](../02-架构评审与ADR.md)（数据驱动代码生成/`[target]`）、
> [`02 ADR-12`](../02-架构评审与ADR.md)（ABI/edition）、
> [`00 §6.10`](../00-LangSysQuanta-设计初稿.md)（成本/内存序）、
> [`00 §6.12`](../00-LangSysQuanta-设计初稿.md)（镜像）、
> [`baremetal.md`](baremetal.md)、[`image.md`](image.md)。
> **范围**：`ls.toml [target]`、三目标矩阵、SVD/bindgen/gen、可复现构建与指纹。
> **不在本文件**：LLVM/Cranelift 后端实现、调试器、HIL 硬件农场。

---

## 1. Q7 决定

v0 支持 **3 个目标**，全部 little-endian、静态镜像、`panic=abort`、无动态链接：

| # | target triple | 架构 | 数据模型 | 浮点 | 原子 | 典型用途 |
|---|---|---|---|---|---|---|
| T1 | `x86_64-unknown-linux-gnu` | x86_64 | LP64 (`char` signed) | SSE2 | 是 | QEMU/CI、内核模块原型 |
| T2 | `thumbv7em-none-eabihf` | Cortex-M4F | ILP32 (`char` unsigned) | 硬浮点 | 32-bit exclusive（无 64-bit） | MCU 固件 |
| T3 | `riscv32imac-unknown-none-elf` | RV32IMAC | ILP32 (`char` unsigned) | 软浮点 | A 扩展（32-bit） | RISC-V MCU |

- 其他目标（AArch64、RV64、Xtensa、MIPS…）**不在 v0**；新增目标必须先进本矩阵 + ABI 套件；
- 所有目标默认 `no_std`、`panic=abort`、无 unwind；`agent` 的 hosted 运行时不是本矩阵的一部分；
- 目标的 `char`/`long` 映射以 [`baremetal.md`](baremetal.md) §5 为准；
- 目标选择是**构建输入**，进指纹；同一源码不同 target 是不同产物。

---

## 2. `ls.toml` 的 `[target]`

```toml
[target]
triple = "thumbv7em-none-eabihf"
cpu = "cortex-m4"
float = "hard"              # hard | soft | none
atomics = "32"              # none | 32 | 64
linker = "lld"              # lld | gnu-ld（按目标）
panic = "abort"
no_std = true
entry = "_start"            # 或链接脚本入口
linker_script = "link/mcu.ld"
```

约束：

1. `triple` 必须在本文件矩阵中；未知 triple ⇒ `E-LS-PROFILE`/构建错误；
2. `float`/`atomics` 不能超过目标能力；`atomics=64` 在 T2/T3 上拒绝；
3. `panic` 只允许 `abort`（v0）；`unwind` ⇒ `E-LS-PROFILE`；
4. `no_std=true` 是 v0 默认；hosted 需要 ADR（ADR-21 未关闭）；
5. `entry`/`linker_script` 只影响链接，不改变语言语义；
6. `[target]` 与 `[policy]` 一起进 manifest 哈希。

---

## 3. 可复现构建

构建指纹至少包含：

```text
compiler_version + target.triple + target.cpu + float/atomics
+ linker_version + linker_script_hash
+ manifest_hash + lockfile_hash + source_tree_hash
+ svd/bindgen/gen 的 inputs/outputs 与版本
+ trusted.lock_hash + policy_hash
```

要求：

1. 同一指纹 ⇒ 逐位相同的镜像（无时间戳；见 `image.md`）；
2. 禁止 build script/任意宿主命令；代码生成只经登记的 `ls svd`/`ls bindgen`/`ls gen`；
3. 生成步骤声明输入/输出/确定性；输出进指纹；
4. 生成物标 `@generated`，不参与 style 检查，但**不自动 trusted**；
5. CI 用 `ls build --repro` + `diffoscope`（或哈希比较）验证；
6. 依赖版本由 lockfile 固定；网络访问不进入构建（vendoring）。

---

## 4. SVD / bindgen / gen

| 工具 | 输入 | 输出 | 规则 |
|---|---|---|---|
| `ls svd` | SVD 文件 | `#[register]`/`Mmio` 类型 | 地址/位宽/访问权限映射；不自动 trusted |
| `ls bindgen` | C 头文件 | `extern "C"` 声明/`#[repr(C)]` 类型 | 按 `baremetal.md` §5；位域/变参拒绝 |
| `ls gen` | 声明式模板/数据 | 源文件 | 无任意脚本；输入/输出/确定性登记 |

- 生成代码中的 `unsafe`/`rawptr` 仍计入模块 unsafe 面积；
- 生成物必须能通过 `tests/syntax`/ABI 校验；生成器版本进指纹；
- 生成物默认 `@generated`，不得自动 `#[trusted]`；
- SVD 地址范围必须与模块 `#[cap(Mmio[a..b])]` 交叉校验（`cap-context.md`）；
- bindgen 产物的布局必须与 C 头文件逐字段一致（`E-LS-LAYOUT`/`E-LS-ABI`）。

---

## 5. 目标相关规则

- **内存序**：按 `00 §6.10` 的 x86-64/ARMv8/RISC-V 表；T2/T3 的 `Order` 映射以实际架构为准，
  缺少的原子宽度在编译期拒绝；
- **浮点**：T1 SSE2、T2 hard-float、T3 soft-float；FMA 收缩关闭；denormal 固定；
- **栈**：入口栈对齐按目标 ABI；静态栈上界由 `#[stack]`/递归上界（`H-LS-29`）；
- **MMIO**：volatile，不重排/不合并；仅 `fence` 排序；
- **中断/DMA**：T2/T3 的 IRQ/DMA 域规则属 `H-LS-16`，不在 T4a；
- **镜像**：静态 `PT_LOAD`/段布局按 `image.md`；无动态链接/PLT/GOT。

---

## 6. Q7 验收

| 项 | 判据 | 状态 |
|---|---|---|
| Q7-1 | 三目标均能构建最小 `hello`/`abort` 镜像 | 未开始 |
| Q7-2 | x86_64 QEMU 跑通；T2/T3 QEMU 或 HIL 跑通 | 未开始 |
| Q7-3 | 同指纹构建逐位一致 | 未开始 |
| Q7-4 | `ls svd`/`ls bindgen` 产物可复现且 ABI 校验通过 | 未开始 |
| Q7-5 | 目标矩阵外的 triple 被拒绝 | 规则已定 |
| Q7-6 | `char`/`long`/位域 ABI 套件通过 | 规则已定；套件未做 |

> Q7 的**规格决定**已定；Q7-1…Q7-4 通过前不得声称“target 矩阵已实现”。

### 6.1 `ls-sem` 第一版实现

- `tools/ls-sem/src/target.rs`：三个 target 的 arch/data model/float/atomics/endian；
- `by_triple`、`validate_config`：未知 triple、超出 float/atomics/endian 能力被拒；
- CLI：`ls-sem targets`；测试 `tools/ls-sem/tests/q2_q6_q7.rs`。

> 这是**矩阵级**实现；构建、链接、QEMU/HIL、可复现指纹仍未实现。

---

## 7. 未决

| # | 项 | 归属 |
|---|---|---|
| T-1 | 工具链版本 pin 与可复现 LLVM/Cranelift | S1 |
| T-2 | T2/T3 的 QEMU/HIL 测试矩阵 | S1/S2 |
| T-3 | SVD/bindgen 生成物的 trusted 归属 | S4（H-LS-25） |
| T-4 | hosted/agent 运行时与 sysroot | ADR-21（未关闭） |
| T-5 | 多目标链接/LTO 与镜像合并 | 非 v0 |
