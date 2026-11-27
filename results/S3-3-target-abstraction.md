# S3-3 · Target 抽象（Q7 T1 行，数据层 + syscall 序列层表驱动）

> 状态：**实现完成，QEMU 全量验证通过（2026-11-28，第 4 轮，主验证收官）**；
> commit：随 S3-3 提交批次入库（证据命令与输出见 §4）。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §6/§6.2（`Target` 抽象；先整程序编译）、
> [`spec/toolchain.md`](../spec/toolchain.md) §1（Q7 三目标矩阵，T1 = `x86_64-unknown-linux-gnu`）；
> 前序：[`results/S3-1-desseed.md`](S3-1-desseed.md)（去种子后主路径全由 stage2_self 编译）、
> [`results/S3-2-split.md`](S3-2-split.md)（模块化为 `src/modules/*.ls`，本项首次按模块编辑）。
> 关键约束：①`names_stage` 顶层函数 **128/128 触顶**——描述表与全部接线**零新增顶层函数**；
> ②EBNF v2.3 冻结——Target 是编译器内部结构，不进语言面；③固定点指纹**必然漂移**
> （源码变化 ⇒ 编译器二进制变化 ⇒ 自编译产物变化），新值随 QEMU 登记。

## 1. 范围（按 2026-11-28 裁定：指令层一并抽象）

| 层 | 内容 | 状态 |
|---|---|---|
| **数据层**：ELF 镜像 | e_ident class/data、e_type、e_machine、p_align、image base、BSS heap 预算 | ✅ 表驱动 |
| **数据层**：Linux syscall ABI | read/write/openat/close/exit 号、AT_FDCWD（u32 形态） | ✅ 表驱动 |
| **指令层**：syscall 调用序列 | 号装载指令（`mov eax,imm32`）与 `syscall` 指令对（0F 05）的字节值 | ✅ 表驱动（2026-11-28 裁定扩展） |
| 指令层：寄存器编码 / MODRM / 数据传送 | `mov rdi,...` 等 System V 参数装载、RIP 相对寻址 | ⬜ **不抽象**（见 §3 边界） |
| ARM64 / Cortex-M / RV32 行 | 第二目标 | ⬜ 未做（挂点清单见 §5） |
| CLI / 语言面暴露 target 选择 | — | **不做**（不动 argv 契约与 EBNF；target 是构建输入而非程序输入） |

## 2. 实现

### 2.1 Target 描述表（`post[262000..262016]`，17 槽；sast 上界与 ctxi 之间的死区）

`modules/90-main.ls` main 早期初始化（`let ps` 构造后立即），**单一事实源**：

| 槽 | 名（注释） | 值 | 语义 |
|---|---|---|---|
| 262000 | T_ARCH | 0 | 行 id：0 = T1 `x86_64-unknown-linux-gnu`（Q7 矩阵） |
| 262001 | T_ELFCLASS | 2 | ELFCLASS64 |
| 262002 | T_ELFDATA | 1 | ELFDATA2LSB |
| 262003 | T_ET | 2 | ET_EXEC |
| 262004 | T_MACHINE | 62 | EM_X86_64 |
| 262005 | T_SYSC_READ | 0 | Linux x86_64 |
| 262006 | T_SYSC_WRITE | 1 | Linux x86_64 |
| 262007 | T_SYSC_OPENAT | 257 | Linux x86_64 |
| 262008 | T_SYSC_CLOSE | 3 | Linux x86_64 |
| 262009 | T_SYSC_EXIT | 60 | Linux x86_64 |
| 262010 | T_BASE | 4194424 | image base（code vaddr 起点 0x400078） |
| 262011 | T_PAGE | 4096 | PT_LOAD p_align |
| 262012 | T_HEAPBSS | 1048576 | runtime BSS heap 预算（1 MiB） |
| 262013 | T_ATFDCWD | 4294967196 | AT_FDCWD（−100）的 u32 装载形态 |
| 262014 | T_OP_SYSNR | 184 | `mov eax, imm32` 指令字节（syscall 号装载） |
| 262015 | T_OP_SYSCALL_0 | 15 | `syscall` 指令字节 1 |
| 262016 | T_OP_SYSCALL_1 | 5 | `syscall` 指令字节 2 |

**选址教训（首次选址 `post[17050]` 被 QEMU 拒收）**：17xxx 段实际处于**名字字节池**
（`post[12000]…`，M1d-0d 起约 166 KiB）的覆盖范围——24 个小语料名字量 <5KB 碰不到，
故产物 diff 全等；而 names_stage 自身标识符 ≈5KB 正好覆盖 17050 区，自编译场景下
`post[17051..17054]` 被名字池字节覆写，ELF 头变成 `03 c5 01 / e_machine=0x09ca`，
guest 内 `Exec format error`。**教训两条**：①post 槽位选址必须避开一切**无守卫**的
可变表（名字池无容量守卫，fd 之前全段皆不安全）；②产物 diff 语料必须包含**大程序**
（自编译这一量级）——最终选址 `262000` 位于 sast 硬守卫上界（141024 + 20000×6 − 1
= 261023）与 ctxi（266336）之间的可证死区，验证链含自编译产物 ELF 头检查。

