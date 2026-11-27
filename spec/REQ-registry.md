# spec/REQ-registry.md · REQ 登记总表

> **上位**：[`SDD-Plus开发规范.md`](../SDD-Plus开发规范.md) §4.3（登记总表）；
> [`AGENTS.md`](../AGENTS.md) 核心原则 1（权威分层）。
> **校验**：`python tools/req-registry --check`（已挂 `tools/check-docs.sh`、pre-push 与 CI）。
> **性质**：追溯矩阵主键表——正向「REQ → AC → 语料 → 任务」，反向「提交 trailer → 任务 → REQ」。
>
> **编号纪律（SDD-Plus §4.2）**：
> 1. `REQ-N` 仅为映射索引主键，按分区段分配；**存量编号（E-LS/W-LS/UB/R/Q/ADR）零迁移、永不重排**；
> 2. 分区段：§1 AC·诊断码 `REQ-001..`（接 diagnostics/bls 码位序）；§2 UB 约束 `REQ-101..`；
>    §3 区域规则 `REQ-201..`；§4 决策队列 `REQ-301..`；§5 ADR 索引 `REQ-401..`；
> 3. 本表是**活跃索引**（状态列随里程碑更新），不纳入 `freeze-manifest` 冻结清单；
>    一致性由 `--check` 机器校验（ID 集合 vs 四源 + 引用文件存在性）；
> 4. §4/§5 来源（04/02）为 local-only 设计稿：CI 检出缺席时来源校验降级 INFO，ID 完整性仍校验。

---

## 1. AC·诊断码（`REQ-001..REQ-043`）

> 来源：`spec/diagnostics.md` §1（40 码）+ `spec/bls.md` §5.1（B-LS 专属 4 码）；
> `E-LS-REGION-ESCAPE` 双源登记（语言码 + B-LS 实现码）。
> 「语料未建」= 该码尚无负例语料（可执行性缺口登记，接入时补行）；
> 分工与 R1–R8 侧写见 `spec/feature-coverage.md` §3/§4。

