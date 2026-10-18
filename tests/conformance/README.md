# tests/conformance/ · 接受/拒绝语料

> 上位：S-1 执行计划 §5（内部文档，未随仓库发布）；诊断码见设计初稿 §6.4（内部文档）。

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

- `accept/`：空，等待 `dossiers/*/accept.ls` 提供第一批；
- `reject/`：空，等待 `dossiers/*/reject.ls` 拆分。

> 在检查器 spike 可用前，这些目录只放计划，不放「看起来能过」的伪语料。
