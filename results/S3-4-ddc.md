# S3-4 · 双 C 编译器 seed DDC 与自编译差分门

> 状态：**dual 门与 self-diff 门实现完成；QEMU 全量 gate 轮 PASS（2026-11-28：102 项/18 项
> 分歧与 known-gaps 精确互匹配，§6）；自编译 struct 缺陷时间盒内完成排除法收窄与首行诊断
> 四家族提取（未定位到行，专项交接，见 §7）**；
> commit：随 S3-4 提交批次入库（gate 轮证据见 §6）。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §6.3（信任与可复现第 1/2 条）、§6.6；
> 前序：[`results/S3-1-desseed.md`](S3-1-desseed.md) §3（自编译版 struct 字段 codegen 缺陷登记，
> 本项差分门即其验收载体）、[`results/S3-2-split.md`](S3-2-split.md)（模块拆分）、
> [`results/S3-3-target-abstraction.md`](S3-3-target-abstraction.md)（Target 描述表与本报告 §2 的勘误纠偏）。
> 关键设计：①self-diff 门**比行为不比字节**（§4.2 实证：旧 seed codegen 与 names_stage codegen
> 对同输入产物本就互异）；②known-gaps 是**精确互匹配账本**（未知差异 FAIL、修复后过期条目也 FAIL，
> 强制清账）；③缺陷二进制可在 Windows 宿主**逐字节复现**（§2 黄金事实），调试不必依赖 QEMU。

## 1. 范围与任务分解

| 子项 | 内容 | 状态 |
|---|---|---|
| S3-4a | `bootstrap/ci/ddc.sh dual`：双 C 编译器构建 seed，全链产物逐字节一致（05 §6.3 第 1/2 条）| ✅ 落地（本地 clang＋MSVC 全绿；CI `ddc-dual` job＝gcc＋clang） |
| S3-4b | `ddc.sh self-diff`：自编译版（stage2_self）对 seed-built 参考版（stage1-seed）全语料**行为等价**差分门 | ✅ 落地（ENUMERATE 基线＋GATE 精确互匹配；6 探针） |
| S3-4c | 时间盒内尝试定位 S3-1 §3 登记的 struct 字段缺陷 | 🟡 收窄未定位（§5 排除法：七个被调函数＋两处调用侧接线全排除，嫌疑面收至 giant caller 内联段；专项交接 §7） |
| 交付形态 | 两道门进 CI（`ddc-dual` job + run-stage1.sh 尾部接线）；缺陷差异以 `bootstrap/ci/ddc-known-gaps.txt` 门禁化挂账 | ✅ |

## 2. 本地复现与反汇编求证（缺陷调试的黄金事实）

三名产物（均在 Windows 宿主可复现生成，命令见 §7 调试资产）：

| 产物 | 生成方式 | sha256（前 8 位） | 说明 |
|---|---|---|---|
| A.elf | `seed --run names_stage.ls <X>`（seed 编译模式，`-o`/两参形态） | `27572509` | seed 的 `-o` 编译模式（历史 codegen）编译 names_stage 的产物 |
| B.elf | `seed --run names_stage.ls names_stage.ls B.elf`（解释自编译） | `70301239` | **与 QEMU guest 固定点指纹 `703012394f7f…a027`（freeze-manifest §3，S3-3 轮登记）逐字节一致**——解释器逐位忠实，坏编译器二进制在宿主可逐字节复现，ndisasm 求证（基址 `-o 0x400078`）不必进 QEMU |

**「两个不同编译器」实证**（self-diff 门不比字节的依据，产物批 `.temp/s3diff/{old,new,seedmode}/`）：

- seed 的 `-o` 编译模式与 names_stage codegen 是**两套 codegen**：17 个可编译语料在两模式下产物 **17/17 互异**；
- 8 个 Stage 2 特性测试在 seed 编译模式下直接编译失败（旧 codegen 不支持）——「字节等价」在自编译差分里既不成立也无意义，门必须比**行为**（编译成败、退出码、stdout）。

**name_id 源码级核实（S3-3 报告尾部勘误的证据）**：`st_find`/`name_id` 路径的源码
（`src/modules/20-symtab.ls`）确认名字**条目表**布局——计数 `post[16000]`、池用量 `post[16001]`、
条目自 `post[16002 + 2·i]` 起（每名 2 槽：偏移＋长度）、字节池在 `post[18000 + idx/8]`；
names_stage 自身约 524 个唯一标识符使条目数组恰好伸到 `16002 + 2×524 = 17050`。B.elf 中
`name_id` 的机器码（`cqo`/`idiv` 序列取 `rdx` 余数）与该源码语义一致。**结论**：S3-3 首轮选址
`post[17050]` 的覆盖源是名字条目表而非字节池（S3-3 报告 §2.1 尾部勘误，随本批提交）。