| REQ | 来源 | 类型 | AC（诊断码） | 正例 | 负例 | 承接任务 | 状态 |
|---|---|---|---|---|---|---|---|
| REQ-001 | diagnostics.md §1＋bls.md §5.1 | AC·诊断码 | `E-LS-REGION-ESCAPE` | dossiers/views/accept.ls | tests/conformance/reject/E-LS-REGION-ESCAPE-a5-ref-field.ls、bootstrap/bls/tests/reject/ref_escape_return.ls | ls-sem R8/A5；bootstrap B5-8/B5-9 | 可执行 |
| REQ-002 | diagnostics.md §1 | AC·诊断码 | `E-LS-ALIAS` | tests/conformance/accept/accept-r2-borrow-then-write.ls、tests/conformance/accept/accept-r5-sibling-index-write.ls | tests/conformance/reject/ E-LS-ALIAS-*.ls 共 3（r2-write-during-borrow、r5-nested-write-site、r5-frozen-place-write） | ls-sem R2/R5（W1，2026-10-19） | 可执行 |
| REQ-003 | diagnostics.md §1 | AC·诊断码 | `E-LS-ESCAPE` | — | 语料未建 | — | spec-only |
| REQ-004 | diagnostics.md §1 | AC·诊断码 | `E-LS-RACE` | tests/conformance/accept/ E-LS 无警告正例共 3（r6-atomic-fetch-add、r8-iso-spawn、r8-val-static-spawn） | tests/conformance/reject/ E-LS-RACE-*.ls 共 5 | ls-sem R6/R8（W1） | 可执行 |
| REQ-005 | diagnostics.md §1 | AC·诊断码 | `E-LS-CAP` | bootstrap/bls/tests/effects.ls（Cap 令牌正例） | bootstrap/bls/tests/reject/cap_missing.ls、bootstrap/bls/tests/reject/cap_unknown.ls | bootstrap B5-10 | 可执行（B-LS） |
| REQ-006 | diagnostics.md §1 | AC·诊断码 | `E-LS-UNSAFE` | — | 语料未建（R7 由 spike 效果门承证） | checker-spike R7 子集 | spec-only |
| REQ-007 | diagnostics.md §1 | AC·诊断码 | `E-LS-INIT` | tests/conformance/checker-spike/accept/accept-init-first-assignment.ls | tests/conformance/checker-spike/reject/E-LS-INIT-read-uninitialized.ls | checker-spike Q9 | 可执行 |
| REQ-008 | diagnostics.md §1 | AC·诊断码 | `E-LS-MOVE` | dossiers/slab/accept.ls | tests/conformance/checker-spike/reject/E-LS-MOVE-use-after-move.ls | checker-spike R1；dossiers/slab | 可执行 |
| REQ-009 | diagnostics.md §1 | AC·诊断码 | `E-LS-UNIQ` | tests/conformance/checker-spike/accept/accept-unsafe-termination.ls | tests/conformance/checker-spike/reject/E-LS-UNIQ-val-alias-field.ls | checker-spike R3 | 可执行 |
| REQ-010 | diagnostics.md §1 | AC·诊断码 | `E-LS-DROP` | — | 语料未建 | — | spec-only |
| REQ-011 | diagnostics.md §1 | AC·诊断码 | `E-LS-EFFECT` | tests/conformance/checker-spike/accept/accept-unsafe-trusted-lock.ls、tests/conformance/checker-spike/accept/accept-boundary-effect-union.ls | tests/conformance/checker-spike/reject/ E-LS-EFFECT-* 共 4；bootstrap/bls/tests/reject/eff_call.ls、bootstrap/bls/tests/reject/eff_missing.ls、bootstrap/bls/tests/reject/eff_unknown.ls | checker-spike Q4；bootstrap B5-10 | 可执行 |
| REQ-012 | diagnostics.md §1 | AC·诊断码 | `E-LS-LAYOUT` | — | 语料未建 | — | spec-only |
| REQ-013 | diagnostics.md §1 | AC·诊断码 | `E-LS-ABI` | — | 语料未建 | — | spec-only |
| REQ-014 | diagnostics.md §1 | AC·诊断码 | `E-LS-BOUNDS` | — | 语料未建（UB-1 oracle 路径规划中） | — | spec-only |
| REQ-015 | diagnostics.md §1 | AC·诊断码 | `E-LS-OVERFLOW` | — | 语料未建（UB-6：语言定义 wrapping） | — | spec-only |
| REQ-016 | diagnostics.md §1 | AC·诊断码 | `E-LS-RECURSION` | — | 语料未建 | — | spec-only |
| REQ-017 | diagnostics.md §1 | AC·诊断码 | `E-LS-COMPTIME` | bootstrap/bls/tests/contracts.ls | bootstrap/bls/tests/reject/comptime_assert.ls、bootstrap/bls/tests/reject/comptime_nonconst.ls、bootstrap/bls/tests/reject/bls_comptime.ls | bootstrap B5-11 | 可执行（B-LS 基础形式） |
| REQ-018 | diagnostics.md §1 | AC·诊断码 | `E-LS-PROV` | — | 语料未建（RTT v1 模型已机械化） | lean/LSys/Provenance.lean（T4b） | spec-only＋模型机械化 |
| REQ-019 | diagnostics.md §1 | AC·诊断码 | `E-LS-IRQ` | — | tests/conformance/reject/E-LS-IRQ-r6-lock-rank.ls | ls-sem R6 | 可执行 |
| REQ-020 | diagnostics.md §1 | AC·诊断码 | `E-LS-MATCH` | — | 语料未建 | — | spec-only |
| REQ-021 | diagnostics.md §1 | AC·诊断码 | `E-LS-ARITY` | bootstrap/bls/tests/funcs.ls | bootstrap/bls/tests/reject/bls_arity.ls、bootstrap/bls/tests/reject/gen_struct_new_arity.ls | bootstrap B0；R2.6-B | 可执行（B-LS） |
| REQ-022 | diagnostics.md §1 | AC·诊断码 | `E-LS-DUP` | bootstrap/bls/tests/funcs.ls | bootstrap/bls/tests/reject/bls_dup_fn.ls、bootstrap/bls/tests/reject/bls_dup_impl.ls、bootstrap/bls/tests/reject/bls_region_dup.ls | bootstrap B0/B2 | 可执行（B-LS） |
| REQ-023 | diagnostics.md §1 | AC·诊断码 | `E-LS-BUFFER-CAP` | tools/ls-sem/tests/surface.rs（内嵌） | tools/ls-sem/tests/surface.rs | ls-sem | 可执行 |
| REQ-024 | diagnostics.md §1 | AC·诊断码 | `E-LS-MONO-SIZE` | — | 语料未建 | — | spec-only |
| REQ-025 | diagnostics.md §1 | AC·诊断码 | `E-LS-STATIC` | — | 语料未建 | — | spec-only |
| REQ-026 | diagnostics.md §1 | AC·诊断码 | `E-LS-ERROR-SIZE` | — | 语料未建 | — | spec-only |
| REQ-027 | diagnostics.md §1 | AC·诊断码 | `E-LS-TRUST` | — | 语料未建 | — | spec-only |
| REQ-028 | diagnostics.md §1 | AC·诊断码 | `E-LS-PROFILE` | — | 语料未建 | — | spec-only |
| REQ-029 | diagnostics.md §1 | AC·诊断码 | `E-LS-COHERENCE` | — | 语料未建 | — | spec-only |
| REQ-030 | diagnostics.md §1 | AC·诊断码 | `E-LS-LEAK` | — | 语料未建 | — | spec-only |
| REQ-031 | diagnostics.md §1 | AC·诊断码 | `E-LS-STACK` | — | 语料未建 | — | spec-only |
| REQ-032 | diagnostics.md §1 | AC·诊断码 | `E-LS-CAPCTX` | — | 语料未建 | — | spec-only |
| REQ-033 | diagnostics.md §1 | AC·诊断码 | `E-LS-ATTR` | — | 语料未建 | — | spec-only |
| REQ-034 | diagnostics.md §1 | AC·诊断码 | `E-LS-DIAL` | — | 语料未建 | — | spec-only |
| REQ-035 | diagnostics.md §1 | AC·诊断码 | `W-LS-STACK` | — | 语料未建（UB-13 模型已机械化） | lean/LSys/Stack.lean（T4d） | spec-only＋模型机械化 |
| REQ-036 | diagnostics.md §1 | AC·诊断码 | `W-LS-UNSAFE-DENSITY` | — | 语料未建 | — | spec-only |
| REQ-037 | diagnostics.md §1 | AC·诊断码 | `W-LS-NONDET` | — | 语料未建 | — | spec-only |
| REQ-038 | diagnostics.md §1 | AC·诊断码 | `W-LS-OVERFLOW` | — | 语料未建 | — | spec-only |
| REQ-039 | diagnostics.md §1 | AC·诊断码 | `W-LS-FIXIT-UNSAFE` | — | 语料未建 | — | spec-only |
| REQ-040 | diagnostics.md §1 | AC·诊断码 | `W-LS-WCET` | — | 语料未建 | — | spec-only |
| REQ-041 | bls.md §5.1 | AC·诊断码 | `E-LS-UNSUPPORTED` | bootstrap/bls/tests/（B-LS 子集正例族） | bootstrap/bls/tests/reject/bls_buffer.ls、bootstrap/bls/tests/reject/bls_comptime.ls 等 38 处 | bootstrap B1（R3.6 结构化推进中） | 可执行（B-LS） |
| REQ-042 | bls.md §5.1 | AC·诊断码 | `E-LS-MAIN` | bootstrap/bls/tests/hello.ls | bootstrap/bls/tests/reject/bls_main_params.ls、bootstrap/bls/tests/reject/bls_main_ret.ls | bootstrap B0 | 可执行（B-LS） |
| REQ-043 | bls.md §5.1 | AC·诊断码 | `E-LS-NO-IMPL` | bootstrap/bls/tests/gen_struct.ls | bootstrap/bls/tests/reject/bls_no_impl.ls、bootstrap/bls/tests/reject/trait_call_no_impl.ls、bootstrap/bls/tests/reject/impl_add_int.ls、bootstrap/bls/tests/reject/struct_add_no_impl.ls | bootstrap B7/R2.6-C/R2.6-E（R3.6 结构化） | 可执行（B-LS） |