**无全局变量问题的解法**：B-LS 无全局可变状态，但 `ps = slice(post, 0, 360000)` 是
post 的**全量视图**——全部发射点（emit_expr 家族的 `post` 参数、emit_stmt 家族的
`ps` 参数、main 内联段）都能直接索引 262xxx 槽，**零签名改动、零新增函数**。

### 2.2 接线点（3 模块 11 处发射）

| 模块 | 位置 | 原硬编码 | 现 |
|---|---|---|---|
| 90-main | ELF ident | `o[4]=2; o[5]=1;` | `o[4]=post[262001]; o[5]=post[262002];` |
| 90-main | ELF type/machine | `put16(o,16,2); put16(o,18,62);` | `post[262003]/[262004]` |
| 90-main | p_align | `put64(o,112,4096)` | `post[262011]` |
| 90-main | code_vaddr | `let code_vaddr = 4194424;` | `post[262010]` |
| 90-main | total（BSS heap） | `... + 1048576` | `... + post[262012]` |
| 90-main | entry stub 尾部 exit | `emit1(184);emit4(60); emit1(15);emit1(5);` | `post[262014]/[262009]/[262015]/[262016]` |
| 85-emit-stmts | ensures 失败路径（exit 74，emit_stmt_span） | 同形态 | `ps[262014]/[262009]/[262015]/[262016]` |
| 85-emit-stmts | requires 失败路径（exit 73，emit_body） | 同形态 | 同上（回归记录见 §3.1：首版误为 74，QEMU 抓回后恢复 .swp 基线） |
| 85-emit-stmts | `write(Str)` 语句（mov eax,1 + syscall 对） | 同形态 | `ps[262014]/[262006]/[262015]/[262016]` |
| 85-emit-stmts | `write("字面量")` 语句 | 同形态 | 同上 |
| 70-emit-expr | `emit_expr_io`：openat 号 + AT_FDCWD + read/write 号 + close 号 + 3 个 syscall 对 | 257/4294967196/0+rkind/3 | `post[...]`（read 号 `post[262005]+rkind`） |

**识别陷阱（已避）**：`80-scan-stmts.ls:157` 与 `85-emit-stmts.ls:61` 的 `257` 是
**AST 元数据表基址**，不是 syscall 号——仅改 `emit_expr_io` 内与 `T_OP_SYSNR`
（184/`mov eax`）装载配对的 imm32。

### 2.3 指令层裁定（2026-11-28 用户裁定"指令层一并抽象"的落实边界）

syscall ABI 是**序列级**目标相关（号装载指令 + syscall 指令形态），本项全表驱动。
寄存器编码 / MODRM / 数据传送指令是**指令选择级**目标相关（数百个 emit 点，
System V 参数装载遍布 emit_expr/emit_stmts），在无第二目标的 v1 参数化属投机性
抽象：真正的 ARM64 需要 ISA 描述 + 指令选择器 + 寄存器分配（见 §5），不是表替换
能覆盖的。此边界按 SDD-Plus 诚实降级纪律在此**显式登记**，不以"指令层已抽象"
对外表述。

## 3. 验证

### 3.1 产物 diff（零行为变化机器证明）

**对照**：改动前后两版 `names_stage`（seed 解释执行）对同一批 25 语料的产物
逐字节比较——覆盖全部表驱动路径（write 字面量/Str、`?` 失败、**契约 requires/ensures
两条失败路径**、ELF 布局、openat/read/write/close、offset 族、`?` 传播）：

```text
CORPUS = hello str calc funcs arrays enums structs slices slice_params ops argv dynpath
         stage1_io stage1_str_io high_offset big_offset logic_ops divmod
         result_option result_err gen_enum gen_slice_cmp slice_concat_cap
         contract_ensures contract_requires
$ .temp/s3diff/mk.sh old   # 旧编译器 = git show HEAD:bootstrap/src/names_stage.ls
$ .temp/s3diff/mk.sh new
$ sha256 逐对比较：ALL 25 PRODUCTS BYTE-IDENTICAL (old == new)
```

**回归记录（本轮最重要的过程事实）**：首版 24 语料 diff 通过后，QEMU 第 3 轮
（93 分钟）抓到 `contract_requires` 退出码 74≠73——编辑轮次中我把 requires 失败
路径的退出码误改（残留槽位修复时误判"两处都是 74"；.swp 基线为 632 行 ensures=74、
3107 行 requires=73），而 24 语料恰好不含 `contract_requires`，字节级本可抓住的回归
成了盲区。修复三件套：①恢复 73；②diff 语料补入两个契约测试（退出码立即数嵌入产物
字节，产物 diff 完全可检）；③mk.sh 改为双侧显式源（旧侧文件曾因 PowerShell `>`
UTF-16 重定向损坏而不可用，改 bash 字节流生成）。修正后 25 语料全等。

