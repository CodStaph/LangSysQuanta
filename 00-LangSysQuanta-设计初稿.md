# LangSysQuanta（L-Sys）设计初稿 · 系统编程分支

> **状态**：Draft / 探索性初稿（非规范、未实现）。
> **版本**：`0.5.0-draft`（修订自 `0.4.0-draft`；修订记录见 §0.1）。
> **文档集**：语义 [`00`](00-LangSysQuanta-设计初稿.md) / 语义评审 [`01`](01-初稿评审与修订建议.md) /
> 架构与 ADR [`02`](02-架构评审与ADR.md) / 开发与工程实践 [`03`](03-开发与工程实践评审.md) /
> S-1 执行计划 [`04`](04-S-1-执行计划.md) / Bootstrap 计划 [`05`](05-Bootstrap-实施计划.md)。
> **父项目**：[`LangAIQuanta`](../LangAIQuanta)（下称 **L**）。
> **性质**：**独立分支**，拥有自己的目标函数、保证级别表（`H-LS-*`）、edition 与信任边界；
> 不继承 L 的「无 UB / 无引用 / 无并发」承诺。
>
> **纪律（沿用 L 的方法论）**：
> 1. 本文所有「能 / 会 / 优于」均为**待验证提案**，不是结论；
> 2. 任何性能或 AI 生成率结论必须绑定 `run-id + protocol + 指纹` 后才可引用；
> 3. 不可判定的性质必须登记进 §12 的诚实降级表，禁止写成「已保证」；
> 4. 语法以未来的 `spec/langSysQuanta.ebnf` 为唯一权威，本文的代码块是**草案示意**；
> 5. 术语以 §15.1 为准：**mode（模式）/ cap（权限令牌）/ effect（效果）/ region（区域）**
>    是四个不同概念，不得混用（初稿 0.1.0 的主要缺陷之一）。

---

## 0. 摘要

**LangSysQuanta（L-Sys）** 是 LangQuanta 的**系统编程分支**，目标是：

> 在保留 L 的「AI 可生成 / 可修复 / 可验证」管线的前提下，
> 提供一套**不要求显式生命周期注解**、**安全子集无 UB**、**可显式控制内存与硬件**、
> 并且**原生面向 AI 生成与自动修复**的系统级语言。

它不是「L 加几个关键字」，而是一次**换核**：

| 维度 | L（主线） | L-Sys（分支） |
|---|---|---|
| 定位 | 自改系统的可信执行/采纳底座 | 系统编程语言（对标 C/Rust，兼容 C++ 的迁移面） |
| 内存 | 值语义，无引用/生命周期 | 值语义 + 区域 + **模式（mode）** + 显式分配器 + `unsafe` |
| 并发 | Out-of-scope（H-6） | 一等公民，按**并发域**划分，数据竞争自由由 mode 规则保证 |
| 后端 | Rust 解释器 | LLVM/Cranelift 原生 + `no_std` + C ABI |
| 预算 | 默认有限 | `profile agent` 有限；`profile kernel` 精确控制 |
| 保证 | 语言内无 UB | **安全子集**无 UB（UB 清单见 §8.1）；`unsafe` 有边界、可审计 |
| 共同点 | EBNF 权威、约束解码、结构化诊断、能力/效果、确定性、可复现 | 同左 |

**一句话**：L-Sys 想证明的是——
**「系统语言可以既像 C 一样可控、又不像 Rust 那样要求人（和 LLM）做生命周期代数。」**

**差异化的真正落点**（修订）：不是「模型能写」，而是
**「模型写错后，错误可局部归因、修复可机器应用、且修复不会扩大 unsafe 面积」**。

### 0.1 相对 `0.1.0-draft` 的修订

| # | 修订 | 消解评审项 |
|---|---|---|
| R-1 | 新增 **UB 清单**（§8.1，15 条，逐条给检测方式与诊断码） | P0-7 |
| R-2 | 定义 **三个正交轴**：region 格 / mode 格 / cap 令牌，并给出 gate matrix（§4.1、§6.2） | P0-4/5 |
| R-3 | **region 不再作为类型或参数**；跨过程分配通过 `Alloc` 句柄（区域 ρ 只出现在推断类型） | P0-1 |
| R-4 | **删除安全 `thaw`**；`iso → val` 单向，还原只能 `recover {}`（线性消费别名）或运行期见证 | P0-2 |
| R-5 | 别名规则改为**区域级**可判定规则（R1–R8），并给出约束推断算法与最小不可满足核 | P0-3 |
| R-6 | `unsafe` 门槛改为「作用域内存在 `Cap[Unsafe]` **值**」，令牌只能签发 | P0-4 |
| R-7 | 重写 §5.9 黄金样例（正确、无 UB、可被检查器接受），并补「安全版 / `unsafe` 版」对照 | P0-6 |
| R-8 | 新增 **C++ 取舍表**（§2.2） | 评审 §4 |
| R-9 | 新增 MMIO/volatile、DMA 令牌、中断域与锁 rank（§4.7、§5.7） | P1-2/3 |
| R-10 | 新增 Drop/panic/错误模型/栈与递归（§6.6、§5.8） | P1-4/5/6 |
| R-11 | 新增 `comptime` 求值模型、单态化策略、coherence 选择、无 turbofish 决策（§6.5、§5.2） | P1-7/8 |
| R-12 | 新增包管理/构建/供应链最小设计（§6.8） | P1-9 |
| R-13 | AI 层补：契约（可检查意图）、系统语义进类型、诊断预算、AST patch、修复成本指标、禁止自动加 `unsafe` | 评审 §3 |
| R-14 | 路线改为 **S-1 → S0′ → S0″ → S1…S5**；`H-LS-*` 表拆为「当前级别/目标级别/升级证据」，补 H-LS-15…19 | P0-8、评审 §6 |
| R-15 | **安全子集改为闭包定义 + `Trusted` 集合**（§8.2）；新增 `#[trusted]`/`#[forbid(unsafe)]` | A1 |
| R-16 | 新增 **TCB 清单**（§8.0），加载器、`comptime`、内建属性入 TCB | A2 |
| R-17 | `Mmio[T]`/`Alloc[Region]`/`Slice` 定为 **affine**；cap 只能**借出**视图（§4.3、§4.7） | A3 |
| R-18 | **v0 不做 cap 撤销**，删除「可吊销」表述，登记 `H-LS-20` | A3/ADR-4 |
| R-19 | profile 改为 **crate 图分区 + `#[boundary]` trampoline**（§5.1、§6.3） | A4 |
| R-20 | 新增 **镜像格式 / 加载协议 / cap 授予**（§6.12） | A5 |
| R-21 | 新增 **成本模型**（§6.10）与 `ls cost` | A6 |
| R-22 | 新增 **分析模块化边界**（§6.11），决定 G-S5 可行性 | A7 |
| R-23 | 补 `static`/`cell`/`shared` 语义（§4.10、§6.2），修正 C1/C2/C5 | C1/C2/C5 |
| R-24 | `release(self)` 消费 + 返回 `Result`；新增 `#[fault]`；错误合并预算（§5.8） | C4/C6/C12 |
| R-25 | 新增 `explore/seal` 等价性与认证构建 `--guards=keep`（§8.6） | ADR-9 |
| R-26 | 新增 H-LS-20…24、决策 D14…D22；S-1 交付物对齐 02 | 架构层 |
| R-27 | **Trusted 治理**：`trusted.lock` 内容寻址 + 逐项目钉住 + 失败关闭 + advisory（ADR-15） | 未决 1 |
| R-28 | **加载器密钥**：Ed25519 + root/build 双层 + dev/prod 分离 + 防回滚 + 平台 MMIO 策略（ADR-16） | 未决 2 |
| R-29 | **跨 crate impl**：trait 默认 `#[open]`，orphan 规则，`#[sealed]` 显式，`#[orphan]` 推迟 S4（ADR-17） | 未决 3 |
| R-30 | 新增 **03 开发与工程实践评审** + 三份硬模式档案（视图/递归/自引用）作为 S-1 验收清单 | 开发/工程 |
| R-31 | 新增 §4.11 **可返回视图与 Cursor**：`val` 字段可返回、`ref` 字段不可返回（ADR-19） | 档案 A |
| R-32 | kernel **有界递归**逃生舱 `#[recursion(bound=N)]` + 静态栈上界（D31） | 档案 B |
| R-33 | 新增 `defer` / `#[must_release]` / `E-LS-LEAK`，解决错误路径泄漏（D32） | 档案 C |
| R-34 | 新增 **模块级 `#[cap]` 上下文** + 每模块 `#[bounds]/#[overflow]/#[fp]` 旋钮（ADR-18） | D4/D10 |
| R-35 | 补 **裸机属性集**（`no_mangle`/`link_section`/`used`/`naked`/`repr(transparent)`/`union`）+ asm 操作数（D34） | D7 |
| R-36 | `ls svd` / `ls bindgen` / `ls gen` 为一等构建步骤；`[target]` 矩阵（D35） | D6/E3/E4 |
| R-37 | 工具链前移：LSP/SARIF/`ls explain`/`@generated` 到 S1（D36） | E2/E7 |
| R-38 | S-1 砍单为「4 spec + 三份档案 + baremetal」；新增交付 L/M/N/O/P | E10 |
| R-39 | 新增 **§1.5 适用场景与非目标场景**；把「手机 OS/App」明确写入 §1.2 非目标 | 场景误读 |
| R-40 | 新增 [`04-S-1-执行计划.md`](04-S-1-执行计划.md)、`tools/doc-lint`、`dossiers/`、`results/`、`tests/conformance/` | S-1 启动 |
| R-41 | 新增 [`05-Bootstrap-实施计划.md`](05-Bootstrap-实施计划.md) + `spec/bls.md` + `bootstrap/`；ADR-28…30；编译器策略改为「Rust 参考 + C seed/B-LS 无依赖链」 | 依赖最小化 |

---

## 1. 定位

### 1.1 目标（G-S）

按优先级排序，冲突时以编号小者为准：

| 代号 | 目标 | 可验收判据（初稿） |
|---|---|---|
| **G-S1** | **安全系统编程**：安全子集无 UB、无越界、无 UAF、无数据竞争 | 负例套件全拒（对照 §8.1 UB 清单）；`explore` 守卫覆盖核心语义；fuzz 无崩溃 |
| **G-S2** | **可控底层**：内存布局、分配、MMIO、FFI、中断、DMA 可按需显式控制 | 5 个系统试金石（§9 S0″）至少 3 个在安全子集内表达；其余有清晰 `unsafe` 边界与契约 |
| **G-S3** | **AI 可生成/可修复**：生成-验证成功率与修复成本达到冻结阈值 | 四臂评测（§10）；`first_check_rate` / `resolved_rate` / `UB_rate` / `repair_diff_bytes` |
| **G-S4** | **确定性/可复现**：逐位浮点、确定性布局、可复现构建 | 构建指纹一致；跨平台浮点逐位一致（登记 FP 子集） |
| **G-S5** | **迭代速度**：编译/检查时间不成为 AI 闭环瓶颈 | 增量检查 < 200ms / 10kLOC；冷编译 ≤ Rust 同规模项目的 0.5× |

> **G-S5 是本版新增**。评审指出：AI 闭环是**编译时间受限**的；若 L-Sys 继承 Rust 的编译慢（R-5），
> 则 G-S3 的「修复轮数」会被编译时间吃掉。故编译时间升为一等目标，可与 G-S2 冲突时优先。

> **与 L 的 G1/G2 的关系**：G-S3 对应 L 的 G1（AI 可生成），但**目标是系统任务**；
> L 的 G2（RSI）在 L-Sys 中降为**可选上层**（复用 L 的 `Artifact`/`Proof`/adoption），
> 不作为 L-Sys 的核心承诺。

### 1.2 非目标（明确不做）

| 非目标 | 理由 |
|---|---|
| 取代 L 主线 | 两者目标函数不同；L-Sys 是 fork，不是下一个 edition |
| 编译器自举（S5 前） | 三阶段方案见 [`05`](05-Bootstrap-实施计划.md)；S5 前不做，S5 后按 readiness 评估（ADR-28 / `H-LS-8`） |
| 用户可扩展的宏 / 过程宏 | 违反 EBNF 权威与约束解码；用 `comptime` + **封闭属性集**替代 |
| GC / 托管运行时 | 与系统编程的确定性资源控制冲突 |
| 完整内核形式化验证 | 研究级成本；只承诺安全子集的核心定理 |
| 短期超越 C/Rust 生态 | 生态靠 C ABI 借力，不重复造轮子 |
| 完整的 Rust 式生命周期 | 本文的核心赌注就是**不引入显式生命周期注解** |
| 构建脚本（build script） | 它是宏/UB 的后门（`LS-12`）；构建只由 manifest 描述 |
| C++ 源码级互操作（早期） | 只做 C ABI；C++ 通过 `extern "C"` 包装层（§2.2） |
| **手机 OS / 手机系统框架** | 不在本分支路线；需独立「L-Sys/OS」分支与 ADR-21…27（进程/MMU/IPC/cap 撤销/SMP/驱动/TEE） |
| **手机 App（Android/iOS）** | 无 UI/运行时/动态加载/商店；最多作为 native 库经 C ABI 使用 |
| 通用应用 / 前端 / 脚本语言 | 无 GC、无 UI、生态为零；与系统语言目标冲突 |

### 1.3 与主线 L 的 fork 边界

L-Sys **必须**独立维护以下内容，不得回灌 L 的承诺：

1. **保证级别表**：`H-LS-*`（§12），与 L 的 `H-1…H-18` 分开；
2. **edition**：`ls 0.x`，与 L 的 `0.x` 分开；
3. **语法权威**：未来的 `spec/langSysQuanta.ebnf`，不与 L 的 EBNF 混用；
4. **信任边界**：L-Sys 的 `unsafe` 是语言的一部分；L 的「无 UB」不适用于 L-Sys；
5. **工具链**：L-Sys 需要原生后端；L 保持解释器。
6. **TCB 与部署链**：加载器、镜像格式、cap 授予在 L-Sys 的 TCB 内（§8.0、§6.12）；
   这一点不继承 L 的「解释器内无 UB」假设。

> **复用**：EBNF→GBNF 约束解码、诊断 schema 与 fix-it 机制、`explore/seal` 双模式、
> `Cap[T]` 的**签发/消费点**方法论（注意：L 的 `Cap` 是权限令牌，与 L-Sys 的 `mode` 不同，见 §15.1）、
> `eff(...)` 效果框架、确定性/指纹/可复现构建方法论、`Proof`/`Witness`/adoption 的上层设计。

### 1.4 架构基线（S-1 交付物 A）

> 本节是 [`02-架构评审与ADR.md`](02-架构评审与ADR.md) 与
> [`03-开发与工程实践评审.md`](03-开发与工程实践评审.md) 的入口。
> 00 定义**语言内部语义**；02 定义**保证由谁执行、边界在哪、失败时怎样、代价多少、怎么演进**；
> 03 定义**能不能真的写系统代码、工程团队会不会第一周放弃**。
> 三者冲突时：语义以 00 为准，边界/部署/成本以 02 的 ADR 为准，交付与验收以 03 的档案为准，并在 00 登记。

六层架构与信任链：

| 层 | 职责 | 关键契约 | 是否 TCB |
|---|---|---|---|
| L1 语言核心 | 值/mode/region/effect/契约语义 | EBNF + 小步语义 | 规范 |
| L2 检查器 | region/mode/cap/effect/契约判定 | 诊断码 + 最小不可满足核 | **是** |
| L3 代码生成 | 零成本消解、守卫、ABI | 成本模型（§6.10） | **是** |
| L4 链接与镜像 | 段布局、ABI 协商、cap 表 | 镜像格式（§6.12） | **是** |
| L5 加载器 | 验签、映射、授予 cap | cap 表 + 签名 | **是** |
| L6 运行时 | 预算、原子、中断、故障 | profile 契约 + fault hook | 部分 |

**架构核心命题**：

> **语言承诺的执行点在加载器（L5），而不是检查器（L2）。**
> 若加载器不按清单授予 `Cap[Mmio[a..b]]`、不隔离地址空间，整套 cap 故事只是编译期装饰。

五张架构图（TCB / 信任闭包 / 部署链 / 运行时边界 / 分析模块化）见 02 §4。
S-1 的交付清单与枪毙条件见 02 §6；三份硬模式档案与工程验收见 03 §4/§5。

### 1.5 适用场景与非目标场景（新增，R-39）

> **当前状态是 Draft、无编译器**。本节的「可用」均为**路线判断**，不是现状；
> 任何对外表述必须绑定 §9 的阶段与 §12 的 `H-LS-*` 级别。
> 判定规则：只有「能在安全子集内表达 + `unsafe` 原语 ≤ 预算 + HIL 通过」的场景才算可用（03 §4）。

| 场景 | 判定 | 最早阶段 | 关键依赖 / 阻碍 | 依据 |
|---|---|---|---|---|
| **MCU 裸机固件**（Cortex-M / RISC-V） | **目标场景** | S2 试点；S3/S4 产品（非安全关键） | 工具链/调试/HIL/SVD/RTOS 适配 | 03 V1/V3、ADR-20 |
| **RTOS 应用 / 驱动** | **目标场景** | S3 | RTOS 适配层、`spawn` 契约、分配器契约 | 03 D8/档案 C |
| 嵌入式 Linux 用户态原生服务 | 条件性 | S4+ | POSIX/libc、动态链接、sysroot | ADR-12/15 |
| 嵌入式 Linux 内核模块 | **不推荐** | — | 跨 C ABI 后安全承诺失效（H-LS-5） | §8.2 |
| Android 原生库（NDK） | 远期条件性 | 未排期 | JNI/NDK/打包/权限模型 | 非目标 |
| Android 系统服务 / HAL | **不在范围** | — | Binder/AIDL/HIDL/框架 | 需新分支 |
| **手机 OS / 系统框架** | **不在范围**（需新分支 L-Sys/OS） | 未排期 | 进程/MMU/IPC/cap 委托撤销/SMP/驱动/TEE | ADR-21…27（见下） |
| **手机 App（Android/iOS）** | **不适合** | — | UI/运行时/动态加载/商店/平台互操作 | §1.2 |
| 通用应用 / 前端 / 脚本 | **不适合** | — | 无 GC/无 UI/生态为零 | §1.2 |

