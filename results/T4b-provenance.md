# T4b · UB-8/9/10 · RTT v1 provenance / 对齐 / 野指针

> 状态：**A1–A6 访问检查与 UB-8/9/10 事件已机械化**（Lean 4.6.0，`lean/LSys/Provenance.lean`）；
> RTT v1 与 Tree Borrows 的包含关系（S5）仍未证。
> 日期：2026-10-22
> 上位：[`spec/ub.md`](../spec/ub.md) §2（RTT v1，Q5/D41 已关闭）、
> [`spec/semantics.md`](../spec/semantics.md) 的「RTT v1」小节与 T4 拆分表、`H-LS-4`。

## 目标与三条边界

1. **什么算 UB-8/9/10**（本文给可执行模型）：RTT v1 的 `Access(t, off, sz, rw)` 必须满足
   A1–A6（`spec/ub.md` §2.4）；不满足任一条 ⇒ UB-10；null/未知分配 ⇒ UB-8；
   `off` 未对齐 ⇒ UB-9。
2. **`unsafe` 契约是否成立**（不做）：`Witness` 是输入，不是定理；`H-LS-4` 仍 `Out-of-scope`。
3. **RTT v1 ⊆ Tree Borrows**（不做）：`spec/ub.md` §2.5 明确不声称等价；S5 仍开。

## 模型（`lean/LSys/Provenance.lean`）

| 层 | 内容 |
|---|---|
| 分配/标签树 | `AllocId`/`TagId`、`TagKind = uniq|mut|frozen|raw`、`TagState = act|res|froz|dis`、`Tag`（`id`/`parent`/`kind`/`state`）、`Alloc`（`size`/`align`/`tags`）、`Prov`（`AllocId ⇀ Alloc`，用关联表以便 `decide`） |
| 祖先关系 | `parentOf`、`reaches`（带 fuel 的父链上溯）、`anc` |
| 访问 | `Access { alloc, tag, off, sz, align, rw, witness }`（= `spec/ub.md` §2 的 `(a, off, tag)` + 对齐 + `Witness`） |
| 判定 | `alignOk`（A3）、`overSize`（A2，做成 `Bool` 以保持可计算）、`outsideConflict`（A5/A6：读=子树外有活的 `act uniq/mut`；写=子树外且非祖先链上有活的非 `raw`）、`checkTag'` → `Verdict`、`check`（null → 未知分配 → tag 树） |
| 事件 | `Verdict.ub`：`nullDeref`/`wildDeref` → **UB-8**，`misaligned` → **UB-9**，其余 → **UB-10**；`OutsideF0` 覆盖 |
| oracle | `check_ok_or_ub`（每访问要么 `ok`，要么产出 UB 码，**无公理**）、`verdict_ub_outside`（仅 `propext`） |
| 成功的检查 | `checkTag'_ok`：`ok` ⇒ A2–A6 成立（含 `overSize_false` 的 A2）；`checkTagged_ok`、`check_ok_lookup`（找到分配） |
| 指针运算 | `ptrAdd`（越界派生 ⇒ UB-10）、`ptrSub`（跨分配 ⇒ UB-10）、`intToRaw`（无 `Witness` ⇒ UB-10）、`recoverVerdict`（仍有活 `froz` 副本 ⇒ UB-10） |
| 核心桥接 | `ProvWF p c`（RTT 里的分配 id 都是核心 `Conf` 的活 cell）→ `check_ok_live`（通过检查的访问触碰活 cell） |

**为什么 tag 树不塞进 `Cell`/`RVal`**（相对 `MEMORY.md` 原计划的偏差，按 `spec/ub.md` §2.1 的理由）：
安全子集没有 `rawptr`，RTT tag 在编译期擦除、运行期零成本；把 `tag` 加进 `Cell`
会强制改动 `Unified`/`StepBridge`/`EffHCK`/`WTKH` 全链路，而 F0 语法根本没有 raw 解引用。
因此 tag 树独立成层，用 `ProvWF`/`check_ok_live` 与核心 `Conf` 对齐；
`RVal` 不需要 raw 变体（raw 指针只存在于 `F_unsafe`）。

## 覆盖 `spec/ub.md` 的 RTT oracle 表

