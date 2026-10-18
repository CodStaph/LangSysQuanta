# tests/conformance/ · 接受/拒绝语料

> 上位：[`04-S-1-执行计划.md`](../04-S-1-执行计划.md) §5；诊断码见 00 §6.4。

## 布局

```text
accept/  应被检查器接受；文件名 = 规则/模式 id
reject/  应被检查器拒绝；每条首行 // EXPECT: <code>
```

## 约定

1. `reject/*.ls` 的**第一行**必须是 `// EXPECT: E-LS-...`，否则检查器无法判定；
2. 一个文件只测一个错误，便于定位；
3. 文件名用 `code-<短名>.ls`，例如 `reject/E-LS-REGION-ESCAPE-return-ref.ls`；
4. 每个诊断码至少一个正例与一个负例（与 00 §6.4 双向满射）；
5. 负例总数 S-1 期间 ≥ 20，S0′ 起随码位增长。

## 当前

- `accept/`：4 条：
  `accept-init-first-assignment.ls`（Q9：首次赋值 = 初始化）、
  `accept-unsafe-termination.ls`（Q4：`#[trusted]` 安全包装）、
  `accept-unsafe-trusted-lock.ls` + `trusted.lock`（Q4：lock 条目覆盖）、
  `accept-boundary-effect-union.ls`（Q4：boundary 保留 `Unsafe`）；
- `reject/`：7 条：
  `E-LS-UNIQ-val-alias-field.ls`（`val` 进入聚合字段后未消费）、
  `E-LS-MOVE-use-after-move.ls`（`move` 后再次使用）、
  `E-LS-INIT-read-uninitialized.ls`（未初始化读取）、
  `E-LS-EFFECT-unsafe-wrapper-exposes-rawptr.ls`（直接 `rawptr`）、
  `E-LS-EFFECT-rawptr-in-public-field.ls`（struct 字段传递 `rawptr`）、
  `E-LS-EFFECT-stale-trusted-lock.ls`（lock 哈希失败关闭）、
  `E-LS-EFFECT-boundary-drops-unsafe.ls`（boundary 吞掉效果）。

运行方式（checker-spike 按首行 `// EXPECT:` 识别负例）：

```bash
cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- tests/conformance/accept
cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- tests/conformance/reject
```

> 只放能用当前检查器复现的语料；`E-LS-UNIQ` 这条同时对应
> `spec/t4-proof.md` 的 M2 静态重放（`Aliases*(Σ_c,x)={(s,b1)}`）。
> `E-LS-MOVE`/`E-LS-INIT` 目前是整变量级启发式（不跟踪字段），
> 不等于 `ls-sem` 的完整 `M`/初始化规则；
> Q4 已实现 `trusted.lock` 子集、按值 struct 字段的传递 `rawptr`、`#[boundary]` 效果并集；
> 最终 schema/advisory、跨 crate `Reach(P)`、mode 包装字段仍待 `ls-sem`。
