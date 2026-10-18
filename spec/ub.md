# spec/ub.md · UB 清单与 provenance 决策

> **状态**：`草稿`（15 条条目与诊断码已冻结；oracle 实现待 S0′/S1）
> **上位**：[`00 §8.1`](../00-LangSysQuanta-设计初稿.md)（UB 清单，**唯一权威**）、
> [`00 §8.2`](../00-LangSysQuanta-设计初稿.md)（安全子集闭包，决策 **D24**）。
> **相关**：`H-LS-4`（`unsafe` 深层 soundness，`Out-of-scope`）、`H-LS-16`（中断域）、
> 决策 **Q5**（provenance 模型）、`spec/trust.md`。
> **规则**：新增 UB 必须走 edition 变更；本表是「安全子集无 UB」的**唯一 oracle**。

## 1. 清单

「安全子集可达 = 否」表示：在 `Safe(P)` 成立的程序里语言保证不发生。
「仅 `unsafe`」表示：只有显式 `unsafe` + 满足契约时才可能出现，由契约与审计承担。

| # | UB | 安全子集可达 | 检测 / 处理 | 诊断码 | oracle（如何验证被防住） |
|---|---|:--:|---|---|---|
| UB-1 | 越界读/写 | 否 | 默认边界检查；`explore` 守卫 | `E-LS-BOUNDS` | 负例：`tests/conformance/reject/bounds.ls` 报 `E-LS-BOUNDS`；正例：契约可证时边界检查被消除（`ls cost`） |
| UB-2 | 悬垂引用/指针 | 否 | 区域约束检查 | `E-LS-ESCAPE` | 负例：`dossiers/views/reject.ls` 的越界派生（`E-LS-REGION-ESCAPE`）+ region 逃逸负例 |
| UB-3 | double free / 重复 drop | 否 | 线性所有权 | `E-LS-DROP` | 负例：同一 `box` 二次 move/drop；正例：`iso` 转移后原绑定不可用 |
| UB-4 | 使用未初始化 | 否 | 初始化检查 | `E-LS-INIT` | 负例：`let x: T;` 后读取 |
| UB-5 | 数据竞争（线程域） | 否 | mode `R6`/`R8` | `E-LS-RACE` | 负例：`shared` 写入 + 并发送达；正例：`iso`/`val` 转移 |
| UB-6 | 整数溢出 | 否 | 语言定义 **wrapping**；`agent` checked 为调试 trap（非不同语义） | `E-LS-OVERFLOW` / `W-LS-OVERFLOW` | 正例：`Int.MAX + 1` wrap 结果可预测；`agent` 下同表达式 trap |
| UB-7 | 除零 / 非法移位 | 否 | trap（**定义行为**：abort） | — | 运行期 oracle：退出码与 `abort` 一致，不是未定义结果 |
| UB-8 | 解引用 null/野指针 | 仅 `unsafe` | 契约 + `Witness` | `E-LS-PROV` | 负例：`unsafe` 块内无 `Witness` 的 `rawptr` 解引用 |
| UB-9 | 未对齐访问 | 仅 `unsafe` | 契约 / `align_of` 检查 | `E-LS-PROV` | 负例：用 `align_of::<T>()` 可证的对齐违约 |
| UB-10 | 违反 provenance（别名/越界派生） | 仅 `unsafe` | **Tree Borrows 简化子集** + 契约（见 §2） | `E-LS-PROV` | 负例：`dossiers/slab/reject.ls` 的 `E-LS-PROV` 两例（越界派生、跨域别名） |
| UB-11 | MMIO 非 volatile 访问被优化/重排 | 否（须用 `Mmio[T]`） | 类型固定 volatile + `fence` | `E-LS-PROV` | 负例：普通 `*T` 访问 `Mmio` 区域；正例：`Mmio[T]` 访问在 `ls cost` 中显示 1 volatile |
| UB-12 | 未定义求值顺序 | 否 | **规范求值序**：从左到右、先求值后调用 | — | 正例：`f(g(), h())` 的求值顺序在 IR 与产物中一致（`spec/bls.md` 同规则） |
| UB-13 | 栈溢出 | `agent` 可达；`kernel` 否 | `agent` depth 预算；`kernel` 静态栈上界 | `W-LS-STACK` / `E-LS-RECURSION` | 负例：`dossiers/recursion/reject.ls`（`E-LS-RECURSION` / `E-LS-STACK`）；正例：`accept_stack.ls` 显式栈 |
| UB-14 | drop 期间使用已释放对象 | 否（`abort`，无 unwind） | 见 `00 §6.6` | `E-LS-DROP` | 负例：`drop` 实现中访问已释放字段 |
| UB-15 | 跨 FFI 的 unwind | 否 | `extern "C"` 隐含 `nounwind` | `E-LS-ABI` | 负例：`extern "C"` 函数体内 `?`/`panic` 越过边界 |

## 2. provenance 决策（UB-10，Q5）

- **模型名**：Tree Borrows 的**简化子集**（`00 §6.9` 建议），不是 Stacked Borrows 全量；
- **可判定部分**：`ref` 派生链在编译期可见时完全静态检查；
  `unsafe` 内的 `rawptr` 派生以**契约 + `Witness`** 承担，超出部分记入 `ls audit` 的「未判定项」；
- **禁止**：`rawptr` 与 `ref` 混用后声明「无 UB」——在 S-1 冻结前该组合属于**未定义状态**；
- 决策状态：**Q5 未关闭**，本文件只冻结「模型名 + 简化范围」，不冻结完整规则。

## 3. 规则

- 本表与 `00 §8.1` 必须逐行一致；任何差异以 `00` 为准并回改本文件；
- 每条 UB 的 oracle 必须是**可执行**的：要么 `tools/checker-spike` 报出对应诊断码，要么运行期行为可断言；
- 诊断码新增需同时登记到 `00 §11`（诊断表）与 `00 §12`（`H-LS-*`，若涉及能力降级）；
- 不得用「安全子集不含 unsafe」这类**排除式**说法替代闭包定义（`00 §8.2` D24）。

## 4. 待办

- [ ] 为 UB-1/3/4/5/14/15 各补一条 `tests/conformance/reject` 负例（当前仅有 UB-2/10/13 的覆盖）；
- [ ] UB-7 的「定义行为」需要写成可断言 oracle（`abort` 的退出码与信号）；
- [ ] UB-12 需要在 `spec/bls.md` 与正式 EBNF 里同步求值序条款；
- [ ] `E-LS-PROV` 目前由 `dossiers/slab/reject.ls` 覆盖，需扩展到 `unsafe` 契约负例集；
- [ ] Q5 关闭条件：Tree Borrows 子集规则写成可执行检查（S3 检查器）。