**为什么手机 OS 不在本分支**：它不是「内核 + 驱动」，而是进程/地址空间/权限/IPC/电源/安全的组合。
当前语言缺少 7 项基础（grep 可验证：无 MMU/页表/syscall/IPC/SMP/TEE/动态链接）：

| # | 手机 OS 必需 | 当前现状 | 需要的新 ADR |
|---|---|---|---|
| 1 | 进程、虚拟内存、页表、用户/内核边界、syscall ABI | 无 | ADR-21 |
| 2 | IPC + 能力委托/撤销 | cap 为编译期 + loader 授予；v0 **不可撤销**（ADR-4） | ADR-22 |
| 3 | SMP / big.LITTLE / 调度 / 功耗 / 热 | 只有 Thread/Irq/Dma | ADR-23 |
| 4 | 驱动/总线模型（PCIe/USB/I2C/SPI/MIPI/IOMMU/PM） | 只有 MMIO/DMA 原语 | ADR-24 |
| 5 | TEE/TrustZone、逐应用沙箱、keystore、attestation | 只有镜像签名 + 防回滚 | ADR-25 |
| 6 | 动态链接、稳定 ABI、sysroot、多语言互操作 | 只有静态镜像 + C ABI | ADR-26 |
| 7 | 认证与工具鉴定（ISO 26262 / IEC 61508 / MC-DC） | 未设计 | ADR-27 |

> **门槛**：上述 7 项至少前 3 项有 ADR + 可执行原型，才允许把「手机 OS」写入任何路线图；
> 在此之前，任何「可用于手机系统」的表述都是**误读**，按 `H-LS-10`（生态规模）与 `H-LS-1`（安全子集覆盖）处理。

**与目标的关系**：G-S1…G-S5 的验收对象是 **MCU/RTOS 系统代码**；
手机 OS 需要新的目标函数（进程隔离、SMP、功耗、TEE、认证），不得复用本分支的保证级别。

---

## 2. 问题陈述：我们要解决什么

### 2.1 C 的问题

| # | 问题 | 后果 |
|---|---|---|
| C-1 | 未定义行为（UB）无处不在 | 优化器可做任意假设；安全漏洞的温床 |
| C-2 | 手动内存 + 裸指针 | 越界、UAF、double free、泄漏 |
| C-3 | 弱类型/隐式转换/无泛型 | 类型错误在运行期才暴露 |
| C-4 | 无模块/包管理/构建碎片化 | 工程规模难以治理 |
| C-5 | 并发内存模型弱（C11 原子之外） | 数据竞争难以静态发现 |
| C-6 | 诊断弱、无自动修复 | LLM 生成「看似对、实则 UB」的代码 |

### 2.2 C++ 的问题（本版新增）

初稿 0.1.0 的目标写了「解决 C++ 问题」，正文却没有 C++ 的问题陈述。补齐如下。

| # | 问题 | 后果 | L-Sys 立场（§2.5） |
|---|---|---|---|
| X-1 | 模板元编程 / SFINAE / 重载决议 | 错误信息不可读；编译期爆炸；文法不可 EBNF 化 | 替换：泛型 + 有界 `comptime` |
| X-2 | 多重继承 / 虚基类 / 菱形 | 布局与转换规则复杂，ABI 不稳 | 拒绝：trait + 组合 |
| X-3 | 异常 + 栈展开 + 析构交互 | 隐式控制流；`noexcept` 传染；跨 ABI 危险 | 替换：`Result` + `panic=abort` |
| X-4 | RAII 与析构顺序隐式 | 资源释放时机依赖作用域细节 | 受限：`agent` 允许 `Drop`，`kernel` 强制显式 `release` |
| X-5 | 宏 / 预处理器 | 文法不唯一，约束解码失效 | 拒绝：封闭属性集 + `comptime` |
| X-6 | 头文件 / ODR / 链接期重复定义 | 构建脆弱；符号冲突延迟到链接 | 替换：模块 + 单一定义 |
| X-7 | 隐式转换 / 转换运算符 | 静默精度丢失、意外构造 | 拒绝：只有显式 `as` |
| X-8 | 未定义求值顺序（`f(i++, i)`） | 不可复现、不可验证 | 禁止：规范求值序（UB-12） |
| X-9 | `constexpr` 任意计算 | 编译期风险与时间不可控 | 受限：fuel 有界、无副作用、无 IO |
| X-10 | 移动后使用 / 迭代器失效 / 切片 | 静默错误，静态不可查 | 替换：mode + 借用检查 + `Slice` 视图 |
| X-11 | 无稳定 ABI | 跨编译器/跨版本不可链接 | 片段：`extern "C"` 子集按 edition 冻结 |

### 2.3 Rust 的问题

| # | 问题 | 后果 |
|---|---|---|
| R-1 | 借用检查/生命周期学习曲线陡 | 人难学；**LLM 极难写对** |
| R-2 | 生命周期注解 `'a` 需要全局推理 | 生成-修复轮数高 |
| R-3 | `async` 染色、trait coherence、孤儿规则 | 组合复杂度高 |
| R-4 | 宏系统（声明宏/过程宏） | 文法不可完全 EBNF 化；约束解码失效 |
| R-5 | 编译慢、单态化膨胀、二进制大 | 迭代成本高（**对 AI 闭环尤其致命**） |
| R-6 | `unsafe` 是悬崖 | 审计困难；生态 soundness 风险 |
| R-7 | 无稳定 ABI | FFI 摩擦大 |
| R-8 | 浮点/布局跨平台不保证逐位一致 | 可复现性弱 |

### 2.4 共同问题（对 AI 尤其致命）

- **错误不便宜**：语法/类型/借用错误没有结构化 fix-it，LLM 只能盲试；
- **语义不可判定**：C 的 UB、Rust 的 trait 求解/宏展开让「生成即可验证」困难；
- **文法不唯一**：多写法 + 宏扩展，使约束解码难以覆盖；
- **资源不可控**：无 budget，生成代码可能打死宿主；
- **意图不可检查**：没有契约/typestate，模型只能靠运气写对系统语义；
- **修复会扩大攻击面**：模型遇到类型错误就包一层 `unsafe`（必须在策略层禁止）。

### 2.5 设计含义

> 如果 L-Sys 只是「Rust 的另一种语法」，它必输（EL-1 熟悉度 + 生态）。
> 它必须在一个**正交维度**上赢：**让内存安全不需要生命周期代数**，
> 从而让 AI 的「生成→诊断→修复」闭环真正收敛。

三条必须同时成立的因果链：

1. **无注解** ⇒ 错误可归因到「引用的存活期超界」，而非 `'a: 'b` 约束求解；
2. **单一规范形 + 无宏** ⇒ 语义错误可局部定位 ⇒ fix-it 可机器应用；
3. **系统语义进类型**（mode / typestate / 锁 rank / 原子序 / DMA 令牌）⇒ 模型的典型错误被类型拒绝，
   而不是留到运行期。

---

## 3. 设计原则

### 3.1 继承自 L（不妥协）

| # | 原则 | 判据 |
|---|---|---|
| **LS-P1** | **文法即权威**：`spec/langSysQuanta.ebnf` 是唯一语法定义 | EBNF 接受集 == 实现接受集；可导出 GBNF |
| **LS-P2** | **单一规范形**：每个概念一种写法；`lsfmt` 幂等 | `format∘format = format` |
| **LS-P3** | **机器可判定**：静态规则产出结构化诊断 | 每条规则有 code + span + 正/负例 |
| **LS-P4** | **边界显式**：`unsafe`/`Ffi`/`Hw`/`Asm`/`Alloc`/`Dma`/`Irq` 必须显式 | `seal` 缺失即错误 |
| **LS-P5** | **双模式**：`explore` / `seal` 同语法 | 差异不止诊断强度（explore 插守卫） |
| **LS-P6** | **诚实降级**：不可判定性质集中登记 | §12 与正文双向满射 |
| **LS-P7** | **确定性**：浮点逐位、布局确定、构建可复现 | 指纹一致 |
| **LS-P8** | **最小信任核**：验证器/检查器与运行时边界清晰 | 隔离测试 |
| **LS-P9** | **可演进**：变更绑定 edition，旧版冻结 | 迁移器 + 冻结套件 |

### 3.2 替换自 L（关键差异）

| L 的设定 | L-Sys 的替换 | 理由 |
|---|---|---|
| 无引用/无生命周期 | **有引用，但无生命周期注解**（region 推断 + mode） | 系统需要引用，AI 不需要 `'a` |
| 语言内无 UB | **安全子集无 UB**；`unsafe` 内有边界 | 裸机/MMIO 无法避免 |
| 并发 Out-of-scope | **并发一等公民**（按并发域划分） | 系统编程必需 |
| 解释器 | **原生后端** | 系统性能/裸机 |
| 编译器用 Rust（H-8） | **Rust 参考实现 + C seed/B-LS 无依赖链**（05）；汇编仅 stage0/runtime | 两条链共用 conformance |

### 3.3 新增

| # | 原则 | 判据 |
|---|---|---|
| **LS-P10** | **无生命周期注解**：用户不写 `'a`；存活期由约束推断完成 | EBNF 中不存在 lifetime 参数 |
| **LS-P11** | **模式即别名边界，令牌即权限边界**：二者分离，不混用 | gate matrix（§6.2）逐项可查 |
| **LS-P12** | **AI 错误可修复**：所有常见错误必须带至少一条 fix-it | `fixit_applicable_rate` |
| **LS-P13** | **零成本默认**：mode/region 在编译期消解；守卫只在 `explore` 出现 | 汇编/IR 检查 |
| **LS-P14** | **迭代优先**：编译/检查时间是一等目标 | G-S5 判据 |
| **LS-P15** | **意图可检查**：公开 API 鼓励写 `requires/ensures`，`explore` 变守卫、`seal` 变义务 | 契约覆盖率 + 属性测试生成率 |
| **LS-P16** | **系统语义进类型**：锁序、原子序、初始化状态、DMA 归属用类型表达 | 对应错误在编译期出现 |
| **LS-P17** | **修复不扩大攻击面**：自动修复**禁止**新增 `unsafe`/令牌/`Ffi` | `unsafe_delta ≤ 0`（硬门禁） |
| **LS-P18** | **文法无歧义**：不引入需要上下文消歧的语法（如 turbofish） | EBNF 单义；见决策 D2 |
| **LS-P19** | **工程可用性同期**：语言特性与入门路径/调试/工具链同期交付，不推迟到 S4 | `time_to_first_blinky ≤ 2h` |
| **LS-P20** | **每模块旋钮**：安全/成本取舍可在模块级显式降级，且有契约与 CI 证据 | 降级点密度 + `ls cost` |

> **LS-P19/P20 是 03 的直接产物**：过程纪律再好，工具与入门路径缺失也会让团队在第一周放弃；
> profile 级旋钮太粗，会逼出「全局关检查」或「unsafe 上移」。

---

## 4. 核心设计赌注：内存模型

> 这是整个分支的成败点。先用 §9 S0′/S0″ 的试金石验证，再投入后端。

### 4.0 三个正交轴（修订核心）

初稿 0.1.0 把「所有权模式」和「权限令牌」都叫「能力」，导致 `unsafe(Cap[Unsafe])` 沦为装饰。
本版拆成三轴：

```
一、生命期区域 ρ   local(s) ⊑ region(R) ⊑ thread ⊑ heap(H) ⊑ static
                   ——— 只出现在推断类型与诊断中，源码不写（决策 D4）

二、所有权模式 m   uniq | frozen | mut | atom | raw
                   对应源码：box/iso | val | ref | shared | rawptr
                   ——— 类型限定符，有格结构与转换规则

三、权限令牌 c     Cap[Unsafe] / Cap[Alloc] / Cap[Mmio[a..b]] / Cap[Dma] / Cap[Ffi] / Cap[Spawn]
                   ——— 线性值，只能由登记签发点产生；v0 不可撤销（H-LS-20）
```

> **命名纪律**：正文一律用 **mode** 指 `box/iso/val/ref/shared/rawptr`，
> 用 **cap** 指 `Cap[...]`，用 **effect** 指 `eff(...)`。三者不得互换。

### 4.1 值语义（默认）

- 所有值默认**拥有**、可 `copy`（仅平凡类型）或 `move`；
- 无隐式别名；无 GC；
- 复合类型（`struct`/`enum`/`Array`）默认内联，`box` 显式堆分配；
- `move` 后源位置失效（`E-LS-MOVE`）；`copy` 只对 `T: Copy`（无析构、无 `uniq` 字段）。

### 4.2 区域（region）：只是分配区域，不是类型

```ls
region R {
    let a: Alloc[Region] = R.allocator();
    let buf: box[Array[U8, 4096]] = a.alloc(Array.zeroed());   // ρ = R（推断）
    let node: box[Node] = a.alloc(Node { next: Option.None, value: 1 });
    // ...
} // R 结束：按分配逆序释放；`buf`/`node` 的 box 不再可用
```

规则：

- `region R { ... }` 引入**分配区域**，区域内 `Alloc[Region]` 产生的 `box` 都归 `R`；
- 区域结束时**统一释放**（无需逐个 free；析构顺序见 §6.6）；
- `box` 可以 `move` 出区域吗？**不可以**（否则悬垂，`E-LS-REGION-ESCAPE`）；
  需要「带出」时复制值，或改用 `Alloc[Heap]`；
- 区域可嵌套；内层区域随其块结束而结束；
- **`region` 不是类型、不是参数、不是字段、不可存储**；
  跨过程「在调用者区域分配」通过传入 `Alloc[Region]` 句柄完成，ρ 由调用点推断（决策 D4）。

> **这一条彻底消解了 0.1.0 的 §4.2/§6.1/§5.9 三重矛盾**：
> 源码只出现 `region R`（块标签）与 `Alloc`（可传值），ρ 永远在推断类型里。

**`Alloc` 与 `Cap[Alloc]` 的区别**：`Alloc[Heap]`/`Alloc[Region]` 是分配器**句柄值**（不携带权限，
可自由传递）；「能否分配」由 `Cap[Alloc]`（`kernel` 必须显式）+ 实际传入的句柄共同决定。
`agent` 下 prelude 提供 `heap_allocator()`；`kernel` 下由启动代码签发。

### 4.3 模式（mode）与源码写法

| 源码类型 | 核心模式 | 语义 | 可跨并发域 | 可别名 | 可写 | 释放方式 |
|---|---|:--:|:--:|:--:|:--:|---|
| `box[T]` | `uniq` | 唯一拥有（堆或区域） | 否* | 否 | 是 | 所有者 drop / 区域结束 |
| `iso[T]` | `uniq` | 唯一拥有 + **可转移** | **是** | 否 | 是 | 所有者 drop |
| `val[T]` | `frozen` | 冻结/只读 | 是 | 是 | 否 | 随所属值 |
| `ref[T]` | `mut` | 独占临时借用 | 否 | 受检（唯一） | 是 | 借用结束归还 |
| `shared[T]` | `atom` | 共享（锁；原子用 `shared[Atomic[T]]`） | 是 | 是 | 受同步保护 | 随所属值 |
| `rawptr[T]` | `raw` | 裸指针（仅 `unsafe`） | 不保证 | 是 | 是 | 手动 |

\* `box` 是「线程/区域局部」的唯一所有者；需要跨域移动时**必须**先转为 `iso`（`transfer`），
这是一次显式的、可审计的所有权移交。理由：让 `spawn` 的签名自己说明风险，避免隐式跨线程。

**补充（容器类型，不是 mode）**：

- `box[T]` 支持隐式解引用（`b[i]` ≡ `(*b)[i]`，`b.len` ≡ `(*b).len`）；
- `cell[T]`：**单域内部可变**容器，`get`/`set`，带 `Local` 效果，**非 Copy**；
  用于 `val` 下需要「读时可变」且不跨域的场景（决策 D14）；
- `shared[T]`：**锁语义**（`lock` 返回 `Guard`），带 `Atomic` 效果；
  需要原子指令时用 `shared[Atomic[T]]`（提供 `fetch_add` 等）；
- `Slice[T]`：只能以 `val[Slice[T]]`/`ref[Slice[T]]` 出现；**裸 `Slice` 不作为值传递**
  （否则复制即别名，与 R5 冲突）。

**转换规则（全部单向或受控）**：

| 转换 | 语法 | 条件 | 可逆？ |
|---|---|---|---|
| `box → iso` | `transfer b` | `b @ H`（堆）且 `T` 无区域引用（`T: 'heap`） | 否 |
| `iso → val` | `freeze q` | 无 | **否**（单向，决策 D5） |
| `val → iso` | `recover { q }` | 块内**消费全部别名**（线性检查） | 受控 |
| `ref → val` | `val r` | 借用期内只读 | — |
| `box/iso → ref` | `borrow mut x as r` | 作用域内独占 | 归还 |
| `raw → ref` | 仅 `unsafe` + 契约 | 契约 | — |

> **`thaw` 已删除**（0.1.0 的 `thaw: val→iso eff(Unsafe)` 是 soundness 漏洞：
> `val` 可别名，凭空造唯一性 ⇒ 数据竞争）。
> 需要还原唯一性时：`recover {}`（静态）或 `unsafe` + **运行期唯一性见证**（`rc == 1`），
> 后者登记为 `H-LS-15`。

