# lean/ · L3（Lean 4）机械化状态

> **状态**：`L3 机械化完成（F0 核心，2026-10-20）`。
> **对应**：[`spec/t4-proof.md`](../spec/t4-proof.md) §3.12、[`spec/semantics.md`](../spec/semantics.md) §2。
> **工具链**：Lean 4.6.0（`.tools/lean/`，gitignored；CI 用 elan 安装）。

## 机器检查的模块（`bash lean/check.sh`）

按依赖顺序构建（权威顺序见 `lean/check.sh`）：`Term → StepEval → State → Effect → EvalConf → EffHPath → EffHCounterexample → EffHC → EvalEff → EffHMeasure → Adequacy → WTK → WTyH → WTyHCtx → WTyHStar → Progress → Block → Runtime → Env → Holders → Unified → TypedStep → Preservation → PreservationCounterexample → StepBridge → LetHandleCounterexample → WTPreservation → Coherent → WTPlugCounterexample → Path → T4a → T4aSafe`。

| 模块 | 内容 |
|---|---|
| `LSys/Term.lean` | 核心语法、求值上下文、`M=(w,r)`、`Step`、**L-Term**、**L-Term\***、`FINAL`/`UB` |
| `LSys/State.lean` | `Σ=(Γ,Λ,M,H)`、`Match(M1–M5)`、`ConsumeResult`、`Consumed*`、**L-Holder**、**L-Consume** |
| `LSys/Adequacy.lean` | `WT`、`Rgn*`/`T1a-mono`、S3/S4/S5/S8/S9/S10/S11/S12/S14 的 **L-Adequacy** 逆向引理 |
| `LSys/Progress.lean` | **L-Progress**（`progress_any`，以及 `WT` 参数化形式 `progress`）、**L-NoStuck**（`l_no_stuck_wt`） |
| `LSys/Block.lean` | **L-Block**：`Mlt` 良基 + 每步下降 ⇒ 到达 `FINAL`（`terminates`） |
| `LSys/T4a.lean` | **T4a**：`¬ UB ∧ 终止 ∧ 所有 F0 事件均为定义行为`（`t4a`） |
| `LSys/Runtime.lean` | 真实 heap/borrow-table/flight、I1–I4、`RStepCore`（read/write/alloc/freeze/recover/**drop**/**regionExit**）、**L4** `wf_preserved_core`、**T1** `t1_no_dangling`、**T3** `t3_recover_unique` |
| `LSys/Env.lean` | 变量环境、`let`/`move`/`borrow`、环境 holder、`WFE`；`wfe_letVar`/`wfe_moveVar`/`wfe_borrowVar` |
| `LSys/Holders.lean` | 动态 `H`（`Occ`/`HoldPos`）、动态 `ConsumeResult`；`consumeD_exact`、`recoverD_clears` |
| `LSys/TypedStep.lean` | premise-carrying `StepP` + `RedexOK`；`StepPStar`；`redexOK_of_WT`、`progressP`、`l_no_stuckP`、`terminatesP`（条件 `WTPreserved`） |
| `LSys/Preservation.lean` | **`Eff`**、**`MatchU`（域相等）**、**`MatchUS`（域包含）**、**`StepPM`**；`RStepE` 含 `refl`/`borrowPush`/`borrowPop`；`MatchU/MatchUS` 帧 push/pop、`MatchUS.letVar` |
| `LSys/WTPreservation.lean` | **`WTPreserved` 已证明**：`wt_of_plug`、`wt_plug_of`、`wt_preserved_step`、`wtPreserved`、`terminatesP_uncond`、`t4a_safeP_final` |
| `LSys/PreservationCounterexample.lean` | 旧合取式 `Preservation` 为假；`not_preservation_current`（StepPM 未耦合 Eff/RStepE） |
| `LSys/Coherent.lean` | **（legacy）逐规则耦合的 `Eff`/`StepPM`**：`Eff` 带 `WT` 前提；每个 `StepPM` 构造器同时给出 Step/RStepE/Eff/RedexOK/输入 MatchU/输出 MatchU；覆盖全部 redex 规则与 `sctx` 上下文规则；`Coherent.preservation` 已证明（无公理） |
| `LSys/WTPlugCounterexample.lean` | **`wt_plug_eff` 检查：假**；`not_wt_plug_eff`（`region`/`freeze` 反例） |
| `LSys/Unified.lean` | 统一 `ConfE`（heap+env+holders+btab+flight）、`WFU`（完整 `H ⇔ B`）、`ConsumeResultU`；`let/move/borrow` 的 `WFU` 保持与 `consumeU_wfu` | `consumeU_exact`、`consumeU_wfu`、`wfu_letVar/moveVar/borrowVar`、`t1_wfu_*`、`t3_consumeU_consumes` |
| `LSys/Path.lean` | `Path = List Nat`、`Prefix`/`Desc`/`Anc`/`Overlap`；`State.Place = Path` 已接入 |
| `LSys/T4aSafe.lean` | `Safe`/`SafeP`/`SafeU`/`RuntimeSafe`/`RecoverSafe`；`t4a_safe`/`t4a_safeP`/`t4a_safeP_wt`/`unified_safe` |
| `LSys/StepEval.lean` | prefix-aware `StepEval`（`opL`/`opR`/`letB`/`seqL`/…）；`StepEval.toStep`、`stepEval_decreases` |
| `LSys/Effect.lean` | 状态无关 `Eff`；`EffH`（结果 handle）；`EffStepEval`；`EffPre`/`EffPost`；`RegionSafe`；`eff_plug_decomp`、`eff_plug_compose`、`effStepEval_eff_compose`、`regionSafe_step` |
| `LSys/EffHPath.lean` | 独立 `EffHPre`/`EffHPost`/`EffHStepEval`；`effH_plug_decomp`、`effH_recoverH_step`、`effH_recoverB_step`（`EffHStepEval` 尚未接入任何定理） |
| `LSys/EvalConf.lean` | `EvalConf`（expr/env/heap/state）；`StepEvalC`（19 条 canonical redex + 全部 14 条 prefix-aware 上下文规则，无总关系 `base`）；`EffHStepEvalC`（redex + 上下文规则，携带结果 handle）；`StepEvalC.toStep`、`stepEvalC_decreases` |
| `LSys/EffHCounterexample.lean` | **`EffHStepEvalC`/`EffH` 固定输出组合为假**；`not_effHStepEvalC_eff_compose` |
| `LSys/EvalEff.lean` | 配置级 **handle-free** `EffStepEvalC`（与 `StepEvalC` 逐规则对应）；`StepEvalC.toEffStepEvalC`、`effStepEvalC_eff_compose`、`regionSafe_stepC` |
| `LSys/EffHMeasure.lean` | `EffHStepEvalC` → `StepEvalC`（stutter 或 canonical 步）；度量 | `EffHStepEvalC.toStepEvalC`、`step_decreases_or` |
| `LSys/EffHC.lean` | **配置相对、携带 handle** 的 `EffHC env heap`；`RegionSafeHC`；`freshBid` 确定性 | `effHStepEvalC_effHC_compose`、`EffHStepEvalC.env_heap`、`regionSafeHC_step`（无公理） |
| `LSys/WTK.lean` | 逐规则 continuation-passing `WTK`；`region` 检查 `RegionSafe`（定义/编译；preservation 未证；已被 `WTyH` 取代） |
| `LSys/WTyH.lean` | **handle-aware、状态线程化** `WTyH env heap e σ σ₁ A`：`write` 存储操作数 handle、`recover` 消费、`freeze/read` 用 `freshBid`、`region` 用 `RegionSafeHC`、副作用条件在触发状态检查 | `WTyH.toEffHC`、`WTyH.preserved`（无公理；`derefRaw` 除外） |
| `LSys/StepBridge.lean` | `ConfE` ↔ `EvalConf` **子环境**对齐 `MatchV`；`RStepE`（`let/borrow` 带新鲜性）保持对齐；**朴素 `match_step` 的反例** | `MatchV.letVar/moveVar/borrowVar/rstep`、`EffHStepEvalC.var_inv`、`not_match_step_naive`（无公理） |
| `LSys/LetHandle.lean` | **tagged 变量 place** `varPlace x = [0,x]`；`bindHolders`；handle 值 `let` 的静态更新 | `heapPlace_ne_varPlace`、`varPlace_inj`、`MatchUS.letVarWithHolders` |
| `LSys/PlaceWF.lean` | **可加性路径良构** `WFPlace`/`WFLam`/`WFHolds`/`WFGamma`；静态操作保持 | `WFLam.addBorrow`、`WFHolds.clearPlace/setHolders/removeOcc/consumeResult`、`WFLam.consumeResult` |
| `LSys/WTyHCtx.lean` | 同余上下文 `CtxCong`（`hole` + 14 个上下文，`opR` 带 `IsVal`；仅排除 `borrowB`） | `EffHC.plug_step_compose`、`RegionSafeHC.plug_preserved`、`WTyH.plug_preserved`（无公理） |
| `LSys/WTyHStar.lean` | `EffStepStar`（`EffHStepEvalC` 自反传递闭包）；多步与上下文多步 | `WTyH.preserved_star`、`EffStepStar.trans`、`WTyH.plug_star_preserved`（无公理） |
| `LSys/CoherentH.lean` | handle-aware、prefix-aware `StepPMH`（配置级步 + `MatchUS`/`MatchV`/`RStepE`）；后置类型由 `WTyH` 推导，无需 `hwt_out`；**旧 `StepPM` redex 规则已逐条迁移**；`StepPMHStar` 多步闭包 | `StepPMH.redex` 与全部 redex 构造、`wt/wt_ctx/wt_ctx_star`、`ofStepRefl`、`borrowEnter/borrowExit/abortBorrow`、`varV/moveV/readV`、`letV`、`StepPMHStar.toEffStepStar`、`WTyH.preserved_stepPMH_star`、`StepPMHStar.wt_ctx`（`letV` 为 `propext, Quot.sound`，其余无公理） |
| `LSys/EffHCK.lean` | **route A 的配置级步** `EffHStepEvalCK`：19 条 canonical redex + 14 条 prefix-aware 上下文规则，`letV`/`borrowEnter` 线程化 `env` 与 `Σ` | `heap_same`、`env_ext`、`gamma_same`（无公理） |
| `LSys/LamEff.lean` | **`Λ`-only 过近似** `LamEff`（21 条规则，`recover` 不裁剪）；`λ` 只按 `(place, mode, rgn)` 三元组比较（`lamTriples`/`LamSub`，bid 擦除）；`RegionSafeLam` | `LamSub.refl/trans`、`lamSub_consumeResult`、`noEscape_of_lamSub`、`LamEff.coarsen`、`LamEff.gamma_eq`、`LamEff.mono`（无公理） |
| `LSys/LamStep.lean` | **`Λ` 效果的步组合**：残差的 `LamEff` 可拉回步前表达式；上下文规则用 `LamEff.mono` 重放后续子表达式 | `LamEff.step_compose`、`regionSafeLam_step`（仅 `propext`） |
| `LSys/WTKH.lean` | **路线 A 的值依赖类型判定** `WTKH env heap e σ σ₁ A`：`let` 把值/持有者绑定带进 body（`∀ v`），`borrow` 用 `setEnv`+`addBorrow`；`region` 现用 env 无关的 `RegionSafeLam σ R e` | `WTKH.letE_inv`/`letV_inv`/`letE_ctx`/`borrow_inv`、`WTKH.env_ext`、`WTKH.vars_bound` |
| `LSys/WTKHPreservation.lean` | `WTKH` 的**保持**：`preserved_redex`（redex，含 `letV`/`borrowEnter`）+ `preserved`（全部 14 条上下文；续接项沿 `env_heap_trans` 搬运，`regionB` 用 `regionSafeLam_step`） | `WTKH.preserved_redex`（无公理）、`WTKH.preserved`（仅 `propext`） |

