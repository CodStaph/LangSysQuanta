# tests/conformance/pending/ · 尚未被任何检查器覆盖的语料

> 上位：[`../README.md`](../README.md)、[`spec/feature-coverage.md`](../../../spec/feature-coverage.md) §3/§6。

## 当前状态

**空。** 2026-10-19 的迁移把最后 15 条（R2/R5/R6/R8）迁到了
`../accept/` 与 `../reject/`，由 `tools/ls-sem` 判定。

Q4/Q9 的旧语料（属性、`unsafe`、未初始化 `let`、`freeze`/`recover` 早期用例）
不在 `ls-sem` 的 surface 内，放在 `../checker-spike/`，由 checker-spike 继续守。

## 什么情况下往这里放

只有在**规范已冻结、surface 已进 EBNF、但两个检查器都还没实现**时才放这里。
目录非空意味着 L1 的「可执行」条件未满足（`04 §14.6`）。

## 规则

1. `pending/*.ls` **不计入** `spec/feature-coverage.md` §6 的 L1 冻结清单；
2. 首行仍然写 `// EXPECT: <code>`，迁移时不用改；
3. 迁移条件：`tools/ls-sem`（或 checker-spike）实现对应规则，且该文件单独跑得到期望结果；
4. 迁移时必须：移动文件 → 跑 `python tools/conformance-run` →
   更新 `../README.md` 的计数与 `spec/feature-coverage.md` §3/§6 的状态；
5. 不允许把「能解析但语义未定」的用例放进 `accept/` 或 `reject/`。