**仿射性（affine）与 cap → 视图派生**（决策 D15、D16）：

| 类型 | 仿射性 | 理由 |
|---|---|---|
| `Mmio[T]` | **affine（不可 Copy）** | 可 Copy 则一次 cap 派生无限副本，线性性被绕过 |
| `Alloc[Heap]` | `Copy` | 分配权由 `Cap[Alloc]` 把关，句柄本身无权限 |
| `Alloc[Region]` | **affine 且不可存字段** | 可存则 ρ 逃逸，region 又成一等值 |
| `DmaToken` | 线性 | 归属必须唯一 |
| `Slice[T]` | 只能经 `val`/`ref` | 裸复制即别名 |

- `cap.view(addr)` 从 `Cap[Mmio[a..b]]` **借出**一个 `Mmio[T]` 视图（R2 reborrow，不消费 cap）；
  同一 cap 同时最多一个活视图；多寄存器用 struct projection（`r.ctrl` 仍是 `Mmio[U32]`）；
- `addr` 为常量 ⇒ 编译期范围检查；非常量 ⇒ 运行期一次范围检查（成本见 §6.10）；
- `recover` **仅限单函数 + 同域**；跨域/跨模块禁止（别名集合不可追踪）——诚实降级，登记 `H-LS-15`；
- cap **不可撤销**（v0）：删除 0.1.0 的「可吊销」表述，登记 `H-LS-20`。

### 4.4 借用与逃逸（无生命周期注解）

```ls
fn fill[const N: USize](dst: ref[Array[U8, N]], v: U8) eff(Write) {
    for i in 0..N { dst[i] = v; }
}

fn use_buffer() {
    let mut buf: Array[U8, 16] = Array.zeroed();
    borrow mut buf as b {
        fill(b, 0xFF);
    }
    // b 在块结束失效；buf 重新可写（reborrow 归还）
}
```

**检查规则（R1–R8，全部可局部检查）**：

| # | 规则 | 诊断 |
|---|---|---|
| **R1** | `uniq` 无别名；`move` 后源失效 | `E-LS-MOVE` |
| **R2** | `uniq` 可在作用域 s 内借出 `ref`，s 结束归还（reborrow） | `E-LS-ALIAS` |
| **R3** | `uniq --freeze--> frozen` 单向；`recover {}` 内消费全部别名方可回 `uniq` | `E-LS-UNIQ` |
| **R4** | `ref @ ρ` 不可存入 ρ' ⊐ ρ 的位置（逃逸） | `E-LS-REGION-ESCAPE` |
| **R5** | 写 place 要求**其区域内**无 `frozen`/`ref` 别名（区域级，非全局） | `E-LS-ALIAS` |
| **R6** | `atom` 只能跨域共享，且带 `Atomic/Order` 或锁 rank | `E-LS-RACE` |
| **R7** | `raw` 仅在 `unsafe` 且作用域内存在 `Cap[Unsafe]` **值**时可用 | `E-LS-UNSAFE`/`E-LS-CAP` |
| **R8** | 跨域（`Thread`/`Irq`/`Dma`）移动只允许 `iso`/`atom` | `E-LS-RACE` |

**关于 R5 的代价声明**（0.1.0 缺失，必须诚实写清）：

`frozen`（`val`）一旦产生，其生命期等于所属区域，**该区域结束前不得再对该 place 取可变借用**。
这是「无生命周期注解」的**真实学费**：大结构不要轻易 `freeze`；需要「读时可变」时用
`shared[T]`/`cell[T]`（显式，带 `Atomic`/`Local` 效果）。
fix-it 会建议「缩小 region 作用域 / 改用 `cell` / 复制」——**不会**建议插入 `unsafe`（LS-P17）。

错误示例（应被拒绝）：

```ls
fn bad() -> ref[Int] {
    let mut x = 1;
    borrow mut x as r { return r; } // E-LS-REGION-ESCAPE
}
```

**这是相对 Rust 的核心差异**：用户只看到「这个引用逃出了 `R`」，
不需要理解 `'a: 'b` 的约束求解；fix-it 会建议 `val`/复制/移动。

### 4.5 推断算法（「无注解」的兑现方式）

1. **约束生成**：每个 `borrow`/`alloc`/`freeze`/`recover`/`spawn`/`store` 产生 `ρ1 ⊑ ρ2` 约束；
2. **求解**：在区域格上做并查集 + 最小上界；局部完成，不做全程序不动点；
3. **失败**：输出**最小不可满足核**（通常 2–3 条约束），映射为一句人话 + fix-it；
4. **fix-it 候选**（按代价排序）：缩小作用域 / 复制 / 改 `uniq` / 提升 region / 加 `recover`；
5. **禁止**：fix-it 不得生成 `unsafe`/新令牌/`Ffi`（LS-P17）。

S0′ 的 DoD 直接测量：**5 个试金石上的约束失败率与 fix-it 采纳率**。
未决：失败率阈值（§13 Q1，暂定 ≤ 30%，超过即按 `LS-14` 枪毙）。

### 4.6 `unsafe` 边界（令牌是值，不是语法）

```ls
// 令牌只能由登记签发点产生（main 签名 / 内核加载器 / 构建清单）
fn main(sys: Cap[Sys], uart: Cap[Mmio[0x4000_0000..0x4000_0fff]]) { ... }

fn poke(reg: ref[Mmio[U32]], v: U32) eff(Hw) {
    reg.write(v);          // MMIO 访问是「安全」的，只需 cap + Hw 效果（见 §4.7）
}

unsafe fn walk(head: rawptr[Node]) -> USize
    requires is_valid_list(head)
    ensures  result == list_len(head)
{
    // 只有这里能对 rawptr 解引用/算术
}
```

规则：

- **`Unsafe` 是边界效果，不向安全包装函数传播**：`unsafe fn` 在签名上暴露 `Unsafe`；
  普通 `fn` 内的 `unsafe {}` 视为实现细节，**不**给调用方增加 `Unsafe` 效果，但该模块必须
  带 `#[cap(Unsafe)]` 且被 `Trusted`/审计背书（否则 `seal` 拒绝）——这正是 `Mmio[T]`/slab
  能作为安全 API 的原因；
- **`unsafe fn` 隐含 `Unsafe` 效果**（调用方必须有 `Cap[Unsafe]`，且该调用进审计日志）；
- `rawptr` 只能在 `unsafe` 块/`unsafe fn` 内解引用/算术；
- `unsafe` 的门槛是**作用域内存在 `Cap[Unsafe]` 的值**（线性，用后失效），不是括号里写个字面量；
- `unsafe` 块内涉及的 `Hw`/`Asm`/`Ffi`/`Dma` 效果必须显式；
- 每个 `unsafe` 块产生**证明义务**（对齐、别名、provenance、初始化、长度），进审计日志；
- `seal` 模式下 `unsafe` **原语种类**（不是行数比例）与密度设阈值（CI 门禁，`W-LS-UNSAFE-DENSITY`）。

### 4.7 硬件边界：MMIO / volatile / DMA / 中断域（本版新增）

**问题**：0.1.0 用 `mmio()` 返回 `rawptr`，普通 store 会被优化器消除/合并/重排。
**修法**：MMIO 是一等地址空间类型，不是裸指针。

```ls
#[repr(C)]
struct Regs { ctrl: U32, status: U32 }

fn init(r: ref[Mmio[Regs]], a: Alloc[Heap]) eff(Hw, Alloc) {
    r.ctrl.write(1);                 // volatile 语义：不可消除、不可合并
    fence(Order.SeqCst);             // 顺序显式
    let st = r.status.read();        // `Hw` 效果；读取状态寄存器可标 #[nondet]
}
```

规则：

1. `Mmio[T]` 由 `Cap[Mmio[a..b]]` 在 `[a, b)` 内**借出**（`cap.view(addr)`）；越界 ⇒ `E-LS-CAP`；
2. MMIO 读写固定 `volatile` 语义；重排只能由显式 `fence(Order)` 约束；
   `Mmio[T]` 的**字段投影仍是 `Mmio`**（`r.ctrl` 的类型是 `Mmio[U32]`），不会退化成普通引用；
   `Mmio[T]` 是 **affine**：只能 move，不能 Copy；
3. DMA 用**线性令牌**表达归属：

```ls
fn start(d: Cap[Dma], buf: iso[Slice[U8]]) -> DmaToken eff(Dma) { ... }
fn wait(t: DmaToken) -> iso[Slice[U8]] eff(Dma, Block) { ... }
fn try_wait(t: DmaToken) -> Result[Option[iso[Slice[U8]]], DmaToken] eff(Dma) { ... }
fn on_complete(t: DmaToken, f: Fn[iso[Slice[U8]]]) eff(Dma) { ... }
```

   `DmaToken` 必须显式 `wait`；隐式丢弃 ⇒ `kernel` 下 `E-LS-DROP`，`agent` 下阻塞等待。
   ISR 中只能用 `try_wait`/`on_complete`（不可 `Block`）。
   这是用类型把「设备读缓冲区期间不得访问」编码进所有权，**不需要 unsafe**。
4. **并发域**：`Thread` / `Irq(level)` / `Dma`。跨域共享必须 `shared`（`atom`）；
   仅 ISR 独占、不与主循环共享的状态可用 `cell`（不跨域）；
   ISR 内禁止 `Alloc`/`Block`；`Irq` 效果必须上签名；
5. **锁 rank**：`Lock[T, const Rank: USize]`，`lock` 检查 rank 单调递增，且
   「持 rank ≤ R 的锁时不得开启 `Irq ≤ R`」⇒ `E-LS-IRQ`；
6. **内存序映射**：`Order` ∈ {`Relaxed`, `Acquire`, `Release`, `AcqRel`, `SeqCst`}，
   映射表按目标架构固定（ARM/x86/RISC-V），见 §6.10；`fence` 的语义跨架构一致，
   指令序列可不同。

> **能力模型只覆盖线程**是 0.1.0 的漏洞（H-LS-3 在内核场景不成立）。
> 本版把「中断域数据竞争自由」单列为 `H-LS-16`，不并入线程定理。

### 4.8 形式化义务（S5 目标）

1. region 约束推断的 soundness（含过程间区域多态）；
2. 逃逸/别名规则（R1–R8）的 soundness；
3. mode 规则 ⇒ 线程域数据竞争自由；
4. mode + `Irq`/`Dma` 规则 ⇒ 中断/DMA 域数据竞争自由（或明确降级，H-LS-16）；
5. `recover` 保持唯一性；
6. `unsafe` 契约的局部义务（对齐/别名/provenance/初始化/长度）；
7. 安全子集的无 UB 定理（在 §8.1 UB 清单与内存模型公理下）；
8. 指针 provenance 模型（建议采用 Tree Borrows 的简化子集）——**没有它，UB-10 无法定义**。

### 4.9 明确会被拒绝的写法（负例清单）

| 写法 | 错误码 | 原因 |
|---|---|---|
| 返回局部 `ref` | `E-LS-REGION-ESCAPE` | 引用逃逸 |
| `box @ R` move 出 `R` | `E-LS-REGION-ESCAPE` | 区域释放后悬垂 |
| 同时 `ref` 与 `val` 指向同一 place 且写 | `E-LS-ALIAS` | 区域级别名冲突 |
| 把 `ref` 存入全局/更长寿结构 | `E-LS-ESCAPE` | 存活期超界 |
| 跨线程传 `ref` / 跨域传 `box` | `E-LS-RACE` | mode 不允许 |
| `unsafe` 作用域内无 `Cap[Unsafe]` 值 | `E-LS-CAP` | 令牌缺失 |
| `rawptr` 在安全块解引用 | `E-LS-UNSAFE` | 需显式 unsafe |
| 使用未初始化内存 | `E-LS-INIT` | 初始化检查 |
| 使用已 move 的值 | `E-LS-MOVE` | 可移动性检查 |
| `val → iso` 无 `recover` | `E-LS-UNIQ` | 唯一性未恢复 |
| `kernel` 中隐式 `Drop` | `E-LS-DROP` | profile 禁止 |
| `kernel` 中递归 | `E-LS-RECURSION` | 静态栈分析 |
| MMIO 越出 `Cap[Mmio[a..b]]` | `E-LS-CAP` | 令牌范围 |
| 持低 rank 锁时开高优先级中断 | `E-LS-IRQ` | 锁 rank 检查 |
| 自动修复试图插入 `unsafe` | `W-LS-FIXIT-UNSAFE`（拒绝） | LS-P17 |
| 存储/复制 `Mmio[T]` | `E-LS-MOVE` | affine，不可 Copy |
| 将 `Alloc[Region]` 存入字段 | `E-LS-REGION-ESCAPE` | ρ 逃逸 |
| 同一 cap 同时持有两个 `Mmio` 视图 | `E-LS-ALIAS` | 借出唯一 |
| `static mut` | `E-LS-STATIC` | 语法不存在；用 `shared`/`cell` |
| 跨模块 `recover` | `E-LS-UNIQ` | 别名集合不可追踪 |

### 4.10 全局状态与 `static`（新增）

系统语言必需全局设备表/分配器实例，但 `static mut` 是 UB 温床。规则（决策 D17）：

```ls
static BOOT_MAGIC: val[U32] = 0x4C535953;          // 编译期初始化、不可变
static DEVICES: shared[DeviceTable] = ...;        // 跨域共享，锁/原子语义
```

- `static` 只允许 `val[T]` 或 `shared[T]`；**不存在裸 `static mut`**（`E-LS-STATIC`）；
- 初始化必须是 `comptime` 可求值常量，无运行期初始化顺序问题；
- `static` 默认位于 `static` 区域（§4.0 格的顶端），不可被区域释放；
- 单域可变的全局状态用 `static CELL: cell[T]`（带 `Local` 效果，仅限单线程 profile 的启动阶段）；
- 中断/线程共享必须 `shared`，并遵守 R6/R8。

### 4.11 可返回视图与 Cursor（新增，ADR-19）

> 零拷贝是系统语言的硬需求；但 `ref` 不可逃逸（R4）会让「返回视图」变得不可能。
> 本节的规则决定解析器/网络栈能否在安全子集内表达。验收见 03 §4.0 档案 A。

**规则**：

1. **`val` 字段可返回**：含 `val` 字段的结构体是**区域参数化**的（ρ 由源推断，源码不写 ρ）；
   返回值随源区域存活，源区域结束后使用 ⇒ `E-LS-REGION-ESCAPE`；
2. **`ref` 字段不可返回**：只能在借用作用域内存活；返回即 `E-LS-REGION-ESCAPE`；
3. **推荐 Cursor 模式**：`struct Cursor { src: val[Slice[T]], pos: USize }`——可返回、可 `ref` 可变；
4. `recover` 仍限**单函数 + 同域**；跨模块/跨域零拷贝归还暂不支持（H-LS-15）；
5. 可变视图用 `ref[Slice]` + 作用域内 API；需要跨函数可变视图时传 owner，不传 `ref`。

```ls
struct Packet { header: Header, payload: val[Slice[U8]] }   // 可返回

fn parse(src: val[Slice[U8]]) -> Result[Packet, Error] {
    // ...
    Ok(Packet { header: h, payload: src.view(4, n)? })
}

struct Cursor { src: val[Slice[U8]], pos: USize }           // 可返回
fn next_u8(c: ref[Cursor]) -> Result[U8, Error] { /* ... */ }

// 应被拒绝：
struct BadCursor { src: ref[Slice[U8]] }
fn bad(src: ref[Slice[U8]]) -> BadCursor { BadCursor { src } } // E-LS-REGION-ESCAPE
```

> **若档案 A 不能通过**：需引入显式 `View[T]`/生命周期参数，LS-P10 必须修订，
> 分支定位需重新评估（`LS-25`）。

---

## 5. 语法草案（示意，非最终）

> 语法以未来的 `spec/langSysQuanta.ebnf` 为唯一权威。本节的每个代码块都必须能被
> S0′ 的检查器接受（或明确标注「应被拒绝」）。

### 5.1 模块与 profile（单一写法，决策 D9）

```ls
#[cap(Unsafe, Mmio[0x4000_0000..0x4000_0fff])]
#[bounds(off, requires = "idx < len")]
#[overflow(wrapping)]
module drivers.uart;
profile kernel;
```

- `module` 每个文件一条，必须在文件首部（先于任何 item）；模块路径 = 文件树路径；
- `profile` 每个 crate 根一条：`agent` | `kernel`；子模块继承，不可覆盖（`E-LS-PROFILE`）；
- 不用 `#[profile(...)]` 属性，避免「属性带不带分号」的规范形分歧；
- **模块级 `#[cap(...)]`** 提供词法能力上下文（ADR-18）：入口检查一次，内部 `unsafe {}` 不再逐处传 cap；
  不可嵌套放宽、不可跨模块隐式继承；
- **每模块旋钮**：`#[bounds(off, requires=...)]`、`#[overflow(wrapping)]`、`#[fp(fast)]`；
  默认安全，降级必须有契约与 CI 证据（LS-P20）。

| profile | 溢出 | 越界 | fuel/depth/mem | 隐式 Drop | panic | 递归 |
|---|---|---|---|---|---|---|
| `agent` | checked（debug trap） | 守卫/检查 | 有限 | 允许 | abort | 允许（depth 限制） |
| `kernel` | wrapping（默认，显式 `checked_*`） | 检查或 `unsafe` 契约 | 无 | **禁止** | abort | **禁止** |

**profile 是 crate 图分区，不是诊断级别**（决策 D18）：