---

## 2. UB 约束（`REQ-101..REQ-115`，来源 `spec/ub.md` §1）

> AC 列为防御诊断码（可多个或 `—`＝定义为行为/运行期 oracle）；
> 「机械化」= A 线 Lean 模型（`lean/check.sh` 门），成果见 `results/A-line-summary.md`。

| REQ | 来源 | 类型 | AC（诊断码） | 正例 | 负例 | 承接任务 | 状态 |
|---|---|---|---|---|---|---|---|
| REQ-101 | spec/ub.md §1 · UB-1 越界读/写 | UB 约束 | `E-LS-BOUNDS` | — | 语料未建（负例 bounds 规划见 spec/ub.md §1） | — | 登记（防线已定义） |
| REQ-102 | spec/ub.md §1 · UB-2 悬垂引用 | UB 约束 | `E-LS-ESCAPE`＋`E-LS-REGION-ESCAPE` | dossiers/views/accept.ls | dossiers/views/reject.ls | dossiers/views | 部分可执行（档案） |
| REQ-103 | spec/ub.md §1 · UB-3 double free / 重复 drop | UB 约束 | `E-LS-DROP` | — | 语料未建 | — | 登记 |
| REQ-104 | spec/ub.md §1 · UB-4 未初始化使用 | UB 约束 | `E-LS-INIT` | tests/conformance/checker-spike/accept/accept-init-first-assignment.ls | tests/conformance/checker-spike/reject/E-LS-INIT-read-uninitialized.ls | checker-spike Q9 | 可执行 |
| REQ-105 | spec/ub.md §1 · UB-5 数据竞争 | UB 约束 | `E-LS-RACE` | tests/conformance/accept/ 共 3（r8-iso-spawn、r8-val-static-spawn、r6-atomic-fetch-add） | tests/conformance/reject/ E-LS-RACE-* 共 5 | ls-sem R6/R8；lean/LSys/Threads.lean（T4e） | 可执行＋机械化 |
| REQ-106 | spec/ub.md §1 · UB-6 整数溢出 | UB 约束 | `E-LS-OVERFLOW`＋`W-LS-OVERFLOW` | — | 语言定义 wrapping（定义性行为） | — | 登记（定义性） |
| REQ-107 | spec/ub.md §1 · UB-7 除零/非法移位 | UB 约束 | — | — | 运行期 oracle：trap＝定义行为（abort） | — | 登记（定义性） |
| REQ-108 | spec/ub.md §1 · UB-8 null/野指针解引用 | UB 约束 | `E-LS-PROV` | — | RTT v1：null/未分配分配 id（A 线） | lean/LSys/Provenance.lean（T4b） | 机械化 |
| REQ-109 | spec/ub.md §1 · UB-9 未对齐访问 | UB 约束 | `E-LS-PROV` | — | RTT v1：misaligned 判定（A 线） | lean/LSys/Provenance.lean（T4b） | 机械化 |
| REQ-110 | spec/ub.md §1 · UB-10 provenance 违反 | UB 约束 | `E-LS-PROV` | — | RTT v1 A1–A6 访问检查（A 线；spec/ub.md §2） | lean/LSys/Provenance.lean（T4b） | 机械化 |
| REQ-111 | spec/ub.md §1 · UB-11 MMIO 非volatile | UB 约束 | — | — | 类型固定 volatile＋fence（A 线） | lean/LSys/Mmio.lean（T4b） | 机械化 |
| REQ-112 | spec/ub.md §1 · UB-12 未定义求值序 | UB 约束 | — | — | 规范求值序：从左到右先求值后调用 | — | 登记（定义性） |
| REQ-113 | spec/ub.md §1 · UB-13 栈溢出 | UB 约束 | `W-LS-STACK` | dossiers/recursion/accept_stack.ls 等 | dossiers/recursion/reject.ls | dossiers/recursion；lean/LSys/Stack.lean（T4d） | 部分可执行＋机械化 |
| REQ-114 | spec/ub.md §1 · UB-14 drop 期间使用已释放对象 | UB 约束 | `E-LS-DROP` | — | abort 语义（无 unwind） | — | 登记 |
| REQ-115 | spec/ub.md §1 · UB-15 跨 FFI unwind | UB 约束 | — | — | extern nounwind＋ABI gate（A 线） | lean/LSys/Ffi.lean（T4c） | 机械化 |