另加**自编译产物 ELF 头检查**（首轮选址撞击名字池后的回归项）：
`seed --run names_stage names_stage → new_self.elf` 必须
`7f 45 4c 46 02 01 01 / e_type=02 / e_machine=0x3e`（实测恢复；撞名时为
`03 c5 01 / 0x09ca`）。

这是 [`S3-1-desseed.md`](S3-1-desseed.md) §5 登记的 DDC 差分思路的**首次应用**：
diff 比 QEMU 行为断言更快更强（直接证明 emit 字节未变）；但本轮也证明了它的**两个盲区**
——小语料集盖不住名字池量级差异（需自编译项），缺特定语料则盖不住退出码立即数
（需契约对）——**语料构成本身是 diff 方法的一部分**。

### 3.2 负例诊断路径（reject 不产 ELF，产物 diff 覆盖不到）

6 个负例（bls_arity / bls_dup_fn / qmark_mismatch / cap_missing /
ref_escape_return / comptime_nonconst）全部 rc=4 且首行诊断与 R3.6 格式一致。

### 3.3 宿主 run-stage1（解释段）

两轮均 PASS（含 `stage2_a == stage2_b` 确定性复跑；compiled 段按宿主约定 SKIP）。

## 4. QEMU 全量结果（2026-11-28，第 4 轮，RESULT=PASS）

`QEMU_TIMEOUT=7200 bootstrap/ci/run-qemu.sh`：**RESULT=PASS**（guest 约 84 分钟）。关键行：

```text
selfhost: cold start - seed chain produced build/stage2_self
selfhost: main path - compiler = build/stage2_self (seed out of the build)
PASS interpreted stage1 determinism (stage2_a == stage2_b)
PASS compiled contract_requires -> exit 73        ← 回归修复的反向确认
PASS compiled contract_ensures     -> exit 74
PASS self-host determinism (stage1-names reproduces stage2_self)
PASS fixed point: stage2 == stage3
PASS S3-1 selfhost main path (second build.sh seed-free; stage2_self artifact OK)
703012394f7fceb6c4065fe20b423c55e49cb2dba4ff72cd0c9050a2eed8a027  build/stage2_self
703012394f7fceb6c4065fe20b423c55e49cb2dba4ff72cd0c9050a2eed8a027  build/stage3_self
```

**固定点指纹按预期漂移并完成迁移登记**：`6158f95f…0f7d`（R2.6-F/S3-1/S3-2 期）
→ **`70301239…a027`**（S3-3 后；源变化 ⇒ 编译器二进制变化，固定点仍逐位成立）。
历史清单见 [`spec/freeze-manifest.md`](../spec/freeze-manifest.md) 固定点行与 05 §4.2。

前 3 轮过程（均为验证面拓展而非最终失败）：第 1 轮定位首轮选址撞名字池（§2.1）；
第 2 轮因工具调用被中断而终止（非代码问题）；第 3 轮抓到 requires 退出码回归（§3.1）；
第 4 轮全绿收官。

## 5. 多目标剩余工作（ARM64/T2/T3 立项时的挂点清单）

| # | 挂点 | 说明 |
|---|---|---|
| 1 | 指令选择器 | 寄存器编码/MODRM/数据传送（System V 参数装载全线）；ARM64 需 ISA 描述层 |
| 2 | 入口约定 | argc/argv 来自 `[rsp]`/`[rsp+8]`（entry stub 字节序列整体）；ARM64 为 sp + 寄存器 |
| 3 | syscall 号装载形态 | ARM64 `mov x8, #imm`（多字节序列）；表槽 17064 需扩为变长模板 |
| 4 | syscall 指令形态 | ARM64 `svc #0`（4 字节）；17065/17066 两字节槽同理需扩 |
| 5 | AT_FDCWD/stdout fd | OS 层常量（Linux 稳定）；none-eabi 目标无 openat 路径 |
| 6 | syscall 接口本身 | T2/T3 (none-eabi) 无 Linux syscall——I/O 内置改 semihosting/UART 直驱 |
| 7 | ELF → flat binary | Cortex-M/RISC-V 裸机走固定加载地址镜像（05 §6.2）；ELF 头路径需目标分派 |
| 8 | trap/abort 路径 | exit code 71/73/74 语义不变，但发射序列随目标 |

> 挂点 1–4 是"数据表 → ISA 描述"的架构升级，届时按 [`spec/toolchain.md`](../spec/toolchain.md)
> Q7 矩阵新增行驱动；本项已把**不随目标漂移的部分**全部收口。

## 6. 结论

- Target 单一事实源落地：3 模块 11 处发射全部由 17 槽描述表驱动，
  零新增顶层函数（128/128 约束保持）、不动 EBNF 冻结面、不动 CLI 契约；
- 零行为变化由 24 语料产物逐字节 diff 机器证明（DDC 差分首次应用）；
- 固定点指纹按预期漂移，新值随本提交登记（05 §30.1 / freeze-manifest 记录行）。

> AI生成