1. 依赖继承最严：`agent` crate **不得**依赖 `kernel` crate（manifest 期拒绝）；
2. **v0 禁止跨 profile 静态链接**；跨域只能经 `#[boundary]` + 任务/进程隔离；
3. `#[boundary]` 的参数只允许 `val`/`iso`/标量（不传 `ref`/`box`/`rawptr`）；
   预算与 cap 由 trampoline 编组，不在被调方隐式继承；
4. 跨域 `panic` 一律 abort，不 unwind；边界处必然有 trampoline，**没有隐式 ABI 兼容**。

> 实现细节与五张架构图见 [`02-架构评审与ADR.md`](02-架构评审与ADR.md) ADR-5 / §4.4。

### 5.2 声明

```ls
struct Node { next: Option[box[Node]], value: Int }
enum Irq { Timer, Uart(U8), None }
enum Option[T] { Some(T), None }
enum Result[T, E] { Ok(T), Err(E) }

fn add(a: Int, b: Int) -> Int { a + b }
```

- **变体构造唯一写法：`Type.Variant`**（`Irq.Uart(3)`、`Error.Full`、`Option.None`）；
  不存在 `Irq::Uart`，也不存在裸 `none`；
- 泛型用 `[]`（沿用 L 的 D1）；
- **表达式位置不写泛型实参**（无 turbofish，决策 D2）：
  `f(x)` 的 `T` 由期望类型推断；推断失败时用带标注的 `let`：
  `let g: Fn[Int] -> Int = f;` —— 这样 `arr[i]` 与 `f[T](x)` 不会歧义，EBNF 保持单义。
- trait **默认 `#[open]`**（下游可为**本地类型**实现该 trait）；`#[sealed]` 显式用于必须封闭的 trait；
  **orphan 规则**：foreign trait × foreign type 禁止（`E-LS-COHERENCE`），
  本地类型 + 外部 trait、本地 trait + 外部类型均允许；`#[orphan]` 逃生舱推迟到 S4（§6.5/§6.11）：

```ls
trait Read {
    fn read(self: ref[Self], dst: ref[Slice[U8]]) -> Result[USize, Error] eff(Read)
}

impl Read for File {
    fn read(self: ref[File], dst: ref[Slice[U8]]) -> Result[USize, Error] eff(Read) { ... }
}
```

### 5.3 region / alloc / borrow

```ls
fn scoped() eff(Alloc) {
    region R {
        let a: Alloc[Region] = R.allocator();
        let tmp: box[Array[U8, 256]] = a.alloc(Array.zeroed());
        process(tmp.slice());          // 传入 val[Slice[U8]]
    } // R 结束，tmp 随之释放
}

fn heap_build() -> Result[iso[Buffer], Error] eff(Alloc) {
    let a: Alloc[Heap] = heap_allocator();
    let data: box[Slice[U8]] = a.alloc_slice(64)?;   // T 由标注推断（无 turbofish）
    Ok(iso Buffer { data, len: 0 })
}
```

### 5.4 mode 类型

```ls
fn parse(src: val[Str]) -> Result[Ast, Error]           // 只读共享
fn mutate(dst: ref[Buf]) -> Unit eff(Write)             // 线程内独占借用
fn send(q: iso[Queue]) -> Unit eff(Spawn)               // 跨域独占转移
fn freeze(q: iso[Queue]) -> val[Queue]                  // 冻结（单向）
fn reuse(q: val[Queue]) -> iso[Queue] { recover { q } } // 线性恢复（要求别名全部消费）
```

### 5.5 unsafe / 底层 / 契约

```ls
#[repr(C, align(16))]
struct Regs { ctrl: U32, status: U32 }

extern "C" fn memcpy(dst: rawptr[U8], src: rawptr[U8], n: USize);

// MMIO 访问是安全 API（cap 控制），不需要 unsafe
fn mmio_snapshot(r: ref[Mmio[Regs]]) -> (U32, U32) eff(Hw) {
    (r.ctrl.read(), r.status.read())   // 字段投影保留 Mmio 地址空间
}

fn halt() eff(Asm) {
    unsafe(Cap[Unsafe]) { asm("wfi"); }
}

// 裸机代码生成指令（封闭属性集，D34）
#[no_mangle]
#[link_section = ".vectors"]
static VECTORS: val[Array[Handler, 4]] = Array.zeroed();  // 启动代码填充

#[naked]
#[no_mangle]
fn reset_handler() { asm("b _start"); }

#[repr(transparent)]
struct Handle(U32);                     // FFI newtype

union Word { u: U32, f: F32 }

fn read_cntpct() -> U64 eff(Asm) {
    let mut t: U64 = 0;
    unsafe(Cap[Unsafe]) {
        asm("mrs {}, cntpct_el0", out("x0") => t);   // 操作数/命名寄存器
    }
    t
}
```

### 5.6 效果

```ls
fn serve(sock: ref[Socket]) -> Result[Unit, Error] eff(Io, Alloc, Block) { ... }
fn pure_add(a: Int, b: Int) -> Int { a + b }            // 默认 Pure
fn push(r: ref[Ring], v: U8) -> Result[Unit, Error]
    requires r.count <= r.buf.len
    ensures  Ok(_) => r.count == old(r.count) + 1
eff(Write)
```

边界效果（`seal` 必须显式）：
`Unsafe`、`Ffi`、`Hw`、`Asm`、`Alloc`、`Dma`、`Irq`、`Block`、`Atomic`、`Spawn`、`Write`、
`Panic`、`Eval`、`Rewrite`。

### 5.7 并发 / 中断 / DMA

```ls
fn main(sys: Cap[Sys]) {
    let q: iso Queue = iso Queue.new();
    let a = spawn producer(move q);
    let q2: iso Queue = join(a);
    let b = spawn consumer(move q2);
    join(b);
}

fn bump(c: shared[Atomic[U64]]) eff(Atomic) {
    c.fetch_add(1, Order.SeqCst);      // shared 是锁语义；原子操作需内层 Atomic
}

#[irq(level = 1)]
fn on_uart(s: shared[UartState], r: Mmio[UartRegs]) -> Result[Unit, Error]
    eff(Irq, Hw)
{
    let st = r.status.read();
    s.rx.push(st)?;                    // ISR 内禁止 Alloc；`push` 无 Alloc 效果
    Ok(())
}
```

### 5.8 panic / 错误 / Drop

```ls
fn open(p: val[Path]) -> Result[File, Error] eff(Io) {
    let f = fs.open(p)?;               // `?` 传播；Error 是 Copy 的紧凑 enum
    Ok(f)
}

fn kernel_demo() eff(Write) {
    let f = open(p).or_else(Error.NotFound)?;
    defer f.release();                 // 作用域退出消费；错误路径也不泄漏
    // ...
}
```

- `release(self)` **消费**所有权，返回 `Result[Unit, Error]`；kernel 必须处理返回值或显式 `ignore`
  （决策 D19）；release 后使用原变量 ⇒ `E-LS-MOVE`；
- `defer expr;` 在作用域退出时执行，**消费**其捕获的线性资源；编译器做恰好一次检查（`E-LS-LEAK`）；
  `#[must_release]` 标记的类型必须有 `defer`/显式 `release`（D32）；
- `#[fault]` handler 在 `abort` 前记录现场（kernel 推荐；无 handler 时直接 abort）；
- `Error` 跨模块合并用**显式 `From` 注册**；默认每模块 ≤ 4 个变体，超出须声明**错误域**
  `#[error_domain("i2c", 0x20..0x2F)]`（`E-LS-ERROR-SIZE`）；错误域保持 `Copy` + 无分配；
- **语言定义整数为 wrapping**；`agent` 的 checked 是**调试检查**（trap），不是不同语义（决策 D20）。

- `panic` 在 v0 **一律 abort**（两个 profile 都是）；`#[unwind]` 留待后续 edition；
  因此「panic 时的 Drop 顺序」在 v0 不可观测（诚实降级，H-LS-19）；
- `extern "C"` 隐含 `nounwind`；跨 FFI 的展开是 UB（UB-15）；
- `Error` 必须是 `Copy` + 无分配（`enum` + 立即数），格式化只在 `agent` 边界发生。

### 5.9 黄金样例：环形缓冲（安全子集，S0′ 第一个试点）

**安全版**（无 `unsafe`，无 `rawptr`，边界检查 + 契约）：

```ls
#[repr(C)]
struct Ring {
    buf: box[Slice[U8]],
    head: USize,
    count: USize,
}

fn ring_new(a: Alloc[Heap], cap: USize) -> Result[iso[Ring], Error] eff(Alloc)
    // agent：句柄由 prelude 提供；kernel：额外需要 cap: Cap[Alloc]
{
    if cap == 0 { return Err(Error.InvalidCap); }
    let buf: box[Slice[U8]] = a.alloc_slice(cap)?;   // T 由标注推断（无 turbofish）
    Ok(iso Ring { buf, head: 0, count: 0 })
}

fn ring_push(r: ref[Ring], v: U8) -> Result[Unit, Error]
    requires r.count <= r.buf.len
    ensures  Ok(_) => r.count == old(r.count) + 1
    ensures  Err(_) => r.count == old(r.count)
eff(Write)
{
    if r.count == r.buf.len { return Err(Error.Full); }
    let i = (r.head + r.count) % r.buf.len;
    r.buf[i] = v;                       // 索引默认检查；i < len 由契约+取模保证
    r.count += 1;
    Ok(())
}

fn ring_pop(r: ref[Ring]) -> Result[U8, Error]
    requires r.count <= r.buf.len
    ensures  Ok(_) => r.count == old(r.count) - 1
eff(Write)
{
    if r.count == 0 { return Err(Error.Empty); }
    let v = r.buf[r.head];
    r.head = (r.head + 1) % r.buf.len;
    r.count -= 1;
    Ok(v)
}
```

**unsafe 版**（仅用于对照 unsafe 面积；S0″ 审计项）：

```ls
#[repr(C)]
struct RawRing { buf: rawptr[U8], cap: USize, head: USize, tail: USize }

unsafe fn raw_push(r: rawptr[RawRing], v: U8) -> Bool
    requires is_alloc(r.buf, r.cap) && r.tail >= r.head && r.tail - r.head <= r.cap
{
    if (*r).tail - (*r).head == (*r).cap { return false; }
    *((*r).buf + ((*r).tail % (*r).cap)) = v;   // provenance 由契约承担
    (*r).tail += 1;                              // kernel 默认 wrapping
    true
}
```

> 对照目的：安全版把「长度、环绕、边界」交给类型/契约/检查，unsafe 只省下边界检查；
> 若某试金石必须用 unsafe 版，则说明安全子集表达力不足（`LS-01` 枪毙条件）。

### 5.10 comptime 与封闭属性集（替代宏）

```ls
#[bitfield]
struct Ctrl { enable: 1, mode: 3, irq: 1, _: 3 }

comptime fn ring_capacity() -> USize { 4096 }

const CAP: USize = comptime ring_capacity();
```

- `comptime` 是**无副作用、fuel 有界、无 IO/无 `unsafe`/无 `Alloc`** 的解释器（`E-LS-COMPTIME`）；
- 可读类型信息与常量，不可读运行期值；只允许**结构递归**（终止性可判）；
- 内建封闭属性集分三类：
  1. **语义**：`#[repr]`、`#[align]`、`#[bitfield]`、`#[register]`、`#[nondet]`、`#[irq]`、`#[test]`、`#[prop]`、
     `#[trusted]`、`#[forbid]`、`#[boundary]`、`#[fault]`、`#[cap]`、`#[stack]`、`#[recursion]`；
  2. **代码生成指令**：`#[no_mangle]`、`#[link_section]`、`#[used]`、`#[naked]`、`#[link(name)]`；
  3. **每模块旋钮**：`#[bounds]`、`#[overflow]`、`#[fp]`、`#[must_release]`、`#[error_domain]`。
  **不开放用户自定义属性**（这是保持 EBNF 权威的代价，见 `LS-12`）；
- `ls svd`/`ls bindgen` 生成的代码标 `@generated`，不参与 style 检查，但**不自动 trusted**。

### 5.11 模式匹配与闭包（现代特性，最小集）

```ls
fn classify(x: Irq) -> U8 {
    match x {
        Irq.Timer    => 0,
        Irq.Uart(ch) => ch,
        Irq.None     => 0xFF,
    }
}

fn dispatch(r: ref[Read], buf: ref[Slice[U8]]) -> Result[USize, Error] eff(Read) {
    r.read(buf)                     // 动态分派：`ref[Trait]` 是 trait 对象视图
}

fn with_closure() {
    let n = 3;
    let f = |x: Int| x + n;         // 捕获 n：按 val（只读）捕获
    for i in 0..10 { f(i); }
}
```

规则：

1. `match` 必须**穷尽**（`E-LS-MATCH`）；变体模式唯一写法 `Type.Variant`；
2. 闭包捕获模式由**捕获点的 mode** 决定：只读 ⇒ `val`；需要写 ⇒ `ref`（独占捕获）；
   捕获同样受 R2/R4/R5 约束，逃逸的闭包必须 `box`/`iso`；
3. `ref[Trait]` 只允许对象安全 trait（方法不含泛型、`self` 为 `ref[Self]`/`val[Self]`）；
4. `for` 只接受内建 `Range`/`Slice`/`Iterator` 协议（无用户自定义 `for` 展开，保持 EBNF 权威）。

> 现代特性采用**最小集**：够写系统代码与 AI 生成，不追求语法糖。
> 未列入者（`async`、运算符重载、`yield`、可变参数）见 §13 未决问题或非目标。

---

## 6. 类型系统与语义（初稿）

### 6.1 类型

- 标量：`Int`(I64)、`I8..U64`、`F16/BF16/F32/F64`、`Bool`、`Char`、`Str`、`Unit`；
- 复合：`struct`/`enum`/`Array[T, N]`/`Slice[T]`/`Tuple`；
- 视图：`Slice[T] = (rawptr[T], USize)` 的安全封装（不可隐式从 `Array` 转换，需 `.slice()`）；
- mode 类型：`box[T]`/`iso[T]`/`val[T]`/`ref[T]`/`shared[T]`/`rawptr[T]`；
- 硬件类型：`Mmio[T]`、`DmaToken`、`Lock[T, Rank]`、`Cell[T]`；
- `box[T]`/`ref[T]` 字段与索引自动解引用（`b[i]` ≡ `(*b)[i]`，`r.count` 等价于 `(*r).count`）；
  `cell[T]`/`shared[T]` 是容器，不是 mode；
- 效果类型：`Fn(A) -> B eff(E)`；
- 区域：**不是类型**，只出现在推断类型中（§4.0/R-3）。

**`Array` vs `Slice` 的纪律（0.1.0 不一致处）**：`Array[T,N]` 是值、长度编译期已知；
`Slice[T]` 是借用视图、长度运行期；二者**不隐式转换**，`Array.slice()` 返回 `val[Slice]` /
`borrow mut` 返回 `ref[Slice]`。无 `Array[T]` 这种写法。

### 6.2 效果与 gate matrix（权威矩阵）

- 内部效果可推断并报告；边界效果必须显式（`seal`）；
- 效果组合：`eff(E1, E2) = E1 ∪ E2`；偏序为子集；`Pure` 为最小；
- 函数效果子类型：效果更小者可用于要求更大的位置（反之不行）。

| 操作 | mode 要求 | cap 要求 | effect | **权威检查** |
|---|---|---|---|---|
| 索引/解引用 `ref/box/val` | 对应 mode | — | — | mode + 边界检查 |
| `rawptr` 解引用/算术 | `raw` | `Cap[Unsafe]`（值） | `Unsafe` | cap + effect |
| `Mmio[T]` 读写 | 类型本身 | `Cap[Mmio[a..b]]` 且地址在范围内 | `Hw` | cap |
| `fence(Order)` | — | — | `Hw` | 类型/参数 |
| 分配 `alloc`/`box` | — | `Cap[Alloc]`（kernel） | `Alloc` | cap/effect |
| `spawn` / `join` | `iso`/`atom` | `Cap[Spawn]`（kernel） | `Spawn` | mode + cap |
| `extern "C"` 调用 | `raw`（指针参数） | `Cap[Ffi]` | `Ffi` | cap |
| `asm` | — | `Cap[Unsafe]` | `Asm` | cap |
| DMA 提交 | `iso` | `Cap[Dma]` | `Dma` | cap + mode |
| 原子操作 | `atom` | — | `Atomic` | mode |
| `freeze`/`recover` | `uniq`/`frozen` | — | — | mode |
| `unsafe` 块 | — | `Cap[Unsafe]` | `Unsafe`（+ 内含效果） | cap + effect |
| `comptime` 求值 | — | — | — | fuel |
| `panic` | — | — | `Panic` | effect |
| `static` 初始化 | — | — | — | comptime 常量 |
| `cell` 读写 | 单域 | — | `Local` | mode + 域 |
| `shared` 加锁 | `atom` | — | `Atomic` | mode + 锁 rank |
| `release` | `uniq` | — | — | 消费 + 返回值 |
| `defer expr` | 捕获资源 | — | — | 恰好一次消费 |
| `#[recursion]` | — | — | — | 静态栈上界 |
| 模块 `#[cap(...)]` | — | 词法上下文 | — | 入口检查 + 不可放宽 |
| `#[bounds(off)]` | — | — | — | 必须有 `requires` |
| `#[boundary]` 调用 | `val`/`iso`/标量 | 按 callee 需求 | 并集 | trampoline |
| `ls audit`（工具） | — | — | — | Trusted 闭包 |

> 这张表是「三重门」的权威：**cap 判权限，mode 判别名，effect 判可见性**。
> 实现者不得用 effect 替代 cap 检查（这是 0.1.0 的 `unsafe(Cap[Unsafe])` 缺陷）。
> **`Unsafe` 效果在安全包装函数处终止**：封装内的 `unsafe` 由 `#[cap]` + `Trusted`/审计承担；
> 否则 `Mmio[T]`、slab、容器库都无法作为安全 API 暴露。