`#print axioms`：

- `step_decreases`：`propext`
- `wf_preserved_core`：`propext, Quot.sound`；`t1_no_dangling` 无公理；`t3_recover_unique` 仅 `propext`
- `progress_any` / `progress` / `l_no_stuck_wt` / `adequacy_*`：无公理或仅 `propext`
- `l_consume` / `terminates` / `t4a`：`propext`、`Quot.sound`（Lean 内核商公理）
- `not_effHStepEvalC_eff_compose` / `StepEvalC.toEffStepEvalC` / `effStepEvalC_eff_compose` / `regionSafe_stepC`：无公理
- `effHStepEvalC_effHC_compose` / `EffHStepEvalC.env_heap` / `EffHC.env_heap_congr` / `regionSafeHC_step`：无公理
- `WTyH.toEffHC` / `WTyH.preserved`：无公理（`derefRaw` 未覆盖）
- `MatchV.rstep` / `not_match_step_naive`：无公理
- `WTyH.env_heap_congr` / `WTyH.plug_preserved` / `EffHC.plug_step_compose` / `RegionSafeHC.plug_preserved`：无公理
- `WTyH.preserved_star` / `EffStepStar.trans` / `WTyH.plug_star_preserved`：无公理（多步，含 `borrowEnter` 序列）
- `EffHStepEvalCK.gamma_same` / `LamEff.gamma_eq` / `LamEff.mono` / `LamEff.coarsen`：无公理
- `WTKH.preserved_redex` / `WTKH.env_heap_trans` / `WTKH.heap_trans` / `WTKH.letE_ctx_ext`：无公理；`WTKH.preserved`：`propext`
- `LamEff.step_compose` / `regionSafeLam_step`：`propext`（`regionSafeLam_step` 是 3 行推论：`step_compose` + `noEscape_of_lamSub`）
- `StepPMH.wt` / `wt_ctx` / `wt_ctx_star` / `ofStepRefl` / `borrowEnter/borrowExit/abortBorrow` / `varV/moveV/readV` / `StepPMHStar.toEffStepStar` / `WTyH.preserved_stepPMH_star` / `StepPMHStar.wt_ctx`：无公理（无 `hwt_out`）
- `StepPMH.preservation` / `StepPMHStar.preservation` / `StepPMHStar.preservation_ctx`：无公理（活跃接口）
- `MatchU.borrowPush` / `MatchU.borrowPop` / `MatchU.toMatchUS` / `MatchUS.borrowPush/borrowPop`：无公理
- `MatchUS.letVar` / `StepPMH.letV`：`propext, Quot.sound`（`simp` 引入）
- `MatchUS.letVarWithHolders`：`propext, Quot.sound`；handle 值 `let` 的静态 `bindHolders` 更新可行
- `PlaceWF` 的保持引理：无公理（`WFLam.consumeResult` 仅 `propext`）
- `WTKH.letE_inv` / `letV_inv` / `letE_ctx` / `borrow_inv`：无公理
- `RedexK.toEffHStepEvalCK` / `WTKH.preserved_redex`：无公理
- `EnvExtends.setEnv/setEnv_self` / `EffHStepEvalCK.env_ext` / `WTKH.env_ext`：无公理
- `WTKH.vars_bound`：`propext, Quot.sound`（`simp` 引入）
- `EffHC.env_agree` / `RegionSafeHC.env_agree` / `RegionSafeHC.env_ext`：`propext`
- **没有 `sorryAx`**。