---

## 3. 区域规则 R1–R8（`REQ-201..REQ-208`，来源 `spec/feature-coverage.md` §3）

> 正/负例已按 2026-10-19 迁移后的**实际路径**登记（feature-coverage §3 表内 `pending/` 前缀为迁移前陈旧路径，以本表与磁盘为准）。

| REQ | 来源 | 类型 | AC（诊断码） | 正例 | 负例 | 承接任务 | 状态 |
|---|---|---|---|---|---|---|---|
| REQ-201 | spec/feature-coverage.md §3 · R1 `uniq`/move | 区域规则 | `E-LS-MOVE` | dossiers/slab/accept.ls | tests/conformance/checker-spike/reject/E-LS-MOVE-use-after-move.ls | dossiers/slab；checker-spike | 有 |
| REQ-202 | spec/feature-coverage.md §3 · R2 borrow | 区域规则 | `E-LS-ALIAS` | tests/conformance/accept/accept-r2-borrow-then-write.ls | tests/conformance/reject/E-LS-ALIAS-r2-write-during-borrow.ls | ls-sem（W1） | 可执行 |
| REQ-203 | spec/feature-coverage.md §3 · R3 freeze/recover | 区域规则 | `E-LS-UNIQ` | tests/conformance/checker-spike/accept/accept-unsafe-termination.ls | tests/conformance/checker-spike/reject/E-LS-UNIQ-val-alias-field.ls | checker-spike | 有 |
| REQ-204 | spec/feature-coverage.md §3 · R4 store/return | 区域规则 | `E-LS-REGION-ESCAPE` | dossiers/views/accept.ls | dossiers/views/reject.ls、tests/conformance/reject/E-LS-REGION-ESCAPE-a5-ref-field.ls | dossiers/views；ls-sem | 有 |
| REQ-205 | spec/feature-coverage.md §3 · R5 write permission | 区域规则 | `E-LS-ALIAS` | tests/conformance/accept/accept-r5-two-regions-disjoint.ls、tests/conformance/accept/accept-r5-sibling-index-write.ls | tests/conformance/reject/ E-LS-ALIAS-r5-*.ls 共 2（nested-write-site、frozen-place-write） | ls-sem（W1） | 可执行 |
| REQ-206 | spec/feature-coverage.md §3 · R6 `atom`/锁 | 区域规则 | `E-LS-RACE`＋`E-LS-IRQ` | tests/conformance/accept/accept-r6-atomic-fetch-add.ls | tests/conformance/reject/ E-LS-RACE-r6-shared-plain-* 共 2；tests/conformance/reject/E-LS-IRQ-r6-lock-rank.ls | ls-sem（W1） | 可执行 |
| REQ-207 | spec/feature-coverage.md §3 · R7 `raw`/`Unsafe` | 区域规则 | `E-LS-CAP`＋`E-LS-EFFECT` | tests/conformance/checker-spike/accept/accept-unsafe-trusted-lock.ls | tests/conformance/checker-spike/reject/ E-LS-EFFECT-* 共 4 | checker-spike（Q4） | 有（spike） |
| REQ-208 | spec/feature-coverage.md §3 · R8 cross-domain | 区域规则 | `E-LS-RACE` | tests/conformance/accept/accept-r8-iso-spawn.ls、tests/conformance/accept/accept-r8-val-static-spawn.ls | tests/conformance/reject/ E-LS-RACE-r8-*-across-spawn 共 3 | ls-sem（W1） | 可执行 |