### 6.3 预算与 profile

见 §5.1 表。补充：

- **跨 profile 调用**：只能经 `#[boundary]` trampoline（§5.1）；效果取**并**；
  预算与 cap 由 trampoline 编组，不在被调方隐式继承；v0 禁止跨 profile 静态链接；
- **fuel 耗尽** ⇒ abort + 审计条目（不返回 `Result`，避免「错误也要分配」）；
- **语言定义整数为 wrapping**；`agent` 的 checked 是调试检查（trap），`seal` 报告静默回绕
  （`W-LS-OVERFLOW`），显式 `checked_add` 可消除（决策 D20）。

### 6.4 诊断（修订码位）

| 码 | 含义 | 级别 | fix-it |
|---|---|---|---|
| `E-LS-REGION-ESCAPE` | 引用/box 逃出 region | Enforced | 改 `val`/复制/改 `Alloc[Heap]` |
| `E-LS-ALIAS` | 区域级别名冲突 | Enforced | 缩短借用/改 `val`/`cell` |
| `E-LS-ESCAPE` | 存活期超界 | Enforced | 提升 region/复制 |
| `E-LS-RACE` | mode 不允许跨域 | Enforced | 改 `iso`/`val`/`shared` |
| `E-LS-CAP` | 令牌缺失/越界 | Enforced | 补 `Cap[...]`/缩小范围 |
| `E-LS-UNSAFE` | 安全块用裸内存 | Enforced | 包 `unsafe` |
| `E-LS-INIT` | 未初始化 | Enforced | 初始化/`MaybeUninit` |
| `E-LS-MOVE` | 使用已 move 的值 | Enforced | 复制/重排/改 `iso` |
| `E-LS-UNIQ` | 唯一性被破坏 | Enforced | `recover`/复制 |
| `E-LS-DROP` | 重复 drop / profile 禁止隐式 drop | Enforced | 显式 `release` |
| `E-LS-EFFECT` | 边界效果缺失 | Enforced(seal) | 补 `eff(...)` |
| `E-LS-LAYOUT` | 布局/ABI 不符 | Enforced | 改 `#[repr]` |
| `E-LS-ABI` | 泛型/布局跨 FFI 不稳定 | Enforced | 改 `extern "C"` 签名 |
| `E-LS-BOUNDS` | 越界 | Enforced | 加长度检查/契约 |
| `E-LS-OVERFLOW` | 常量溢出 | Enforced | `wrapping_*`/`checked_*` |
| `E-LS-RECURSION` | kernel 递归 | Enforced | 改迭代/展开 |
| `E-LS-COMPTIME` | comptime fuel 耗尽/越权 | Enforced | 结构化递归/移出运行时 |
| `E-LS-PROV` | provenance 契约不满足 | Enforced(unsafe) | 补契约/`Witness` |
| `E-LS-IRQ` | 中断域/锁 rank 违反 | Enforced | 调整 rank/移出 ISR |
| `E-LS-MATCH` | `match` 不穷尽 / 模式类型不符 | Enforced | 补分支/改模式 |
| `E-LS-MONO-SIZE` | 单态化体积超预算 | Reported | 用 `dyn`/拆分泛型 |
| `E-LS-STATIC` | `static mut` 或非法 `static` 类型 | Enforced | 改 `val`/`shared`/`cell` |
| `E-LS-ERROR-SIZE` | 模块错误枚举超预算 | Enforced | 合并/`Other(u16)` |
| `E-LS-TRUST` | `Trusted` 声明不完整/哈希不符 | Enforced | 补审计元数据/重新审计 |
| `E-LS-PROFILE` | 非法 profile 依赖/跨域参数 | Enforced | 改依赖/加 `#[boundary]` |
| `E-LS-COHERENCE` | orphan impl / impl 重叠 / sealed 被实现 | Enforced | 用 newtype/本地 trait/`#[sealed]` |
| `E-LS-LEAK` | `defer`/`#[must_release]` 未执行或重复执行 | Enforced | 加 `defer`/显式 `release` |
| `E-LS-STACK` | 递归上界超 `stack_bound` | Enforced | 降低 bound/改显式栈 |
| `E-LS-CAPCTX` | 模块 cap 放宽/嵌套越权 | Enforced | 收紧 `#[cap]`/显式参数 |
| `E-LS-DIAL` | 安全旋钮降级缺契约/证据 | Enforced | 补 `requires`/CI 证据 |
| `W-LS-STACK` | 递归深度/栈上界不可判 | Reported | 改迭代/加 `#[stack(n)]` |
| `W-LS-UNSAFE-DENSITY` | unsafe 密度超阈值 | Reported | 审查/重构 |
| `W-LS-NONDET` | 隐式非确定性 | Reported | 标 `#[nondet]` |
| `W-LS-OVERFLOW` | kernel 静默回绕 | Reported | `checked_*` |
| `W-LS-FIXIT-UNSAFE` | 自动修复试图引入 unsafe（拒绝） | Reported | 人工处理 |
| `W-LS-WCET` | 最坏情况上界（栈/中断延迟）超限 | Reported | 缩短临界区/拆分函数 |

> 每个码必须配正/负例；码表与实现同步；与 §8.1 UB 清单双向满射（LS-P6）。

### 6.5 泛型 / comptime / 单态化（Rust 问题的正面回答）

| Rust 问题 | L-Sys 决策 |
|---|---|
| 单态化膨胀、编译慢（R-5） | 默认单态化 + `#[dyn]`/`dyn Trait` 显式 + 体积预算 `E-LS-MONO-SIZE`；增量检查为 G-S5 |
| trait coherence / 孤儿规则（R-3） | **`#[open]` 默认 + orphan 规则**：本地类型/本地 trait 可 impl；foreign × foreign 禁止；`#[sealed]` 显式封闭；`#[orphan]` 仅 S4 |
| `const` 泛型求值不可控 | const 实参必须是 `comptime` 可求值常量；fuel 有界；不可操作运行期值 |
| turbofish 与索引歧义 | 表达式位置不写泛型实参（D2）；推断失败用类型标注 `let` |
| 宏 | 封闭属性集 + `comptime`（D10） |

### 6.6 Drop / panic / 析构（新增）

| 项 | `agent` | `kernel` |
|---|---|---|
| 隐式 `Drop` | 允许 | **禁止**（`E-LS-DROP`），显式 `release` |
| 局部变量析构顺序 | 声明逆序（栈语义） | 不适用 |
| 结构体字段析构顺序 | **声明顺序**（确定性，LS-P7） | 不适用 |
| region 结束释放顺序 | **分配逆序** | 同左（显式 `release` 可选） |
| `panic` | `abort` | `abort` |
| panic 时析构 | 不可观测（abort） | 不可观测 |
| `Drop` 中分配 | 允许，但不得分配进已结束的 region | 不存在 `Drop` |
| `defer` | 允许 | **推荐**（替代隐式 Drop） |
| 泄漏检查 | `E-LS-LEAK` | `E-LS-LEAK` + `#[must_release]` |

> 选 `abort` 是有意的：unwind + Drop + 跨 FFI 的组合是 C++/Rust 复杂度的主要来源之一。
> 代价：「panic 时也释放资源」不可用；缓解：`kernel` 用 `defer`/显式释放，`agent` 用 `Result`。
> 登记为 `H-LS-19`。
>
> **`defer` 是 kernel 错误路径的关键（D32）**：它把「释放」从人/AI 的记忆移到编译器检查；
> `E-LS-LEAK` 保证每个线性资源恰好消费一次。没有它，`?` 会系统性地制造泄漏。

### 6.7 栈 / 递归（新增，D31）

- `kernel`：默认**禁止递归**（`E-LS-RECURSION`）；编译期做调用图 SCC 检查与栈上界，
  链接期检查（`#[stack(n)]` 可覆盖）；
- **有界递归逃生舱**：`#[recursion(bound = N)]` 允许 SCC 内递归，但必须满足
  `每帧上界 × N + 调用者余量 ≤ stack_bound`，否则 `E-LS-STACK`（档案 B 验收）；
- `agent`：允许递归，`depth` 预算在 `explore` 下生效；`seal` 下报告上界不可判（`W-LS-STACK`）；
- 无尾调用保证（不承诺 TCO，避免与调试/ABI 冲突）；
- 树遍历优先推荐**显式栈**（`Array[USize, N]`），有界递归是逃生舱而非常态。

### 6.8 模块 / 包 / 构建 / 供应链（新增）

```toml
# ls.toml
[package]
name = "uart-driver"
edition = "0.2"
profile = "kernel"

[capabilities]
required = ["Unsafe", "Mmio:0x40000000-0x40000fff", "Irq"]
```

规则：

1. 模块 = 文件树 + 显式 `use`；可见性显式（`pub`/`pub(crate)`/私有）；
2. **禁止 build script**；构建只由 manifest 描述（`LS-12`）；
3. registry + lockfile + vendoring；版本求解**确定性**（同一 lock 必得同一图）；
4. 依赖的 `capabilities` 取**并集**，`seal` 构建拒绝清单超集（供应链审计）；
5. 产物能力清单（§7.4）必须由 AST 推导并与 manifest 交叉校验；
6. `trusted.lock` 与 advisory 一起进锁文件；信任条目哈希变动即构建失败（§8.2）；
7. `[target]`：triple、硬/软浮点、原子可用性、链接器、`no_std` 变体；三目标矩阵见 S2；
8. **代码生成是一等构建步骤**（D35）：`ls svd`/`ls bindgen`/`ls gen` 声明输入/输出/确定性，
   进指纹；生成物标 `@generated`；**不开放任意 build script**；
9. `[policy]`：`trust`（T0-only/T1）、`unsafe`（预算）、`fp`（严格/快速）——供 CI 门禁读取。

### 6.9 确定性

- 浮点：IEEE-754，逐位；禁止 FMA 收缩（`contract=off`），固定舍入模式，denormal 固定；
  不依赖宿主 `libm`（只用登记的 FP 子集，H-LS-13）；
- 整数：**语言定义 wrapping**；`agent` 的 checked 为调试检查；`kernel` 显式 `checked_*`；
- 布局：`#[repr(C)]` 显式；默认布局在 edition 内冻结（`E-LS-LAYOUT`）；
- 哈希/Map 迭代序：确定性；
- 时间/随机/硬件：必须 `#[nondet]` + 效果显式（`H-LS-6` / `W-LS-NONDET`）；
- 求值顺序：**规范固定**（从左到右，先求值后调用；UB-12）；
- 构建：工具链版本/依赖/flag/布局/哈希进指纹。

### 6.10 成本模型（新增，决策 D21）

> 系统语言的选择靠**可预测成本**。本节是 `spec/cost.md` 的入口；`ls cost` 输出每函数静态上界。

| 构造 | 承诺 | 备注 |
|---|---|---|
| `ref` 借用 | 0 | 编译期消解 |
| region 结束 | 批量释放，O(活跃 box) | 无逐对象 free |
| 边界检查 | 1 cmp + branch | 常量/契约可证时消除 |
| `iso`/`box` move | 0 | 所有权转移 |
| `freeze`/`recover` | 0 | 纯静态 |
| cap 检查 | 0（静态） | 非 const `view` 为 1 次范围检查 |
| `Mmio` 访问 | 1 volatile load/store | 不可消除/合并 |
| 契约（seal） | 0 | 不可判定者转 `Witness` |
| 契约（explore） | 1 branch + trap | 只在 explore |
| `dyn` 分派 | 1 间接调用 | 抑制内联 |
| 单态化 | 代码体积 × 实例数 | `E-LS-MONO-SIZE` |
| 原子操作 | 1 指令或 1 锁 | 按 `Order` 映射表 |
| 隐式 Drop | 每字段 1 次调用 | `agent` only |

**内存序映射**（目标架构表，`spec/cost.md` 维护）：

| `Order` | x86-64 | ARMv8 | RISC-V |
|---|---|---|---|
| `Relaxed` | mov | ldar/stlr 或 mov | lw/sw |
| `Acquire` | mov（load 已 acquire） | ldar | fence r,rw + lw |
| `Release` | mov（store 已 release） | stlr | fence rw,w + sw |
| `SeqCst` | mfence / lock | dmb ish | fence rw,rw |

**最坏情况模型**：ISR 延迟（禁 `Alloc`/`Block` + 锁 rank 上界）、kernel 栈上界（静态）、
MMIO volatile 访问计数、中断屏蔽区间（由 rank 界）。超出上界 ⇒ `W-LS-WCET`。

**每模块旋钮（D33/ADR-18）**：`#[bounds(off, requires=...)]`（免边界检查但带契约）、
`#[overflow(wrapping)]`、`#[fp(fast)]`；默认安全，降级必须进 `[policy]` 且有 CI 证据（`E-LS-DIAL`）。
**每模式基线**：零拷贝解析（档案 A）的 `memcpy` 计数必须为 0；ISR 最坏路径、slab alloc/free
的周期数在 3 个目标上记录；没有基线的指标一律 `Protocol`（H-LS-21）。

### 6.11 分析模块化边界（新增，决策 D22）

> 决定 G-S5 是否可达。原则：**编辑循环只做函数局部 + 函数级缓存；全程序分析只进链接期报告**。

| 分析 | 粒度 | 缓存键 / 失效 |
|---|---|---|
| 类型/效果/穷尽性 | 函数 | 函数源码哈希 |
| mode/别名 R1–R8 | 函数 | 函数源码哈希 |
| 区域约束 | 函数（`ρ-scheme`） | `(源码哈希, 依赖方案哈希)` |
| 单态化实例集合 | crate | 本 crate 泛型使用集 + `dyn` 逃逸 |
| impl/coherence 集合 | crate 局部 | 本 crate impl 集 + orphan 检查 |
| 能力并集 / Trusted | crate 图 | 依赖清单 + 审计元数据 |
| unsafe 面积 / cap 表 / 布局哈希 | 链接期 | 不进增量关键路径 |

**硬规则**：v0 允许**orphan 规则内**的跨 crate impl（本地类型 + 外部 trait、本地 trait + 外部类型）；
**禁止 foreign × foreign**（`E-LS-COHERENCE`），否则需要全局注册表、失效传播到整个依赖图、G-S5 不可达。
新增 impl 只失效**下游**，不失效上游（ADR-17）。

### 6.12 镜像、加载与 cap 授予（新增）

> 语言承诺的**执行点在加载器**。完整协议见 [`02-架构评审与ADR.md`](02-架构评审与ADR.md) ADR-6 与 §4.3。

镜像结构：

```
+--------------------------------------------------+
| header: magic | version | abi | edition | profile |
|         entry | stack_bound | seg_count | cap_count |
+--------------------------------------------------+
| segments: text | rodata | data | bss | stack | vectors |
+--------------------------------------------------+
| cap table (signed): kind | range/params | rights      |
+--------------------------------------------------+
| signature + build fingerprint                      |
+--------------------------------------------------+
```

加载流程（TCB）：

1. 验签 + 校验 `abi`/`edition`/`profile`（不匹配 ⇒ 拒绝加载）；
2. 映射段与 `Mmio[a..b]` 页（由 cap 表驱动，不由程序自述）；
3. 按 cap 表授予令牌（`Unsafe`/`Alloc`/`Dma`/`Irq`/`Mmio` 范围）；
4. 跳转 `entry`；运行时预算从 header 读取。

链接脚本契约：段名/对齐/入口/向量表；`ls build` 生成镜像、`ls image --verify` 做离线校验。

**密钥与验签（ADR-16，决策 D28）**：

| 项 | 决定 |
|---|---|
| 算法 | v0 固定 **Ed25519**（确定性签名 ⇒ 可复现镜像）；header 保留 `alg` 字段 |
| 双层密钥 | 离线 release root（HSM）签发 build key；镜像带 `key_id` + 证书链；loader 固定 ≤ 2 个 root |
| 签名范围 | header + segments + **cap 表** + 构建指纹；cap 表在签名区内 |
| dev/prod | `profile dev` 自签 + `flag=dev`；**生产 loader 拒绝 dev 镜像** |
| 防回滚 | 安全存储的单调 `version_floor`；`version < floor` ⇒ 拒绝 |
| 吊销 | 新 loader + 内置 advisory；**不做在线吊销**（H-LS-26） |
| 平台策略 | 应用 cap 表之外，`Mmio` 范围还需通过**平台签名清单**（loader 持有） |
| 可复现 | `SOURCE_DATE_EPOCH`；签名区不含时间戳 |

---

## 7. AI 自动编程管线

> 差异化核心不是「模型能写」，而是「模型写错后能便宜地修，且修复不扩大攻击面」。

### 7.1 约束解码（定位修正）

- `spec/langSysQuanta.ebnf` → `.gbnf`；
- 单一规范形 + 无宏 + 无 turbofish ⇒ 文法接受集可被引擎约束；
- **诚实说明**：约束解码只保证**语法**合法，不保证 region/effect/契约合法。
  真正的收益是 **语义错误可局部归因 ⇒ fix-it 可机器应用**（§7.2），不是「解码强」。

### 7.2 结构化诊断 + fix-it

- 每条错误：`code + span + severity + message + fix-it`；
- fix-it 分级：`machine-applicable` / `maybe-incorrect` / `requires-human`；
- fix-it 以 **AST patch** 交付（不是文本 diff）：省 token、避免格式漂移、可跨版本重放；
- 诊断携带**稳定节点 ID**（跨编辑不变），供增量修复与回归比对；
- 诊断有**预算**（前 N 条 + 聚类 + 按区域归并），防止 500 条别名错误淹没上下文（ADR-11）；
- **硬策略（LS-P17）**：自动修复不得新增 `unsafe`/`Cap`/`Ffi`/`asm`；只能减少；
  违反即拒绝该修复并报 `W-LS-FIXIT-UNSAFE`；
