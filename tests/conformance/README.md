# tests/conformance/ · 接受/拒绝语料

> 上位：[`04-S-1-执行计划.md`](../04-S-1-执行计划.md) §14.6；诊断码见 [`spec/diagnostics.md`](../../spec/diagnostics.md)。

## 布局

```text
accept/          ls-sem 应接受（R1–R8 安全子集）      —— 检查器门
reject/          ls-sem 应拒绝；每条首行 // EXPECT: <code>
checker-spike/   旧 Q4/Q9 语料（属性 / unsafe / 未初始化），由 checker-spike 判定
  accept/
  reject/
pending/         规范已冻结、两个检查器都尚未覆盖；当前为空
```

## 约定

1. `reject/*.ls` 的**第一行**必须是 `// EXPECT: E-LS-...`，否则检查器无法判定；
2. 一个文件只测一个错误，便于定位；
3. 文件名用 `code-<短名>.ls`，例如 `reject/E-LS-REGION-ESCAPE-return-ref.ls`；
4. 每个诊断码至少一个正例与一个负例（与 [`spec/diagnostics.md`](../../spec/diagnostics.md) 双向满射）；
5. 负例总数 S-1 期间 ≥ 20，S0′ 起随码位增长。

## 当前

- `accept/`：6 条，全部由 **ls-sem** 判定（rc=0）：
  `accept-r2-borrow-then-write.ls`、`accept-r5-two-regions-disjoint.ls`、
  `accept-r5-sibling-index-write.ls`、`accept-r6-atomic-fetch-add.ls`、
  `accept-r8-iso-spawn.ls`、`accept-r8-val-static-spawn.ls`；
- `reject/`：10 条，全部由 **ls-sem** 判定（含期望码）：
  `E-LS-ALIAS-r2-write-during-borrow.ls`、
  `E-LS-ALIAS-r5-nested-write-site.ls`、`E-LS-ALIAS-r5-frozen-place-write.ls`、
  `E-LS-IRQ-r6-lock-rank.ls`、`E-LS-RACE-r6-shared-plain-{read,write}.ls`、
  `E-LS-RACE-r8-{box,ref,val-local-region}-across-spawn.ls`、
  `E-LS-REGION-ESCAPE-a5-ref-field.ls`（A-5：`ref` 字段逃出区域）；
- `checker-spike/`：4 条 accept + 7 条 reject（Q4/Q9：`#[trusted]`、`#[boundary]`、
  `unsafe`、未初始化 `let`、`freeze`/`recover` 的早期语料）。ls-sem 的 surface
  尚未覆盖这些构造，因此由 checker-spike 继续守；
- `pending/`：**0 条**（2026-10-19 全部迁移）。

## 运行

```bash
# ls-sem 检查器门（accept/reject）
python tools/conformance-run

# checker-spike 的 Q4/Q9 语料
cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- tests/conformance/checker-spike/accept
cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- tests/conformance/checker-spike/reject
```

## 诊断优先级

同一程序可能触发多个码。语料约定「一个文件只测一个错误」，因此首个检查点按
[`spec/feature-coverage.md`](../../spec/feature-coverage.md) §4 的顺序判定；
其中 **R8 在 `spawn` 入口先于 R4**，否则 `E-LS-RACE-r8-ref-across-spawn.ls`
的期望码会有歧义。

> R1/R3/R4/R7 的可执行证据来自 `dossiers/{slab,views}` 与 checker-spike；
> R2/R5/R6/R8 由 `tools/ls-sem` 覆盖。两份语料都必须在 CI 里全绿。

## 迁移记录

| 日期 | 变更 |
|---|---|
| 2026-10-19 | R2/R5/R6/R8 的 15 条从 `pending/` 迁入 `accept/`/`reject/`（ls-sem 实现） |
| 2026-10-19 | Q4/Q9 的 11 条从 `accept/`/`reject/` 迁到 `checker-spike/`（ls-sem 未覆盖其 surface） |