## 3. dual 门（S3-4a）：双编译器 DDC

`bootstrap/ci/ddc.sh dual`（`DDC_CC1`/`DDC_CC2` 可覆盖），五步断言链：

1. 双 seed 解释器冒烟（hello）均 rc=0、输出一致；
2. hello 编译产物：`seed1 hello.ls -o` vs `seed2 hello.ls -o` **逐字节一致**；
3. 核心：stage1（names_stage 被各 seed 编译）**逐字节一致**——DDC 的经典形态（05 §6.3 第 1 条）；
4. 解释自编译产物（`seedN --run names_stage.ls names_stage.ls`）**逐字节一致**（05 §6.3 第 2 条）；
5. Linux 宿主延伸：原生 stage2 一致＋「原生 stage2 == 解释自编译」（解释器忠实性）；Windows 跳过该段。

**结果（2026-11-28，本地 clang + MSVC，两轮全绿——第二轮为 self-diff 打印补丁＋水印过滤修复后的复跑）**：
hello/stage1/解释自编译全链逐字节一致；stage1 `27572509e29c…a87b`、自编译 `703012394f7f…a027`
（后者即固定点指纹）。**顺带证明 seed.c 无编译器敏感 UB**。

**MSVC 接入坑（本地第二编译器；CI 用 ubuntu 预装 gcc＋显式安装 clang）**，沉淀为
`.temp/s3diff/msvc-cc.sh` + `vsenv.bat`（调试资产不进库，发布接口就是 `DDC_CC1/CC2` 环境变量）：

- VsDevCmd 环境导入走**批处理中转文件**（`vsenv.bat` 落盘 `set` 输出，纯 ASCII、无空格路径）——
  msys 直接给 `cmd /c` 传长引号命令串会被引号改写弄坏；
- cl 调用整体加 `MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*'`——否则 `/Fe:`/`/Fo:` 被 msys 当
  POSIX 路径表转成 `D:\systool\Git\Fe;…`；
- `/utf-8` 让 cl 按 UTF-8 读源（否则 C4819 代码页告警下与非 UTF-8 读法的编译器不可比）。

**CI**：`.github/workflows/bootstrap.yml` 新增 `ddc-dual` job（ubuntu-latest，apt 装 clang，
`bash bootstrap/ci/ddc.sh dual`）。

## 4. self-diff 门（S3-4b）：自编译差分

### 4.1 形态

run-stage1.sh 末尾接线（QEMU guest / Linux CI 内执行；Windows 宿主自动跳过）：
对**全量编译测试语料**（96 语料项＋6 探针＝102 项）逐项——

- 参考侧 `build/stage1-seed`（seed-built）、受试侧 `build/stage2_self`（自编译）分别编译；
- 编译成功则**执行**产物，比较（退出码, stdout）；编译成败不一致本身即分歧；
- self 侧编译失败时打印其日志**首行**（gate 轮起为定位缺陷提取证据）；
- 字节不比较（§2「两个不同编译器」实证）。

### 4.2 模式与账本

- `DDC_SELF_DIFF_MODE=gate`（默认）：差异集必须与 `bootstrap/ci/ddc-known-gaps.txt` **精确互匹配**
  ——计数一致、无未登记差异（否则 FAIL，新回归挡在门外）、无过期条目（已修复但未清账也 FAIL，
  **强制清账**）；
- `DDC_SELF_DIFF_MODE=enumerate`：只打印表不设门（基线收集用）。

**水印过滤修复（19≠18 的真因）**：known-gaps 文件尾部带平台 AIGC 尾注行（`AI生成`，按平台
策略保留），旧解析把它计为条目（19≠18 必假失败）。修复＝ddc.sh 三处 grep 读该文件时加
`-e '^AI生成\s*$'` 过滤（计数、FAIL 展示、stale 循环）。此前「注释续行缺 `#`」的初判不成立——
注释行本就全部带 `#`。

### 4.3 探针（`bootstrap/bls/tests/ddc-probe/`，登记进 known-gaps）