- **产品化（D36）**：`ls explain E-LS-*`（人话 + 反例）、`ls check --format=sarif|junit`、
  `#[allow]`/`#[expect]` 带过期、baseline 抑制、`CODEOWNERS` 覆盖 `unsafe`；
  AI 生成物标 `@generated`（免 style，但不免 unsafe 评审）。

### 7.3 `explore` / `seal`

| 模式 | 行为 |
|---|---|
| `explore` | 宽松推断；运行期守卫（边界/契约/初始化）；允许省略边界效果；插审计 |
| `seal` | 静态拒绝；`unsafe`/`Ffi`/`Hw` 等缺失即错误；CI 门禁；unsafe 原语种类阈值 |

同一语法，两种严格度（继承 L 的 G1-D）。

### 7.4 能力清单（由 AST 推导，不可手写；ADR-10）

```json
{
  "profile": "kernel",
  "effects": ["Alloc", "Hw", "Irq"],
  "unsafe_primitives": ["ptr_offset", "assume_init"],
  "unsafe_blocks": 3,
  "capabilities": ["Unsafe", "Mmio:0x40000000-0x40000fff", "Irq"],
  "abi": "ls-c-1",
  "nondet": ["cycle_counter"],
  "contracts": { "total": 12, "witnessed": 2 },
  "trust": { "lock": "trusted.lock", "tier": "T1" },
  "keys": { "alg": "ed25519", "key_id": "build-2024-07" }
}
```

- 生成：从 AST + 效果推断 + cap 流分析导出；**不可手写**；
- 粒度：`capabilities` 按**模块**汇总（`#[cap(...)]`），package 级只是并集；
- 校验：与 `ls.toml` 的 `[capabilities]` 交叉校验；`seal` 拒绝超集与**非最小授权**；
- 完整性：清单带构建指纹与签名（供应链/部署）；schema 版本 `ls-protocol v1`；
- 运行时：内核加载器按清单映射 MMIO 页、授予令牌（§6.12）。

### 7.5 证明义务 / 见证

- `unsafe` 块、FFI 边界、并发关键区、契约中不可判定部分产生**义务**；
- 编译器检查可判定部分；不可判定部分生成 `Witness` 供人工/外部检查；
- 复用 L 的 `Proof`/`Witness`/adoption 方法论（上层可选）。

### 7.6 让「意图」可检查（本版新增，最高杠杆）

```ls
fn ring_push(r: ref[Ring], v: U8) -> Result[Unit, Error]
    requires r.count <= r.buf.len
    ensures  Ok(_) => r.count == old(r.count) + 1
    ensures  Err(_) => r.count == old(r.count)
eff(Write)
```

- **可判定片段**：线性算术（`+`/`-`/比较）、区间、`Result`/`Option` 判别式、typestate 标签、`old(...)`；
- `explore`：编译为运行期断言（守卫）；
- `seal`：可判定部分静态检查，其余生成 `Witness`（登记 H-LS-7）；
- **契约即 oracle**：自动生成属性测试（`#[prop]`），作为 AI 修复闭环的判定依据；
- 契约同时是 fix-it 的**目标**（错误信息能指出「哪条 ensures 被违反」）。

### 7.7 系统语义进类型（防 LLM 经典错误）

| LLM 常见错误 | 类型层对策 | 效果 |
|---|---|---|
| 锁序反转 → 死锁 | `Lock[T, Rank]` + `lock` rank 单调 | 编译期 `E-LS-IRQ` |
| 原子序用错 | `Atomic[T, Order]`；`Relaxed` 需显式审计 | 类型 + 审计 |
| 忘记释放/关闭 | typestate `File[Open] → File[Closed]`，线性 | `E-LS-MOVE`/`E-LS-DROP` |
| 缓冲区长度算错 | 契约 + `Slice[T]` + `requires` | 运行期守卫/静态 |
| 未初始化使用 | `MaybeUninit[T]` 安全 API + 初始化检查 | `E-LS-INIT` |
| ISR 里分配 | `Irq` 域禁止 `Alloc` | `E-LS-IRQ` |
| DMA 期间访问缓冲 | `DmaToken` 线性归属 | `E-LS-MOVE` |
| 用 unsafe 掩盖错误 | 自动修复禁止新增 unsafe | `W-LS-FIXIT-UNSAFE` |

### 7.8 修复闭环

```
生成 → 约束解码 → 解析/类型/region/mode/cap/契约检查
   → 结构化诊断 + fix-it（AST patch，可机器应用）
   → 自动修复（仅 machine-applicable，且不新增 unsafe）
   → 重检 → 测试/属性测试（explore 守卫 + 契约生成的 oracle）
   → seal 加固 → 能力清单 → 采纳
```

### 7.9 评测指标（修订）

| 指标 | 说明 | 目标（待冻结） |
|---|---|---|
| `first_check_rate` | 首次生成通过检查 | 冻结于 run-id |
| `resolved_rate` | 自动修复后通过 | 冻结于 run-id |
| `mean_rounds` | 平均修复轮数 | < Rust 对照 |
| `fixit_applicable_rate` | `machine-applicable` 占比 | ≥ 0.6（暂定） |
| `repair_diff_bytes` | 最小修复的 diff 规模 | 越小越好（token 成本） |
| `unsafe_delta` | 修复是否新增 unsafe | **≤ 0（硬门禁）** |
| `regression_rate` | 修复导致原通过测试退化 | 0 |
| `context_tokens` | 一次修复所需上下文 | 越小越好 |
| `UB_rate` | 运行期 UB/崩溃（对照 §8.1） | 冻结 |
| `unsafe_surface` | unsafe **原语种类**（不是行数） | ≤ 5 / 试金石 |
| `compile_time_per_round` | 增量检查/编译时间 | < 200ms / 10kLOC |
| `runtime_perf` | 相对 C 的几何均值 | ≥ 0.7×（S2） |
| `binary_size` | 产物大小 | 冻结 |
| `token_cost` | 生成 token 成本 | 冻结 |
| `time_to_first_blinky` | 新人按 quickstart 跑通时间 | ≤ 2h（LS-P19） |
| `unsafe_primitives_per_dossier` | 三份档案的 unsafe 原语种类 | A ≤1 / B 0 / C ≤5 |
| `zero_copy_memcpy` | 零拷贝路径的 `memcpy` 次数 | 0（档案 A） |

---

## 8. 信任与安全

### 8.0 TCB 清单（新增，决策 D23）

> `Enforced` 的含义是「由某个 TCB 组件执行」。没有 TCB 清单，`Enforced` 无依据。
> 完整图与失效模式见 [`02-架构评审与ADR.md`](02-架构评审与ADR.md) §4.1 / ADR-2。

| 组件 | 在 TCB | 失效后果 |
|---|:--:|---|
| 解析器 / `lsfmt` | 是 | 同一语义两种 AST |
| 检查器（region/mode/cap/effect/契约） | 是 | soundness 崩塌 |
| `comptime` 解释器 | 是 | 布局/常量结论错误 |
| 内建属性展开（`bitfield/register/repr`） | 是 | 「藏在编译器里的宏」出错 |
| 代码生成 / 优化器 | 是 | 安全程序被 miscompile |
| 链接器 / ABI 协商 | 是 | ABI 不匹配静默通过 |
| **加载器** | 是 | **cap 形同虚设** |
| 运行时（预算/原子/中断） | 部分 | 预算/中断语义偏差 |

**硬规则**：加载器必须在 `spec/image.md` 中规范化；`#[bitfield]`/`#[register]` 的语义必须写进
`spec/attributes.md`（否则 EBNF 权威保留、语义权威丢失）。

### 8.1 UB 清单（唯一权威，本版新增）

> 「安全子集无 UB」必须以本表为 oracle。每新增 UB 必须走 edition 变更。

| # | UB | 安全子集可达 | 检测/处理 | 诊断码 |
|---|---|:--:|---|---|
| UB-1 | 越界读/写 | 否 | 默认边界检查；`explore` 守卫 | `E-LS-BOUNDS` |
| UB-2 | 悬垂引用/指针 | 否 | 区域约束检查 | `E-LS-ESCAPE` |
| UB-3 | double free / 重复 drop | 否 | 线性所有权 | `E-LS-DROP` |
| UB-4 | 使用未初始化 | 否 | 初始化检查 | `E-LS-INIT` |
| UB-5 | 数据竞争（线程域） | 否 | mode R6/R8 | `E-LS-RACE` |
| UB-6 | 整数溢出 | 否 | **语言定义 wrapping**；`agent` checked 为调试 trap（非不同语义） | `E-LS-OVERFLOW`/`W-LS-OVERFLOW` |
| UB-7 | 除零 / 非法移位 | 否 | trap（定义行为：abort） | — |
| UB-8 | 解引用 null/野指针 | 仅 `unsafe` | 契约 + `Witness` | `E-LS-PROV` |
| UB-9 | 未对齐访问 | 仅 `unsafe` | 契约/`align_of` 检查 | `E-LS-PROV` |
| UB-10 | 违反 provenance（别名/越界派生） | 仅 `unsafe` | **Tree Borrows 简化模型** + 契约 | `E-LS-PROV` |
| UB-11 | MMIO 非 volatile 访问被优化/重排 | 否（用 `Mmio[T]`） | 类型固定 volatile + `fence` | `E-LS-PROV` |
| UB-12 | 未定义求值顺序 | 否 | 规范求值序（左到右） | — |
| UB-13 | 栈溢出 | `agent` 可达；`kernel` 否 | `agent` depth 预算；`kernel` 静态栈上界 | `W-LS-STACK`/`E-LS-RECURSION` |
| UB-14 | drop 期间使用已释放对象 | 否（`abort`，无 unwind） | §6.6 | `E-LS-DROP` |
| UB-15 | 跨 FFI 的 unwind | 否 | `extern "C"` 隐含 `nounwind` | `E-LS-ABI` |

> **关键**：UB-10 需要 provenance 模型，这是 `unsafe` 审计的地基。
> 在 S-1 冻结前，`rawptr` 与 `ref` 混用的「无 UB」是未定义状态。

### 8.2 安全子集（闭包定义，决策 D24）

> 0.1.0/0.2.0 的「不含 unsafe 即安全」是**排除式定义**，不可判定。本版改为闭包：

```
Safe(P) ⇔ P 无 unsafe/rawptr/Ffi/Asm
        ∧ ∀q ∈ Reach(P): Safe(q) ∨ Trusted(q)
```

- `Reach(P)`：传递可达的模块/库（含泛型单态化结果、`ref[Trait]` 动态分派目标）；
- `Trusted`：**不是全局注册表**，而是每个项目 `trusted.lock` 逐项钉住的
  `(crate, version, content_hash, audit_report_hash, scope, assumptions, auditor, date)`；
- **信任按 API 范围**，不是「整个 crate 安全」：`#[trusted(scope = "public-api", assumptions = [...])]`；
  内部 unsafe 由审计覆盖，语言只对「公开 API 满足安全子集契约」背书；
- **失败关闭**：缺失条目、哈希不符、报告过期 ⇒ `E-LS-TRUST`，`Safe` 不成立；
- **不做传递信任**：`trusted.lock` 必须显式列出完整闭包，禁止「A 信 B、B 信 C」的信任洗白；
- **分层**：T0 工具链 prelude/std（发布签名 + 双人审计）、T1 项目钉住（可第三方审计）、T2 未信任；
- **吊销 = 更新 lock**：无运行期吊销；advisory `(crate, version, hash) → unsound` 由 `ls audit` 读取，
  离线模式**失败关闭**；
- `ls audit` 输出**链接级** unsafe 面积、未判定项、lock 哈希校验结果；
- `#[forbid(unsafe)]`（模块级）使本模块及其子模块不得出现 `unsafe`；
- **允许**：`Mmio[T]`/`DmaToken`（cap 控制的安全 API；硬件后果由 `Hw`/`Dma` 效果承担）；
- 保证：无 UB-1…UB-15（除 UB-13 由 profile 限定）；
- **片段声明**：定理只对「单线程 + 无 unsafe + 无 FFI + 无递归」片段承诺
  （中断域另见 H-LS-16）；新增片段必须登记。

> 这条规则把「安全」从**语法属性**变成**可复现的信任闭包**；治理流程（谁审计、如何吊销）
> 登记为 `H-LS-25`，schema 在 S-1，流程在 S4。详见 02 ADR-15。

### 8.3 `unsafe` 审计

- 每个 `unsafe` 块必须有：cap、effect、证明义务、审计条目；
- 模块级 `#[forbid(unsafe)]`；`#[trusted]` 仅 crate 根；
- CI 统计 **unsafe 原语种类**（优先）与密度（次要）；超阈值即 `W-LS-UNSAFE-DENSITY`（`H-LS-14`）；
- `ls audit` 输出链接级面积、按模块支出、`trusted.lock` 哈希校验与 advisory 结果；
- `#[trusted]` 条目的 `audit_report_hash` 必须进构建指纹；报告变动即失败关闭；
- 把常见 unsafe 操作 API 化并带可检查条件（目标：试金石只落在少量已审计原语上）：

```ls
fn offset_in[T](p: rawptr[T], a: &AllocInfo, n: USize) -> Option[rawptr[T]]
fn assume_init[T](m: MaybeUninit[T]) -> T requires is_init(m)
```

### 8.4 可复现构建与供应链

- 工具链版本、依赖、flag、布局、哈希全部进指纹；
- `ls build --reproducible` 产出可复现产物；
- 依赖能力并集审计（§6.8）；无 build script；
- 浮点/时间/随机在测试中可注入（`#[nondet]` 之外确定性）。

### 8.5 与 RSI 的关系（可选）

L-Sys 可复用 L 的 `Artifact`/`Kernel`/`Proof`/adoption，把「系统代码的生成与采纳」纳入
propose→verify→accept→adopt→rollback。但这是**上层可选**，不是 L-Sys 的核心承诺。

### 8.6 `explore` / `seal` 等价与认证构建（新增，决策 D25）

- **语义等价前提**：守卫只 trap，不改变成功路径；`seal` 只是去掉守卫并补静态证明；
- `--guards=keep`：保留守卫的**认证构建**，用于需要现场证据的场景；
- CI 对 `seal` 与 `guards=keep` 跑同一测试集，输出逐位一致（除 trap 路径）；
- 不满足等价 ⇒ `H-LS-23` 降级，且认证场景不得使用 `seal` 产物。

> 「你验证的二进制不是你交付的二进制」是认证场景的典型陷阱；本条是对它的显式回应。

---

## 9. 实施路线（S-1 → S5）

> 每阶段都必须有**可执行 DoD** 与**枪毙条件**；未过不得进入下一阶段（沿用 L 的 V2 纪律）。
> **本版重排**：先用纸面语义冻结 + 可执行检查器证伪语义，再谈代码生成。

### S-1 · 语义与架构冻结（6–10 周）

> 0.1.0 缺失的最关键一步。没有它，S0′/S0″ 的判决不可复现。
> **本版扩充**：S-1 同时交付架构基线（02）——语义与边界一起冻结。

**交付**：
- [`02-架构评审与ADR.md`](02-架构评审与ADR.md) + 5 张架构图 + ADR-1…30；
- [`03-开发与工程实践评审.md`](03-开发与工程实践评审.md) + **三份硬模式档案**（§4）；
- `spec/ub.md`（§8.1 的 15 条 + 检测方式）；
- `spec/modes.md`（mode 格、区域格、R1–R8、约束推断算法、`recover` 线性检查）；
- `spec/effects.md`（效果集 + **gate matrix**（§6.2））；
- `spec/comptime.md`（求值模型、fuel、可终止片段、封闭属性集）；
- `spec/tcb.md`（§8.0 + 失效模式 + 测试计划）；
- `spec/image.md`（§6.12 的 header/段/cap 表/签名/密钥链/防回滚/loader 伪代码）；
- `spec/cost.md`（§6.10 成本表 + 最坏情况 + `ls cost` 规格）；
- `spec/trust.md`（§8.2 闭包 + `trusted.lock` + advisory + `ls audit`）；
- `spec/coherence.md`（`#[open]`/`#[sealed]` + orphan 规则 + impl semver + vtable ABI）；
- `spec/baremetal.md`（属性/asm/link section/naked/入口/向量，D34）；
- `spec/resource.md`（`defer`/`#[must_release]`/泄漏检查，D32）；
- `spec/cap-context.md`（模块 `#[cap]` + 每模块旋钮，ADR-18）；
- `spec/toolchain.md`（`[target]` 矩阵 / SVD / bindgen / 可复现，D35）；
- `spec/langSysQuanta.ebnf` 最小可解析子集（覆盖 §5 全部代码块）；
- 小步操作语义（≤ 20 条规则，含 region/mode/`recover`）。

**DoD**：
- 三条纸面定理有证明草稿：逃逸 sound、别名 sound、`recover` 保持唯一性；
- 每条 UB 有检测方式与诊断码；
- gate matrix 每行有唯一权威检查；
- TCB 每组件有失效模式；image 有第三方可实现的 loader 伪代码；
- 成本表每行有可测判据；Safe 闭包在 3 个依赖图上判定正确；
- **03 三份档案全部有结论**（通过/条件/失败），负例全拒；
- `baremetal.md`/`resource.md`/`cap-context.md`/`toolchain.md` 各有过一负例。

