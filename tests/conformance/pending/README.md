# tests/conformance/pending/ · 检查器未覆盖的语料

> 上位：[`../README.md`](../README.md)、[`spec/feature-coverage.md`](../../../spec/feature-coverage.md) §3/§6。

## 为什么单独放

`accept/` 与 `reject/` 的约定是「检查器现在就能判定」。下列用例的**规范、surface 与
EBNF 解析都已通过**（`python tests/syntax/run.py`），但 `checker-spike` / `ls-sem`
还没实现对应分析，现在跑会得到「漏过」而不是期望结果：

| 文件 | 缺的检查器能力 | 规则 |
|---|---|---|
| `accept-r2-borrow-then-write.ls`<br>`E-LS-ALIAS-r2-write-during-borrow.ls` | 借用作用域（S6/S7）与写权限（R5） | R2 / R5 |
| `accept-r5-two-regions-disjoint.ls`<br>`accept-r5-sibling-index-write.ls`<br>`E-LS-ALIAS-r5-nested-write-site.ls`<br>`E-LS-ALIAS-r5-frozen-place-write.ls` | 区域级 `Aliases*` / `H`；写检查用 `ρ_place` 而非写入点 | R5 |
| `accept-r6-atomic-fetch-add.ls`<br>`E-LS-RACE-r6-shared-plain-write.ls`<br>`E-LS-RACE-r6-shared-plain-read.ls` | `atomicOp(E)` / `lockCtx(E)` | R6 |
| `E-LS-IRQ-r6-lock-rank.ls` | `Guard` 活跃集 + `rankOk` | R6 rank |
| `accept-r8-iso-spawn.ls`<br>`accept-r8-val-static-spawn.ls`<br>`E-LS-RACE-r8-box-across-spawn.ls`<br>`E-LS-RACE-r8-ref-across-spawn.ls`<br>`E-LS-RACE-r8-val-local-region-spawn.ls` | 域模型与 `R8-transfer`（`thread ⊑ Rgn(v)`） | R8 |

> v2.2 之前这里还放过 surface 缺口（`lock` 关键字）。该缺口已关闭：
> 锁 surface 定为 `let g = m.lock()`（Guard 形式），`borrow` / `freeze` / `as`
> 已进 EBNF。

## 规则

1. `pending/*.ls` **不计入** `spec/feature-coverage.md` §6 的 L1 冻结清单的「可执行」项；
2. 首行仍然写 `// EXPECT: <code>`，迁移到 `reject/` 时不用改；
3. 迁移条件：`checker-spike` 或 `ls-sem` 实现对应规则，且该文件单独跑得到期望结果；
4. 迁移时必须：移动文件 → 跑一次 `accept/`/`reject/` 全绿 → 更新
   `../README.md` 的计数与 `spec/feature-coverage.md` §3 的状态；
5. 不允许把「能解析但语义未定」的用例放进 `accept/` 或 `reject/`。