## 建模边界（必须如实记录）

1. **place 是不可区分的标识符**。`State.lean` 里 `Place = Nat`，`overlap` 为相等；
   字段/索引路径（`isPrefix`）保留定义但未进入 F0 核心检查。因此
   `Aliases*`/`Consumed*` 覆盖“同一 place 的出现”，不展开聚合字段路径。
2. **`Step` 在 F0 语法上是全的**：`op`/`recover`/`deref_raw` 有总 redex 规则
   （`opAny`/`recoverAny`/`derefAny`），`var` 与借用帧弹出也有规则。
   因此 `progress_any` 对所有非 `FINAL` 项成立，比论文的“良类型 ⇒ redex”更强；
   `progress` 仍按论文形式要求 `WT` 前提。静态前提与动态 redex 的对应由
   `Adequacy.lean` 单独给出。
3. **`WT` 是直接风格的受限判断**：`recover`/`region`/`ret` 没有同余规则，
   所以 `adequacy_*` 是真正的逆推；`alloc`/`call`/`spawn` 携带
   `CAP_ALLOC_OK`/`CAPS_OK` 前提（无公理）。
4. **T4a 仍是 F0 的相对定理**：`F0Event` 只包含 bounds/overflow/div-zero/
   eval-order/drop-use；UB-2/3/4/5/8/9/10/11/13/15 由 T1/T3/静态检查承担，
   未在 `F0Event` 中建模。