| 探针 | 形态 | 期望 | 枚举轮结果 |
|---|---|---|---|
| probe-s1-no-struct | 无 struct 对照（同族语句面） | 181 | 一致 |
| probe-s2-struct-write | 声明＋未初始化 typed 变量＋**单次字段写**（9 行最小复现） | 3 | **分歧**（self 侧编译失败） |
| probe-s3-struct-two-writes | 两次字段写 | 7 | **分歧** |
| probe-s4-struct-read-expr | 声明＋读入表达式 | 7 | **分歧** |
| probe-s5-struct-match-blend | match 混合分支 | 177 | **分歧** |
| probe-s6-struct-five-fields | 五字段 | 15 | **分歧** |

## 5. 枚举轮基线与排除映射（S3-4c 时间盒）

### 5.1 枚举基线（QEMU ENUMERATE，2026-11-28，RESULT=PASS，~93 分钟）

**102 项中 18 项分歧，全部是声明 struct 的程序**；非 struct 的 84 项（含 probe-s1）行为全一致。
最小复现 probe-s2 仅 9 行——缺陷与程序规模无关；**用户 struct 声明＋字段访问**在自编译版下
必失败。分歧清单（=known-gaps 条目）：stage1_names、gen_struct_fields、stage1_struct_value、
stage1_gen_struct_param、stage1_gen_struct_new、stage1_trait_calls、ref_fields、ref_escape_ok、
ref_array、effects、contracts、struct_payload、stage1_trait_eq_ord、probe-s2…probe-s6（5 项）。
枚举轮至少一例（ref_payload 与 effects 之间）自编译器**段错误**（非干净拒编译）——
各项首行诊断以 §6 gate 轮打印为准。

### 5.2 排除映射（B.elf 反汇编，ndisasm 基址 `-o 0x400078`）

| 部位 | B.elf 地址 | 核对方式 | 结论 |
|---|---|---|---|
| `st_find` | `0x41B396` | 机器码与 `30-types.ls` 源码逐段对应 | ✅ 语义正确 |
| `st_add` | `0x41B4B6` | 同上（含调用点接线） | ✅ |
| `st_field_add` | `0x41B5B5` | 同上 | ✅ |
| `st_field_find` | `0x41B72C` | 同上 | ✅ |
| `st_size` | `0x41B8A2` | 同上 | ✅ |
| `sv_add` | `0x41BC67` | 6 槽 prologue（含 r9 保存/恢复） | ✅ |
| `name_id` | —（源码级＋`cqo/idiv` 序列） | `20-symtab.ls` 源码核实（§2） | ✅ |
| 调用侧接线（field 写/读路径实参） | giant caller 内 | `name_id` 结果→`fld`、`sv_find`→`svi`、`6404+svi*4`→`sidx` 偏移序列逐条核对 | ✅ |
| 声明侧调用点 | 结构声明处 | `st_add` 调用序 | ✅ |

**收窄后的嫌疑面**：七个被调函数与两处接线全部排除 ⇒ 缺陷藏在 **giant caller** 的内联
struct 分支（`85-emit-stmts.ls` 的 `emit_body`/`emit_stmt_span` struct 路径，行 ~2010–2080，
`unknown field` 诊断在 2038/2060 区）或 scan 侧数据装配——这正是名字 Stage 拆分后每个函数
体量过大的直接代价，与 S3-1 §3「分阶段拆小」的后续建议互证。

## 6. Gate 轮结果（QEMU 全量，2026-11-28，RESULT=PASS）

同轮次完整套件（run-linux＋run-stage1＋S3-1 主路径断言＋self-diff 门，gate 为默认模式）
在 QEMU/TCG guest 内一次通过：guest 内核运行 **5028.7 s（≈83.8 分钟；枚举轮 87.7 分钟）**；
`QEMU-GUEST: RESULT=PASS`、`exit=0`。

- **固定点（再确认）**：`build/stage2_self == build/stage3_self`，指纹 `703012394f7f…a027`
  ——与 §2 宿主复现的 B.elf/self1 **同一指纹**：解释器逐位忠实性的三途径闭环
  （QEMU guest 固定点＝宿主 clang seed 解释自编译＝宿主双编译器一致产物）；
- **self-diff**：102 项、18 项分歧，日志打出 **`PASS self-diff: divergences match
  known-gaps exactly (18)`**——精确互匹配（18==18，水印过滤后）＋集合成员双向核对通过；
- 其余随套件断言（S3-1 selfhost 主路径、stage2 编译 calc/high/big/huge-offset、
  self-host determinism、stage2==stage3）全部 PASS。

### 6.1 18 项 self 侧编译失败首行诊断（缺陷定位的第一手输入）