**枪毙**：
- `recover` 唯一性无法证明 ⇒ 删除 `val → iso`（`LS-13`）；
- UB 清单无法覆盖 5 个试金石 ⇒ 冻结扩语义；
- 镜像无法验签/无法复现 ⇒ S2 不得启动（`LS-19`）；
- 加载器无法在 TCB 内隔离 ⇒ cap 承诺降为 Protocol（`LS-20`）；
- 档案 A 若必须显式视图生命周期 ⇒ LS-P10 修订（`LS-25`）；
- 档案 C 若 unsafe 原语 > 8 或 fuzz 出 UAF ⇒ 回 S0′（`LS-25`）。

### S0′ · 可执行检查器 + 2 个试点（3–4 个月）

**目标**：先证伪语义，再谈表达力。

**交付**：
- 词法/解析器（基于 S-1 的 EBNF 最小子集）+ `lsfmt`；
- region/mode/cap/effect 检查器（**不生成代码**）；
- **`comptime` 最小子集**（const 泛型/常量求值）——S0′ 的 `Array[U8,N]` 依赖它；
- 结构化诊断 + fix-it（AST patch）+ 诊断预算；
- 参考解释器（`spec/ir.md` 最小 IR）+ 差分测试脚手架；
- **QEMU quickstart**（blinky→UART→环形缓冲，≤2 小时）+ LSP 骨架 + `ls check --format=sarif`；
- 2 个试点：环形缓冲（安全版，§5.9）、slab 分配器；
- **03 档案 A/B 被检查器接受**（C 先做类型检查）。

**DoD**：
- 两个试点**被检查器接受**，且 20 条负例（§4.9 + §6.4）全部被拒；
- `lsfmt` 幂等；`fixit_applicable_rate ≥ 0.5`；
- 约束失败率可测量（目标 ≤ 30%）；
- 新人按 quickstart ≤ 2 小时跑通（LS-P19）。

**枪毙**：
- 检查器不 sound（负例漏过）⇒ 冻结扩语义，修检查器；
- 区域约束失败率 > 30% ⇒ `LS-14`。

### S0″ · 扩展试点（2–3 个月）

**交付**：无锁队列、中断处理、MMIO 驱动（**解释器模拟**：假 MMIO 地址空间 + 可注入 IRQ/DMA；
真机验证推迟到 S2）。

**DoD**：
- ≥ 3/5 试点在**安全子集**内完整表达；
- 其余 2 个的 `unsafe` 原语种类 ≤ 5，且每个原语有契约与审计条目；
- 中断域风险有结论（要么证明，要么 `LS-16` 降级）。

**枪毙**：
- 安全子集 < 3 个 ⇒ **内存模型重设计**（`LS-01`），不得进入 S1；
- MMIO 无法在不使用 `unsafe` 时正确表达 ⇒ `Hw` 域划出安全子集（`LS-15`）。

### S1 · 前端 + 完整检查器（6–12 个月）

**交付**：
- `spec/langSysQuanta.ebnf` 完整版、解析器、region/mode/cap/effect/契约检查器；
- 诊断 schema + fix-it 覆盖 §6.4 全部码位；`lsfmt`；GBNF 导出；
- 解释器（复用 L 的 `lq-runtime` 思路）+ 契约守卫；
- 包管理最小版（§6.8）；
- **SVD/bindgen 最小版** + C 头文件导入；
- **模块级 `#[cap]` 与每模块旋钮**实现；
- LSP（跳转/补全/诊断）+ SARIF + `ls explain`。

**DoD**：
- conformance 全绿；诊断正/负例覆盖 §6.4；
- `lsfmt` 幂等；GBNF 可被约束解码引擎加载；
- 5 个试金石在解释器上跑通；
- **增量检查 < 200ms / 10kLOC**（G-S5 首次测量）。

**枪毙**：
- 检查器不 sound（负例漏过）⇒ 冻结扩语义，修检查器（L-01/L-02 精神）。

### S2 · 原生后端 + 裸机（6–18 个月）

**交付**：
- LLVM/Cranelift 后端；`no_std`；C ABI；链接脚本；交叉编译；
- QEMU 上的小内核/RTOS 任务（调度 + 中断 + 分配器）；
- 静态栈分析（递归禁止 + `#[recursion(bound)]` 上界）；
- 三目标矩阵（x86_64 QEMU / Cortex-M / RISC-V）+ 可复现 CI（diffoscope）；
- HIL 测试脚本（一块真实板）。

**DoD**：
- 在裸机/QEMU 跑通；系统基准性能 ≥ 0.7× C；
- 冷编译 ≤ Rust 同规模项目的 0.5×；
- 二进制大小、启动时间可接受。

**枪毙**：
- 性能 < 0.5× C 且无明确优化路径 ⇒ 放弃「对标 C」的表述，退回「可信系统编排层」；
- 增量编译 > Rust 同等项目 ⇒ `LS-17`，暂停特性扩张。

### S3 · 并发 + `unsafe` 审计

**交付**：
- 原子/内存序/`shared`/`cell`/`spawn`/`join`；锁 rank；中断域规则；
- 线程域数据竞争自由定理（安全子集）；
- `unsafe` cap + 证明义务 + provenance 检查器 + fuzz；
- `ls audit`（链接级 Safe 闭包 + `Trusted` 校验）。

**DoD**：
- 安全子集无线程域数据竞争；`unsafe_surface` ≤ Rust 同等任务；
- UB 检查器覆盖 §8.1 核心语义；
- 中断域要么有定理，要么登记 `H-LS-16`；
- 域模型的**可执行操作语义**在 S3 冻结（不等到 S5 形式化）。

**枪毙**：
- 并发模型无法证明数据竞争自由 ⇒ 降级为 Protocol，并在 §12 登记。

### S4 · 生态 + AI 闭环

**交付**：
- C 互操作（头文件导入/`extern "C"`）、libc shim、包管理、LSP/调试器；
- AI 修复闭环 + 四臂评测 + 契约生成属性测试。

**DoD**：
- systems 基准上 `first_check_rate` / `resolved_rate` / `UB_rate` / `repair_diff_bytes`
  达到冻结阈值；
- `unsafe_delta ≤ 0`、`regression_rate = 0`；
- 维护任务（2kLOC 加特性/修 bug）占基准 ≥ 50%。

**枪毙**：
- equal-data-finetune 后仍显著低于 C/Rust ⇒ **AI 自动编程前提不成立**，
  L-Sys 退回「可信编排层」定位。

### S5 · 形式化 + 可验证子集

**交付**：
- 内存模型/mode 规则/线程与中断定理形式化；provenance 模型；
- 片段 PCC；可复现/可回滚工具链。

**DoD**：
- 核心定理机械化（或明确降级）；片段验证通过。

**不承诺**：完整内核验证、自举。

---

## 10. 评测协议（初稿）

### 10.1 系统基准集

- 分配器、环形缓冲、无锁队列、调度器、简单驱动、HTTP 服务、压缩、加密、解析器；
- 每个任务给出 C / Rust / Zig（可选）对照实现；
- 任务必须**中立、只读、确定性**；
- **维护任务**（在 2kLOC 已有代码上加特性/修 bug）占 ≥ 50%（本版新增）。

### 10.2 指标

见 §7.9。额外：`human_expert_minutes`（人类专家时间）、`model_scaling`
（小模型是否也能过检查）、`compile_time_cold`/`compile_time_incremental`。

### 10.3 四臂与 EL-1

沿用 L 的评测纪律：

- `zero-shot` / `few-shot` / `constrained-decode` / `equal-data-finetune`；
- 必须控制**预训练熟悉度（EL-1）**；
- `constrained-decode` 的高通过率是构造结果，**不得**作为 G-S3 达成依据；
- 显著性检验、非劣界、停止规则先冻结再跑；
- **消融**：同一任务用 C 写 + 「外层包安全 API」的对照，证明收益来自语言而非任务难度。

### 10.4 判决纪律

- 在 `results/<run-id>.json` 产出前，**禁止**写「L-Sys 优于 C/Rust」；
- 结论必须绑定 `run-id + protocol + 指纹`；
- 失败要登记，不得只报喜。

---

## 11. 风险与枪毙条件

| # | 风险 | 概率 | 影响 | 枪毙条件（可执行） |
|---|---|:--:|:--:|---|
| LS-01 | 内存模型表达力不足 | 高 | 高 | S0″ 中安全子集 < 3/5 试金石 ⇒ 重设计 |
| LS-02 | region 推断不可判定/太弱 | 中 | 高 | 常见模式必须写 `unsafe` ⇒ 改模型 |
| LS-03 | mode 规则对 LLM 仍太难 | 中 | 高 | 修复轮数不优于 Rust ⇒ 重新设计语法/诊断 |
| LS-04 | 安全子集仍有 UB | 中 | 高 | 负例/fuzz 发现 §8.1 内 UB ⇒ 冻结发布 |
| LS-05 | 并发数据竞争自由不成立 | 中 | 高 | 反例可构造 ⇒ 降级为 Protocol |
| LS-06 | 原生性能不达标 | 中 | 高 | < 0.5× C ⇒ 放弃「对标 C」 |
| LS-07 | `unsafe` 面积过高 | 中 | 中 | `unsafe_surface` > Rust 同等任务 ⇒ 无安全优势 |
| LS-08 | 生态冷启动失败 | 高 | 中 | C 互操作/包管理不可用 ⇒ 降级为研究原型 |
| LS-09 | 设计膨胀、实现停滞 | 高 | 高 | S0′/S1 DoD 未过 ⇒ 冻结文档扩张 |
| LS-10 | 保证级别被误读 | 中 | 中 | 把 Protocol/Out-of-scope 写成已保证 ⇒ 文档门禁失败 |
| LS-11 | 自举诱惑 | 中 | 中 | 早期把自举进排期 ⇒ 按 N1 改路线 |
| LS-12 | 宏/DSL 需求导致文法失控 | 中 | 高 | 引入不可 EBNF 化的语法 ⇒ 拒绝 |
| **LS-13** | `recover`/唯一性无法证明 | 中 | 高 | 纸面证明失败 ⇒ 删除 `val → iso` |
| **LS-14** | 区域推断失败率过高 | 中 | 高 | 试金石上 > 30% ⇒ 引入注解逃生舱或重设计 |
| **LS-15** | MMIO/`Hw` 无法安全表达 | 中 | 中 | 必须 `unsafe` 才能写驱动 ⇒ `Hw` 划出安全子集并登记 |
| **LS-16** | 中断域数据竞争反例 | 中 | 高 | 反例可构造 ⇒ H-LS-3 降级为「仅线程域」 |
| **LS-17** | 编译时间不达标 | 中 | 高 | 增量 > Rust 同等项目 ⇒ 暂停特性扩张，优先 G-S5 |
| **LS-18** | 契约层膨胀成完整验证 | 中 | 中 | 契约不可判定比例 > 50% ⇒ 收缩到线性算术片段 |
| **LS-19** | 镜像无法验签/无法复现 | 中 | 高 | S-1 结束时无 loader 伪代码 ⇒ S2 不得启动 |
| **LS-20** | 加载器无法隔离 cap | 中 | 高 | 越界负例可通过 ⇒ cap 承诺降为 Protocol |
| **LS-21** | 成本模型与 codegen 脱节 | 中 | 中 | `ls cost` 与汇编不一致 > 10% ⇒ 成本表降为 Protocol |
| **LS-22** | `Trusted` 集合治理失效 | 中 | 高 | 审计元数据不可复现 ⇒ Safe 闭包不可判定 |
| **LS-23** | 密钥托管/轮换失败 | 中 | 高 | dev 镜像可上生产/回滚可绕过 ⇒ 拒绝发布 |
| **LS-24** | orphan 场景表达力不足 | 中 | 中 | newtype 适配器摩擦过大 ⇒ S4 引入 `#[orphan]` 注册表 |
| **LS-25** | 零拷贝视图/游标表达力不足 | 中 | 高 | 档案 A 必须复制或引入显式生命周期 ⇒ 重估 LS-P10 |
| **LS-26** | 裸机属性/asm 不足 | 中 | 高 | A 切片无法在真实板跑通 ⇒ S2 不得启动 |
| **LS-27** | cap 工效导致 unsafe 上移 | 中 | 高 | 模块 cap 上下文不可用 ⇒ `unsafe` 面积 > 预算 |
| **LS-28** | S-1 交付过载/规格瘫痪 | 高 | 中 | 砍单后仍超时 ⇒ 只保留 4 spec + 三份档案 |

---

## 12. 诚实降级表（`H-LS-*`）

> 唯一登记处。正文只能引用本表级别；禁止写成「已由公理保证」。
> **本版拆为三列**：当前级别 / 目标级别 / 升级证据。`Enforced` 只用于已有可执行测试或机器检查证明的项。

| # | 做不到的判定 | 当前 | 目标 | 升级证据 | 缓解 |
|---|---|---|---|---|---|
| H-LS-1 | 安全子集覆盖所有系统模式 | Protocol | Protocol | 每新增场景提案 + 试金石 | region + unsafe 边界 |
| H-LS-2 | region 推断对所有程序完备 | Protocol | Protocol | 失败率测量（S0′） | 诊断 + fix-it |
| H-LS-3 | 线程域数据竞争自由 | Protocol | Enforced | S3 定理 + 反例搜索 | mode 规则 |
| H-LS-4 | `unsafe` 块内深层 soundness | Out-of-scope | Out-of-scope | — | 契约 + provenance + 审计 |
| H-LS-5 | FFI 外部代码行为 | Out-of-scope | Out-of-scope | — | 沙箱 + 审计 |
| H-LS-6 | 硬件非确定性（时间/随机/DMA） | Reported | Reported | — | `#[nondet]` + 效果 |
| H-LS-7 | 完整功能正确性 | Out-of-scope | **Protocol** | 契约可判定片段 + 属性测试 | 测试 + `Witness` |
| H-LS-8 | 编译器自举 | Out-of-scope | Protocol | `05` + ADR-28 + `stage2==stage3` | S5 前不做；三阶段方案 |
| H-LS-9 | 与 C/Rust 的性能对等 | Protocol | Protocol | S2 基准 + 指纹 | 优化 + 后端 |
| H-LS-10 | 生态规模 | Out-of-scope | Out-of-scope | — | C ABI |
| H-LS-11 | LLM 生成率优于 C/Rust | Protocol | Protocol | 四臂评测（§10） | — |
| H-LS-12 | 稳定 ABI 覆盖所有类型 | 片段 Enforced | 片段 Enforced | ABI 冻结套件 | 仅 `extern "C"` 子集 |
| H-LS-13 | 跨平台逐位浮点 | Protocol | 片段 Enforced | FP 子集测试 | 禁用 FMA + 固定舍入 |
| H-LS-14 | `unsafe` 密度阈值合理性 | Protocol | Protocol | 人工裁定 + 对照 | 审计 |
| **H-LS-15** | `val → iso` 的还原（`recover`/运行期见证） | Protocol | Protocol | S-1 纸面证明 + S3 检查器 | 单向冻结；运行期 `rc==1` |
| **H-LS-16** | 中断域数据竞争自由 | Protocol | Protocol | S3 域模型 + 反例搜索 | `Irq` 域规则 + 锁 rank |
| **H-LS-17** | `comptime` 终止性/能力边界 | Protocol | Enforced | fuel 模型 + 越权负例 | 结构递归 + 无副作用 |
| **H-LS-18** | 泛型单态化的编译时间/体积上界 | Protocol | Protocol | S2 预算测量 | `#[dyn]` + `E-LS-MONO-SIZE` |
| **H-LS-19** | panic 时的资源释放 | Out-of-scope | Out-of-scope | — | `abort` + 显式释放 |
| **H-LS-20** | cap 撤销与热卸载 | Out-of-scope | Out-of-scope | — | v0 不做；epoch 需 RFC |
| **H-LS-21** | 成本模型上界与实际 codegen 一致 | Protocol | 片段 Enforced | `ls cost` × 汇编对照 | 5 个试金石先验收 |
| **H-LS-22** | 跨 edition 的 ABI 兼容 | Protocol | 片段 Enforced | 0.2 库 × 0.3 程序链接套件 | 布局哈希 + 加载期校验 |
| **H-LS-23** | `seal` 与 `guards=keep` 的语义等价 | Protocol | Protocol | 同测试集逐位一致 | ADR-9，未证前认证不得用 `seal` |
| **H-LS-24** | `Trusted` 集合的正确性 | Protocol | Protocol | 审计元数据 + 哈希固定 | 治理流程（S4 前定） |
| **H-LS-25** | `Trusted` 治理与吊销流程 | Protocol | Protocol | `trusted.lock` + advisory 套件 | 失败关闭；锁更新即吊销 |
| **H-LS-26** | 加载器密钥托管（HSM/轮换/离线） | Out-of-scope | Out-of-scope | — | 运维边界；语言只保证验签 |
| **H-LS-27** | `#[orphan]` 跨 crate impl（foreign×foreign） | Out-of-scope | Protocol | S4 注册表 + 链接期检查 | v0 用 newtype；`#[sealed]` 显式 |
| **H-LS-28** | 可返回视图/游标（零拷贝 API） | Protocol | Enforced | 档案 A + `parse` 无 memcpy | `val` 字段；`ref` 不可返回 |
| **H-LS-29** | 有界递归的栈上界 soundness | Protocol | Enforced | 档案 B + 链接期检查 | `#[recursion(bound=N)]` |
| **H-LS-30** | 模块级 cap 上下文的隔离性 | Protocol | Enforced | 档案 C + 越权负例 | 词法作用域；不可嵌套放宽 |

---

## 13. 未决问题（Open Questions）

> 已解决项移入 §15.3 决策登记；以下仅保留真正未决者。

