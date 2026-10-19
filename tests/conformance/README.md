# tests/conformance/ · 接受/拒绝语料

> 上位：[`04-S-1-执行计划.md`](../04-S-1-执行计划.md) §5；诊断码见 [`spec/diagnostics.md`](../../spec/diagnostics.md)。

## 布局

```text
accept/   应被检查器接受；文件名 = 规则/模式 id
reject/   应被检查器拒绝；每条首行 // EXPECT: <code>
pending/  规范已冻结、检查器尚未实现；不计入冻结清单（见 pending/README.md）
```

## 约定

1. `reject/*.ls` 的**第一行**必须是 `// EXPECT: E-LS-...`，否则检查器无法判定；
2. 一个文件只测一个错误，便于定位；
3. 文件名用 `code-<短名>.ls`，例如 `reject/E-LS-REGION-ESCAPE-return-ref.ls`；
4. 每个诊断码至少一个正例与一个负例（与 [`spec/diagnostics.md`](../../spec/diagnostics.md) 双向满射）；
5. 负例总数 S-1 期间 ≥ 20，S0′ 起随码位增长。

## 当前

- `accept/`：4 条（Q4/Q9，checker-spike 可复现）：
  `accept-init-first-assignment.ls`（Q9：首次赋值 = 初始化）、
  `accept-unsafe-termination.ls`（Q4：`#[trusted]` 安全包装）、
  `accept-unsafe-trusted-lock.ls` + `trusted.lock`（Q4：lock 条目覆盖）、
  `accept-boundary-effect-union.ls`（Q4：boundary 保留 `Unsafe`）；
- `reject/`：7 条（checker-spike 可复现）：
  `E-LS-UNIQ-val-alias-field.ls`（`val` 进入聚合字段后未消费）、
  `E-LS-MOVE-use-after-move.ls`（`move` 后再次使用）、
  `E-LS-INIT-read-uninitialized.ls`（未初始化读取）、
  `E-LS-EFFECT-unsafe-wrapper-exposes-rawptr.ls`（直接 `rawptr`）、
  `E-LS-EFFECT-rawptr-in-public-field.ls`（struct 字段传递 `rawptr`）、
  `E-LS-EFFECT-stale-trusted-lock.ls`（lock 哈希失败关闭）、
  `E-LS-EFFECT-boundary-drops-unsafe.ls`（boundary 吞掉效果）；
- `pending/`：15 条（R2/R5/R6/R8；EBNF 可解析，检查器未实现）：
  - R2：`accept-r2-borrow-then-write.ls` / `E-LS-ALIAS-r2-write-during-borrow.ls`
  - R5：`accept-r5-two-regions-disjoint.ls`、`accept-r5-sibling-index-write.ls` /
    `E-LS-ALIAS-r5-nested-write-site.ls`、`E-LS-ALIAS-r5-frozen-place-write.ls`
  - R6：`accept-r6-atomic-fetch-add.ls` /
    `E-LS-RACE-r6-shared-plain-write.ls`、`E-LS-RACE-r6-shared-plain-read.ls`、
    `E-LS-IRQ-r6-lock-rank.ls`
  - R8：`accept-r8-iso-spawn.ls`、`accept-r8-val-static-spawn.ls` /
    `E-LS-RACE-r8-box-across-spawn.ls`、`E-LS-RACE-r8-ref-across-spawn.ls`、
    `E-LS-RACE-r8-val-local-region-spawn.ls`

> **为什么在 `pending/`**：这些文件已通过 `tests/syntax`（EBNF v2.2）解析，
> 但 `checker-spike` 与 `ls-sem` 还没实现 R2/R5/R6/R8 的判定。
> 放进 `accept/`/`reject/` 会让 `checker-spike` 返回 rc=1（检查器门变红），
> 所以按本文件第 1 条约定放在 `pending/`。迁移条件见 [`pending/README.md`](pending/README.md)。

运行方式（checker-spike 按首行 `// EXPECT:` 识别负例）：

```bash
cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- tests/conformance/accept
cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- tests/conformance/reject
```

## 诊断优先级

同一程序可能触发多个码。语料约定「一个文件只测一个错误」，因此首个检查点按
[`spec/feature-coverage.md`](../../spec/feature-coverage.md) §4 的顺序判定；
其中 **R8 在 `spawn` 入口先于 R4**，否则 `pending/E-LS-RACE-r8-ref-across-spawn.ls`
的期望码会有歧义。

> 只放能用当前检查器复现的语料；`E-LS-UNIQ` 这条同时对应
> `spec/t4-proof.md` 的 M2 静态重放（`Aliases*(Σ_c,x)={(s,b1)}`）。
> `E-LS-MOVE`/`E-LS-INIT` 目前是整变量级启发式（不跟踪字段），
> 不等于 `ls-sem` 的完整 `M`/初始化规则；
> Q4 已实现 `trusted.lock` 子集、按值 struct 字段的传递 `rawptr`、`#[boundary]` 效果并集；
> 最终 schema/advisory、跨 crate `Reach(P)`、mode 包装字段仍待 `ls-sem`。