| 程序 | self 侧首行 | 家族 |
|---|---|---|
| stage1_names | `struct: unknown field` | A |
| gen_struct_fields | `struct: unknown field` | A |
| ref_fields | `struct: unknown field` | A |
| ref_escape_ok | `struct: unknown field` | A |
| ref_array | `struct: unknown field` | A |
| struct_payload | `struct: unknown field` | A |
| probe-s2-struct-write | `struct: unknown field` | A |
| probe-s3-struct-two-writes | `struct: unknown field` | A |
| probe-s4-struct-read-expr | `struct: unknown field` | A |
| probe-s5-struct-match-blend | `struct: unknown field` | A |
| probe-s6-struct-five-fields | `struct: unknown field` | A |
| stage1_struct_value | `slice: bad expr` | B |
| stage1_gen_struct_param | `slice: bad expr` | B |
| stage1_gen_struct_new | `slice: bad expr` | B |
| stage1_trait_calls | `ctl: bad if expr` | C |
| stage1_trait_eq_ord | `ctl: bad if expr` | C |
| contracts | `stage1: E-LS-COMPTIME: 18:5: comptime block needs a constant expression` | D |
| effects | （空——自编译器段错误，无诊断输出） | E |

家族解读（时间盒内不主张单一根因，但方向一致）：

- **A（11 项，含全部 5 个 struct 探针）**：字段查找在自编译版中拿不到正确元数据——与
  §5.2 排除映射（`st_field_find` 本体正确）拼合，指向 **caller 侧 st/sv 实参装配或
  字段表区间**的内联段；probe-s2（9 行、单次字段写）即最小复现，从它出发；
- **B（3 项，全部 struct 值构造）**：值构造表达式的字段索引装配——同链路下游形态；
- **C（2 项，trait 比较）**：以 struct 字段为判据的 if 表达式失效——下游级联；
- **D/E（各 1 项）**：常量表达式求值走不通＋一例编译器段错误——级联最深两端；E 无诊断，
  意味着可能叠加越界访问（布局/守卫问题），修复后重点回归；
- 原始日志另有两处 bash `Segmentation fault` 提示，属 **stage1_io 参考侧行为本身**
  （双侧 rc 均 139、行为一致非分歧），不是缺陷信号。

§7 定位手段 1（首行诊断表）就此兑现：优先沿家族 A 的 caller 装配路径排查。

## 7. 缺陷修复专项交接（S3-1 §3 挂账，S3-4 门禁化）

- **触发即报**：修复后 self-diff gate 对已知条目报 **stale**——known-gaps 清空条目（文件与
  头注保留）、gate 断言 18→0、QEMU 全量绿、固定点指纹按源码变更重登记（freeze-manifest §3）。
- **定位手段优先级**（宿主可复现 B.elf，黄金事实见 §2）：
  1. §6 gate 轮的 18 项首行诊断表——全部同诊断（如 `struct: unknown field`）则指向 field
     查找路径实参装配于 B.elf 的偏差；含段错误则先行查布局/越界；
  2. A/B 行为对照：受试侧换 `.temp/s3diff/B.elf`，宿主直接对 6 探针复现（不必 QEMU）；
  3. 二分注入：`30-types.ls`/`85-emit-stmts.ls` 临时加 write 副作用（本地调试用，不提交；
     守 128/128 顶层函数上限）后 `assemble.sh` 重生成对照；
  4. 函数删除二分（giant caller 嫌疑段）。
- **调试资产**（`.temp/s3diff/`，本地复现命令）：`A.elf`/`B.elf`/`A.asm`/`B.asm`（ndisasm 转储）、
  `msvc-cc.sh`＋`vsenv.bat`（§3）、`mk.sh`（S3-3 语料批）、`callsites.py`/`grepctx.py`（调用点/上下文
  检索）、`seed-vs-interp.sh`、`selfdiff.sh`、`verify-withself.sh`、`old|new|seedmode/` 产物批。

## 8. 结论

- 05 §6.3 第 1/2 条（双编译器 seed＋DDC）落地为 `ddc.sh` 双门＋CI 接线；本地 clang/MSVC、
  CI gcc/clang 两条第二编译器路径均闭环；**seed.c 无编译器敏感 UB** 得到双编译器实证；
- 自编译差分从「无载体」变为「门禁化挂账」：18 项 struct 缺陷全部登记、精确互匹配、
  修复即强制清账；探针族（9 行最小复现）为专项修复提供即用回归面；
- S3-4c 诚实收口：时间盒内未定位到行级——排除映射（§5.2）已把嫌疑面收至 giant caller
  内联 struct 分支，宿主可复现 B.elf＋首行诊断表交接专项（§7）。

> AI生成