1. **区域约束失败率**：5 个试金石上实际多高？阈值 30% 是否合理（`LS-14`）？
2. **mode 粒度**：`box/iso/val/ref/shared/rawptr` 六档是否够？是否需要 `tag`/`weak`？
3. **内部可变性**：`cell[T]` 已定为单域容器（D14）；仍待验：它与 `val` 的别名规则在库 API 上是否够用。
4. **自引用/侵入式容器**：`pin` + region 能否覆盖？需要多少 `unsafe` 原语？
5. **封闭属性集**：`#[bitfield]`/`#[register]` 能否覆盖所有寄存器/位域 DSL 需求？
6. **`async` 是否进入核心**：还是结构化并发 + 效果？取消语义与 Drop 的交互？
7. **C++ 互操作**：只做 C ABI，还是提供受控 C++ 子集（`extern "C++"`）？
8. **形式化范围**：哪些定理必须机械化？provenance 用 Tree Borrows 还是自定义？
9. **AI 评测阈值**：`first_check_rate` / `fixit_applicable_rate` 如何冻结？
10. **单态化默认**：全单态化 + `#[dyn]` 是否足以守住 G-S5？
11. **锁 rank 的表达力**：`const Rank: USize` 是否够，还是需要依赖类型？
12. **与 L 的复用边界**：`Cap` 语义分叉后，哪些组件可共享？
13. **`trusted.lock` 合并冲突策略**：多人/多分支如何合并？（建议按 crate 排序 + 语义合并）
14. **平台 MMIO 签名清单的供给与更新**：S2 前定。
15. **`#[orphan]` 是否值得在 S4 引入**：先看 newtype 适配器的实际摩擦。
16. ~~**视图规则是否足够**~~：已由 Q1/`results/A-views.md` 关闭——`val` 字段可返回，`ref` 字段不可返回；A-2/A-5 待 S0′/S1。
17. **模块 cap 的隔离强度**：词法 vs 动态；嵌套模块如何最小授权？
18. **有界递归默认值**：`bound` 与 `stack_bound` 如何按目标架构定？
19. **SVD/bindgen 生成物是否 trusted**：生成代码的审计责任归属？
20. **C ABI 类型映射**：`char` 有无符号、`long` 宽度、位域布局的默认策略？

---

## 14. 对比表（设计维度）

| 维度 | C | C++ | Rust | Zig | Pony | Hylo | **L-Sys（提案）** |
|---|---|---|---|---|---|---|---|
| 内存安全 | 否 | 否 | 是（借用检查） | 部分（debug 检查） | 是（能力） | 是（值语义） | **是（region + mode）** |
| 生命周期注解 | 无 | 无 | **必须** | 无 | 无 | 无 | **无（ρ 只在推断类型）** |
| 数据竞争自由 | 否 | 否 | 是（Send/Sync） | 否 | 是（能力） | 部分 | **是（mode + 并发域）** |
| 裸内存 | 是 | 是 | `unsafe` | 是 | 否 | 否 | **`unsafe` + cap 令牌** |
| MMIO/volatile | 手动 | 手动 | `unsafe` | 手动 | 否 | 否 | **`Mmio[T]` + `Hw`（安全 API）** |
| DMA 归属 | 手动 | 手动 | `unsafe` | 手动 | 否 | 否 | **`DmaToken`（线性）** |
| 无 GC | 是 | 是 | 是 | 是 | 否（GC） | 是 | **是** |
| 宏 | 是 | 是 | 是 | comptime | 否 | 否 | **否（comptime + 封闭属性）** |
| EBNF 权威 | 否 | 否 | 否（宏） | 部分 | 是 | 是 | **是（无 turbofish）** |
| 约束解码 | 弱 | 弱 | 弱 | 中 | 中 | 中 | **目标：强（语法层）** |
| 意图可检查（契约） | 否 | 否 | 部分（无契约） | 否 | 否 | 部分 | **目标：可判定片段** |
| AI fix-it | 弱 | 弱 | 中 | 中 | 弱 | 弱 | **目标：强（AST patch）** |
| 确定性/可复现 | 弱 | 弱 | 中 | 中 | 弱 | 中 | **目标：强** |
| 编译时间 | 极快 | 慢 | 慢 | 快 | 中 | 中 | **目标：一等目标（G-S5）** |
| 原生性能 | 高 | 高 | 高 | 高 | 中 | 中 | **目标：≥0.7× C** |
| 生态 | 巨大 | 巨大 | 大 | 中 | 小 | 小 | **靠 C ABI** |

---

## 15. 附录

### 15.1 术语（修订：四概念分离）

| 术语 | 含义 | 不与之混用 |
|---|---|---|
| region（区域） | 词法分配区域；静态名字，**不是类型/值**；推断区域变量 ρ | mode / cap |
| mode（模式） | 所有权/别名限定符：`box/iso/val/ref/shared/rawptr` | region / cap |
| cap（权限令牌） | `Cap[T]`，线性值，签发制；**v0 不可撤销**（H-LS-20） | mode / effect |
| effect（效果） | `eff(...)`，函数类型的一部分，集合偏序 | cap / mode |
| profile | `agent` / `kernel` 执行契约；**crate 图分区** | edition |
| 安全子集 | `Safe(P)` 闭包：无 unsafe 且所有可达模块 Safe 或 Trusted（§8.2） | 语法排除式定义 |
| UB | §8.1 表中的 15 条，唯一权威 | 「未定义行为」口语 |
| 能力清单 | 由 AST 推导的部署清单（§7.4） | `Cap` 类型 |
| 试金石 | S0′/S0″ 的 5 个系统程序 | 基准集 |

### 15.2 EBNF 骨架（草案片段，已同步本版决策）

```ebnf
(* 草案；最终以 spec/langSysQuanta.ebnf 为准 *)

SourceFile    = { Attribute } ModuleDecl ProfileDecl { Item } ;
ModuleDecl    = 'module' Path ';' ;
ProfileDecl   = 'profile' ( 'agent' | 'kernel' ) ';' ;

Item          = FnDecl | StructDecl | EnumDecl | UnionDecl | TraitDecl | ImplDecl
              | RegionDecl | ConstDecl | StaticDecl | ExternDecl | UseDecl ;
UnionDecl     = 'union' Ident '{' { FieldDecl } '}' ;

StaticDecl    = 'static' Ident ':' Type '=' Expr ';' ;   (* 类型仅 val/shared/cell *)
RegionDecl    = 'region' Ident '{' { Stmt } '}' ;
RegionAlloc   = Ident '.' 'allocator' '(' ')' ;      (* Alloc[Region] *)
BorrowExpr    = 'borrow' [ 'mut' ] Expr 'as' Ident Block ;
RecoverExpr   = 'recover' Block ;                    (* val -> iso，线性消费 *)
DeferStmt     = 'defer' Expr ';' ;                   (* 作用域退出消费，恰好一次 *)

Attribute     = '#[' AttrName [ '(' AttrArgs ')' ] ']' ;   (* 封闭集合 *)
AttrName      = 'repr' | 'align' | 'bitfield' | 'register'
              | 'nondet' | 'irq' | 'test' | 'prop'
              | 'trusted' | 'forbid' | 'boundary' | 'fault' | 'cap' | 'stack'
              | 'recursion' | 'bounds' | 'overflow' | 'fp' | 'must_release'
              | 'error_domain' | 'no_mangle' | 'link_section' | 'used'
              | 'naked' | 'link' | 'generated' ;

ModeType      = ( 'box' | 'iso' | 'val' | 'ref' | 'shared' | 'rawptr' )
                '[' Type ']' ;
HwType        = 'Mmio' '[' Type ']' | 'DmaToken'
              | 'Lock' '[' Type ',' ConstExpr ']' | 'Cell' '[' Type ']' ;

Type          = Path [ '[' TypeArgs ']' ]          (* 泛型只用 []；无 lifetime 参数 *)
              | ModeType | HwType
              | 'Fn' '(' [ TypeList ] ')' [ '->' Type ] [ EffClause ] ;

(* 表达式位置不写泛型实参（决策 D2）；调用即 f(x)，T 由期望类型推断 *)
UnsafeExpr    = 'unsafe' '(' [ CapExpr ] ')' Block ;   (* 模块 #[cap] 下可省略 *)
AsmExpr       = 'asm' '(' String [ ',' OperandList ] ')' ;  (* 操作数/破坏列表 *)
MatchExpr     = 'match' Expr '{' { Pattern '=>' Expr [ ',' ] } '}' ;
ClosureExpr   = '|' [ ParamList ] '|' Expr ;
CapExpr       = Path ;                              (* 必须是作用域内的 Cap 值 *)
EffectList    = 'eff' '(' [ Effect { ',' Effect } [ ',' ] ] ')' ;

FnDecl        = [ 'unsafe' ] 'fn' Ident [ '[' GenParams ']' ]
                '(' [ ParamList ] ')' [ '->' Type ]
                [ Contract ] [ EffClause ] Block ;
GenParams     = GenericParam { ',' GenericParam } ;
GenericParam  = Ident [ ':' Type ] | 'const' Ident ':' Type ;
Contract      = { 'requires' Expr } { 'ensures' Expr } ;

(* 注意：无 lifetime 参数；无宏调用；无 turbofish；变体统一 Type.Variant *)
```

### 15.3 决策登记（新增，供实现与 AI 对齐）

| # | 决策 | 理由 | 影响 |
|---|---|---|---|
| D1 | 泛型用 `[]` | 沿用 L | 与索引需消歧 |
| D2 | **表达式位置不写泛型实参（无 turbofish）** | 保持 EBNF 单义（LS-P18） | 推断失败需类型标注 `let` |
| D3 | 变体唯一写法 `Type.Variant` | 单一规范形（LS-P2） | 无 `::`、无裸变体名 |
| D4 | **region 不是类型；跨过程用 `Alloc` 句柄** | 消解 0.1.0 三重矛盾 | ρ 只在推断类型 |
| D5 | `iso → val` 单向；还原用 `recover` | 唯一性 sound | 删除 `thaw` |
| D6 | `panic = abort`（v0） | 避免 unwind×Drop×FFI 复杂度 | H-LS-19 |
| D7 | `kernel` 禁止隐式 Drop；递归默认禁，`#[recursion(bound)]` 逃生舱 | 静态栈/资源可控 | `E-LS-DROP`/`E-LS-RECURSION`/`E-LS-STACK` |
| D8 | 禁止 build script | 防宏/UB 后门（LS-12） | manifest 描述一切 |
| D9 | `module`/`profile` 为独立声明，不用属性 | 消除分号/属性规范形分歧 | EBNF 更简单 |
| D10 | 属性集**封闭**，不可用户扩展 | EBNF 权威 | 需求走 RFC |
| D11 | `box` 不跨域，`iso` 才跨域 | `spawn` 签名自说明风险 | 需显式 `transfer` |
| D12 | MMIO 为安全 API（cap 控制），非 unsafe | 降低 unsafe 面积 | `Mmio[T]` 类型 |
| D13 | 自动修复禁止新增 unsafe/cap | 防止攻击面扩大 | 硬门禁 |
| D14 | `cell[T]` 为单域容器（`Local`），`shared[T]` 为锁语义 | 区分内部可变与跨域共享 | 原子需 `shared[Atomic[T]]` |
| D15 | `Mmio[T]`/`Alloc[Region]`/`Slice` 为 affine | 防权限复制/ρ 逃逸 | 不可 Copy/存字段 |
| D16 | cap 只能**借出** `Mmio` 视图 | 唯一视图，保留线性 | 同 cap 同时最多一视图 |
| D17 | 无 `static mut`；`static` 仅 `val`/`shared`/`cell` | 消除 UB 面 | 编译期初始化 |
| D18 | profile 为 crate 图分区；v0 禁止跨 profile 静态链接 | 避免未定义 ABI | 跨域仅 `#[boundary]` |
| D19 | `release(self)` 消费并返回 `Result` | teardown 有错误通道 | 使用原变量即 `E-LS-MOVE` |
| D20 | 语言定义整数 wrapping；checked 只是调试 trap | profile 不改变语义 | agent/kernel 同语义 |
| D21 | 成本模型为一等规范（`spec/cost.md`） | 可预测性能 | `ls cost` |
| D22 | 分析模块化：函数级缓存 + crate 级实例；impl 遵循 orphan 规则（ADR-17） | 保住 G-S5 | 全程序分析仅链接期 |
| D23 | 加载器/`comptime`/内建属性入 TCB | `Enforced` 有执行者 | `spec/tcb.md` |
| D24 | `Safe(P)` 为闭包 + `Trusted` 集合 | 承诺可判定 | `ls audit` |
| D25 | `explore`/`seal` 只差守卫，提供 `--guards=keep` | 认证构建 | H-LS-23 |
| D26 | v0 不做 cap 撤销；删除「可吊销」 | 诚实 + 零成本 | H-LS-20 |
| D27 | Trusted = `trusted.lock` 内容寻址 + 逐项目钉住 + 失败关闭 + 无传递信任 | 可复现/可审计 | `E-LS-TRUST`；H-LS-25 |
| D28 | 加载器 Ed25519 + root/build 双层 + dev/prod 分离 + 防回滚 | 验签可复现 | `spec/image.md`；H-LS-26 |
| D29 | trait 默认 `#[open]` + orphan 规则；`#[sealed]` 显式；`#[orphan]` 推迟 S4 | 生态可用且增量可达 | `E-LS-COHERENCE`；H-LS-27 |
| D30 | `val` 字段可返回；`ref` 字段不可返回；Cursor = `val + pos` | 零拷贝 API 可行 | `E-LS-REGION-ESCAPE`；H-LS-28 |
| D31 | `#[recursion(bound=N)]` 有界递归 + 静态栈上界 | kernel 表达树结构 | `E-LS-STACK`；H-LS-29 |
| D32 | `defer expr;` + `#[must_release]` + `E-LS-LEAK` | 错误路径不泄漏 | 档案 C-8 |
| D33 | 模块 `#[cap]` 上下文 + `#[bounds]/#[overflow]/#[fp]` 旋钮 | 降 unsafe 面积/热路径可控 | `E-LS-CAPCTX`/`E-LS-DIAL` |
| D34 | 封闭属性集增加裸机代码生成指令 + asm 操作数 | 裸机可落地 | `spec/baremetal.md` |
| D35 | SVD/bindgen/gen 为一等构建步骤；`[target]` 矩阵 | 代码生成可复现 | `spec/toolchain.md` |
| D36 | LSP/SARIF/explain/`@generated` 提前到 S1 | 工程采纳 | LS-P19 |
| D37 | C 互操作补 `repr(transparent)`/`union`/`#[link]`/类型映射 | 迁移可行 | 档案 C-10 |
| D38 | quickstart（QEMU + 板）为 S0′ 交付物 | 2 小时可跑通 | `time_to_first_blinky` |
| D39 | 场景判定：MCU/RTOS 为目标；手机 OS/App 不在本分支 | 避免承诺误读 | §1.2/§1.5；ADR-21…27 门槛 |
| D40 | 编译器策略：Rust 参考 + C seed/B-LS 无依赖链；纯汇编编译器非目标 | 依赖最小化 + 可复现 | `05`；ADR-28…30 |

### 15.4 与 L 的文档映射

| L 文档 | L-Sys 的复用方式 |
|---|---|
| `01` 目标与原则 | 复用方法论；目标替换为 G-S1…G-S5 |
| `02` 语法设计稿 | 复用 EBNF/诊断/双模式思想；语法重写 |
| `03` 演进路线 | 复用 edition/DoD/枪毙条件；阶段改为 S-1…S5 |
| `08` 数学基础 | 复用形式化方法论；新增内存/并发/provenance 定理 |
| `spec/eval-protocol.md` | 直接复用四臂/EL-1/判决纪律 |
| `spec/capabilities.md` | **只复用签发/消费点方法论**；`Cap` 语义分叉（见 §15.1） |
| `spec/runtime.md` | 复用预算/确定性；替换为原生后端 |
| `09` 语法教学手册 | 复用教学结构；L-Sys 重写 quickstart/驱动/迁移教程（03 E1） |
| `03` 开发与工程实践评审 | 三份硬模式档案 + S-1 验收清单（本分支新增） |
| `05` Bootstrap 实施计划 | 无 LLVM/Rust 依赖链；B-LS + C seed + 三阶段 |

### 15.5 下一步（本版之后）

1. **先评审 [`02`](02-架构评审与ADR.md) 的 ADR-1…30 与 [`03`](03-开发与工程实践评审.md) 的三份档案**；
   特别确认：Safe 闭包、TCB（含加载器）、`Mmio` 仿射性、profile 分区、镜像格式、
   视图规则、`defer`、模块 cap、裸机属性；
2. 写 `spec/ub.md`、`spec/modes.md`、`spec/effects.md`、`spec/image.md`（四份必须）；
3. 写 `spec/baremetal.md`、`spec/resource.md`、`spec/cap-context.md`、`spec/toolchain.md`（04 产物）；
4. `spec/cost.md`、`spec/trust.md`、`spec/coherence.md` 出 skeleton 即可；
5. 写 `spec/langSysQuanta.ebnf` 最小可解析子集（覆盖 §5 全部代码块）；
6. 用检查器接受 03 档案 A/B（C 先类型检查），并跑通负例；
7. S0′ 交 quickstart + LSP 骨架 + SARIF；冻结 DoD 与枪毙条件；
8. 建立 `H-LS-*` 唯一登记处与自检脚本（表与正文双向满射）；
9. 按 [`04-S-1-执行计划.md`](04-S-1-执行计划.md) 执行 8 周 S-1：先档案 A/C，再四份必须规范；
10. 并行推进 [`05-Bootstrap-实施计划.md`](05-Bootstrap-实施计划.md)：M0 已落地，下一步 M1（B-LS 结构/控制流）。

---

> **本文是初稿，不是承诺。** 任何「L-Sys 能做到 X」的表述，都必须先过 S-1…S5 的 DoD；
> 任何「优于 C/Rust」的表述，都必须先有 `results/<run-id>.json`。