| # | 程序骨架 | 模型定理 |
|---|---|---|
| RTT-1 | `base + len` 再解引用 | `rtt1_out_of_bounds`（`outOfBounds`） |
| RTT-2 | `raw(r)` 写后 `*r` | `rtt2_raw_write_ok`（写本身 OK，祖先豁免）+ `rtt2_after_write_disabled`（`*r` 时父 tag `dis` ⇒ UB-10） |
| RTT-3 | 写 `froz` | `rtt3_frozen_write`（`writeNotActive`） |
| RTT-4 | 整数→指针无 `Witness` | `rtt4_int_to_raw`（`noTag` ⇒ UB-10）+ `rtt4_int_to_raw_is_ub10`；野地址另见 `rtt4_wild_pointer`（UB-8） |
| RTT-5 | 借用结束后用子 tag | `rtt5_child_disabled` |
| RTT-6 | `recover` 仍有活 `val` 副本 | `rtt6_recover_with_live_val` |
| RTT-7 | raw 读、无冲突 | `rtt7_raw_read_ok` |
| RTT-8 | 子借用结束、父恢复 | `rtt8_parent_after_child_ok` |
| RTT-9 | `p - q` 跨分配 | `rtt9_ptr_sub_other`（UB-10）/ `rtt9_ptr_sub_same` |
| RTT-10 | 写 `res` | `rtt10_res_write` |

（对应 `spec/ub.md` 的「UB-10 的 oracle」表；`doc-lint` 不跨文档解析编号引用。）

附加：`witness_exempts_raw_conflict` / `witness_allows_raw_read`（`Witness` 豁免 A5/A6）、
`ub9_misaligned`（UB-9）、`ub8_null`（UB-8）、`rawConflict_implies_raw`（A5/A6 只对 `raw` tag 生效）。

## 公理

```text
check_ok_or_ub / rtt1..rtt10 / witness_* / ub8_null / ub9_misaligned
ptr_add_* / ptr_sub_* / int_to_raw_* / overSize_false / check_ok_lookup?  见下
check_ok_or_ub、全部 RTT-1..RTT-10、ub8_null、ub9_misaligned、ptr_sub_other、
int_to_raw_*、overSize_false：无公理
verdict_ub_outside、checkTag'_ok、checkTagged_ok、check_ok_lookup、
check_ok_live、rawConflict_implies_raw：propext
```

**没有 `sorryAx`，没有 `Classical.choice`。**

## 验证

```text
rm -f lean/LSys/*.olean && bash lean/check.sh
  → PASS lean: L3 + T4a foundation（51 模块，0 sorry，0 sorryAx）

grep -c Classical.choice .temp/lean-axioms.txt
  → 0

# 回归（本轮只加 Lean 模型 + 文档）
cargo test --quiet --manifest-path tools/ls-sem/Cargo.toml   → 64 passed
python tools/conformance-run                                 → SUMMARY PASS (accept=6, reject=10)
cd tools/checker-spike && cargo run --quiet -- ../../dossiers/slab → SUMMARY PASS

bash tools/check-docs.sh
  → doc-lint 54 files / 0 errors、diag 40、freeze 18、grammar 21/21
```

## 边界（不要当成已完成）

- **`Witness` 是输入**：`ac.witness = true` 时 A5/A6 被豁免，但「Witness 本身有效」
  是 `unsafe` 契约与审计的义务（`H-LS-4`），模型不证。
- **RTT v1 ⊆ TB 未证**（S5）：本模型是 `spec/ub.md` §2.5 的保守子集规则，不是与 TB 的等价性。
- **不是完整内存模型**：`size/align` 按分配记录，未建字段/字节级布局；`static`/`cell`/
  跨 FFI provenance/中断域不在范围内（`H-LS-5`/`H-LS-16`）。
- **未接入 `Cell`**：见上「为什么 tag 树不塞进 `Cell`/`RVal`」；`derefRaw` 的
  `WTKH` 规则（`§8.2 #8`）仍是 F0 之外的扩展点。

## 下一步

A 线只剩 **UB-5（T4e，线程/交错模型）**；`MEMORY.md` 建议等 T2 的线程域规则在
`ls-sem` 稳定后再开。