---

## 4. 决策队列 Q1–Q11（`REQ-301..REQ-311`，来源 `04-S-1-执行计划.md` §3/§14.5）

> 04 为 local-only 设计稿：CI 检出缺席时来源校验降级 INFO；关态变更须同步 04 原表。

| REQ | 来源 | 类型 | AC（产物） | 正例 | 负例 | 承接任务 | 状态 |
|---|---|---|---|---|---|---|---|
| REQ-301 | 04 §3 · Q1 `val` 字段/Cursor 可返回性 | 决策 | spec/modes.md §视图 | — | — | 语言负责人（W1） | 已定（modes.md 冻结记 Q1） |
| REQ-302 | 04 §3 · Q2 模块 `#[cap]` 词法/嵌套 | 决策 | spec/cap-context.md | — | — | 系统工程师（W2） | 已定（cap-context 记 Q2） |
| REQ-303 | 04 §3 · Q3 `#[recursion(bound)]` 默认值 | 决策 | spec/baremetal.md | — | — | 系统工程师（W3） | 登记（baremetal 草稿在册） |
| REQ-304 | 04 §3 · Q4 `Unsafe` 安全包装终止 | 决策 | spec/effects.md §4 | — | — | 语言负责人（W4） | 已定（spike 已落地） |
| REQ-305 | 04 §3 · Q5 provenance 模型 | 决策 | spec/ub.md §2（D41） | — | — | 安全审计（已关闭） | 已关闭（D41 RTT v1，2026-10-18） |
| REQ-306 | 04 §3 · Q6 C ABI 类型映射 | 决策 | spec/baremetal.md | — | — | 工具链（W5） | 已定（C ABI v1） |
| REQ-307 | 04 §3 · Q7 target 矩阵 | 决策 | spec/toolchain.md | — | — | 工具链（W7） | 已定（三目标矩阵） |
| REQ-308 | 04 §14.5 · Q8 `val` 仿射 vs 可别名 | 决策 | ADR-31 | — | — | 语言负责人（W1） | 已定（ADR-31 方案 B） |
| REQ-309 | 04 §14.5 · Q9 未初始化 `let` 规则 | 决策 | spec/modes.md 补丁 | — | — | 语言负责人（W1） | 已定（首次赋值＝初始化） |
| REQ-310 | 04 §14.5 · Q10 尾表达式/分号策略 | 决策 | EBNF v2 | — | — | 语言负责人（W1） | 已定（EBNF v2.2 现行） |
| REQ-311 | 04 §14.5 · Q11 字符串转义语义 | 决策 | EBNF v2＋spec/semantics.md 注记 | — | — | 语言负责人（W2） | 已定（EBNF v2.x） |