5. **统一模型已闭合运算 1–2**：`WFU` 已由 `letVar/moveVar/borrowVar` 保持，
   `ConsumeResultU` 也保持 `WFU`。**WT 已改为状态无关**：`WT : Sigma → Expr → Prop`，
   `region` 的 `NoEscape` 现在检查输入 `Σ`。`Preservation.lean` 已定义 `Eff`、`MatchU`、
   `StepPM` 与目标陈述 `Preservation`；**`WTPreserved` 已证明**（`WTPreservation.lean`，
   无公理），`terminatesP_uncond`/`t4a_safeP_final` 为无条件版本。
   旧合取式 `Preservation` 为假（`PreservationCounterexample.lean`）。已新增
   `Coherent.lean`：`Eff` 带 `WT` 前提，`StepPM` 改为逐规则耦合的归纳关系，每个构造器
   同时给出 `Step/RStepE/Eff/RedexOK/输入 MatchU/输出 MatchU`；`Coherent.preservation`
   已机器检查（无公理）。当前耦合规则覆盖 val/var/abort/op/freeze/recover/write/alloc/move/read/drop/
   region/ret/spawn/atomic/unsafe/deref/letV/seqV/callV/borrowEnter/abortCtx/ctx。
   `sctx` 把上下文的后置 `WT` 与 `MatchU` 作为该规则的耦合义务（`hwt_out`/`hm'`）。
   **`EffHStepEvalC`/`EffH` 的固定输出组合为假**（`EffHCounterexample.lean`，无公理）：
   `var x ⇒ val (valH b)` 的 `A = [b]` 来自环境，而 `EffH σ (var x) σ []` 无法给出该
   handle 集；因此不能用 `EffH` 逐规则重建上下文。配置级改用 handle-free 的
   `EffStepEvalC`（`EvalEff.lean`）：`effStepEvalC_eff_compose` 与
   `regionSafe_effStepEvalC` 已证明；它与 `StepEvalC` 的对应（`base` 依赖总关系 `Step`）
   仍未建立。
   **不能直接去掉 `hwt_out`**：`WTPlugCounterexample.lean` 已机器检查 `wt_plug_eff` 为假
   （`region R { freeze p }`：`freeze` 向 `R` 添加 borrow，后置 `NoEscape` 失败）。
   要移除它，必须改成 effect-aware `WT`（或加入 `RegionSafe`），并让 `RStepE` 与 `Eff` 逐规则对应。
   已建立 `Effect.lean`：`Eff`/`RegionSafe`/`EffPre`/`EffPost` 已参数化为
   `Ctx → Expr → Sigma → Sigma`；`eff_plug_decomp` 与 `eff_plug_compose` 均证明，
   `CtxSafe` 与 `regionSafe_to_ctxSafe` 已证明。`regionSafe_ctx`/`regionSafe_step`
   仍待证。**阻塞点**：`EffStep.ctx` 直接使用子步效果，忽略上下文前缀；而 `Term.Step.ctx`
   是总关系（不要求求值序）。已新增 `StepEval` 作为 prefix-aware 执行关系
   （`opR`/`letB`/`seqL`/`callB` 等按位置拆分），并证明 `StepEval.toStep` /
   `stepEval_decreases`。`Effect.lean` 的旧 `EffStep` 已替换为 `EffStepEval`，
   每个构造器同时携带 `e'` 与 `σ'`，与 `StepEval` 规则一一对应。下一步是
   `EffStepCtx` 与 `effStepCtx_decomp`。**注意**：已修正 `Eff`/`EffStepEval` 的一致性：新增 `Eff.recoverAny`；`borrowEnter` 统一使用
   bid 0；`EffStepEval` 移除 prefix-unaware 的 `abortCtx`。`Eff` 已改为可组合的 recover 规则：`recoverCtx`/`recoverCtxConsume` 取代
   `recover`/`recoverAny`；`EffPre`/`EffPost` 的 `recoverB` 改为递归规则；
   `eff_plug_decomp`/`eff_plug_compose` 已重证。`effStepEval_eff_compose` 已证明；`EffStepCtx`/`effStepCtx_decomp` 已定义并证明；
   `effPost_congr`、`regionSafe_ctx_hole`、`regionSafe_step`（hole-relative）已证明。
   下一步是把 `WT.region` 接入 `RegionSafe` 并去掉 `sctx.hwt_out`。`WT.region`
   尚未接入 `RegionSafe`，因为接入后 `WTPreservation.wt_plug_of` 需要先有
   `regionSafe_eff_step`（上下文 effect 保持）。**注意**：不带 `Step` 前提的
   `regionSafe_eff_step` 为假（`not_regionSafe_eff_step`：可把 `e'` 任意取成
   `freeze p`）。正确形式必须带 `Step` + 小步 effect（或 `RedexOK`）。
   `WT.recover` 现在是同余规则，不再在类型层检查 `RecoverOk`；该条件由运行时 T3 承担。
   T4b–T4e 仍未开始。
6. 不引 Mathlib；`propext` 与内核 `Quot.sound` 是仅有的非计算公理。

## 运行

```bash
# 本地：使用 .tools/lean 下的 4.6.0
bash lean/check.sh

# 或指定 Lean
LEAN=/path/to/lean bash lean/check.sh
```

CI：`.github/workflows/bootstrap.yml` 的 `lean-term` job 用 elan 安装 4.6.0
并跑同一脚本（现覆盖全部模块）。