---

## 5. ADR 索引（`REQ-401..REQ-431`，来源 `02-架构评审与ADR.md`）

> 02 为 local-only 设计稿：CI 检出缺席时来源校验降级 INFO；
> ADR-21..27 为预留规划号（`tools/doc-lint` 同口径），定义后状态转「已定义」。

| REQ | 来源 | 类型 | AC（产物） | 正例 | 负例 | 承接任务 | 状态 |
|---|---|---|---|---|---|---|---|
| REQ-401 | 02 ADR-1 · 安全子集闭包定义＋Trusted 集合 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-402 | 02 ADR-2 · TCB 清单（含加载器） | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-403 | 02 ADR-3 · 权限分层与仿射性 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-404 | 02 ADR-4 · cap 撤销：v0 不做 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-405 | 02 ADR-5 · 跨 profile 边界 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-406 | 02 ADR-6 · 镜像格式与加载协议 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-407 | 02 ADR-7 · 成本模型 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-408 | 02 ADR-8 · 分析模块化边界 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-409 | 02 ADR-9 · explore/seal 等价 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-410 | 02 ADR-10 · 能力授予粒度 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-411 | 02 ADR-11 · 工具协议版本化 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-412 | 02 ADR-12 · ABI/edition 协商 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-413 | 02 ADR-13 · 全局状态与内部可变性 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-414 | 02 ADR-14 · 运行时契约 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-415 | 02 ADR-15 · Trusted 治理 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-416 | 02 ADR-16 · 加载器密钥 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-417 | 02 ADR-17 · 跨 crate impl | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-418 | 02 ADR-18 · 模块级能力上下文 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-419 | 02 ADR-19 · 可返回视图与 Cursor | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-420 | 02 ADR-20 · 裸机属性与 asm | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-421 | 02 ADR-21 · （预留） | 架构决策 | spec 各卷 | — | — | 架构师 | 预留（planned） |
| REQ-422 | 02 ADR-22 · （预留） | 架构决策 | spec 各卷 | — | — | 架构师 | 预留（planned） |
| REQ-423 | 02 ADR-23 · （预留） | 架构决策 | spec 各卷 | — | — | 架构师 | 预留（planned） |
| REQ-424 | 02 ADR-24 · （预留） | 架构决策 | spec 各卷 | — | — | 架构师 | 预留（planned） |
| REQ-425 | 02 ADR-25 · （预留） | 架构决策 | spec 各卷 | — | — | 架构师 | 预留（planned） |
| REQ-426 | 02 ADR-26 · （预留） | 架构决策 | spec 各卷 | — | — | 架构师 | 预留（planned） |
| REQ-427 | 02 ADR-27 · （预留） | 架构决策 | spec 各卷 | — | — | 架构师 | 预留（planned） |
| REQ-428 | 02 ADR-28 · 自举时机 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-429 | 02 ADR-29 · 实现语言：Rust 参考＋C seed/B-LS | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-430 | 02 ADR-30 · 第一阶段整程序编译直 emit ELF | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |
| REQ-431 | 02 ADR-31 · `val` 别名策略 | 架构决策 | spec 各卷 | — | — | 架构师 | 已定义 |

---

## 6. 变更规则

1. 新增诊断码 ⇒ `spec/diagnostics.md`（或 `bls.md` §5.1）与本表 §1 **同批次**增行；
2. 新增里程碑承接既有 AC ⇒ 更新对应行的「承接任务」列（附提交号）；
3. 语料从「语料未建」转「可执行」⇒ 填真实路径并保留状态演化可读性（禁止抹历史）；
4. 本表修订遵循 AGENTS.md 文档纪律；状态列更新不触发冻结（本表不在 freeze-manifest 范围）。

> AI生成
