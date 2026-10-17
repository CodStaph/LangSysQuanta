# checker-spike · 最小检查器（W1 起）

> 上位：[`04-S-1-执行计划.md`](../../04-S-1-执行计划.md) §5.1。
> 目标不是完整前端，而是**能证伪**三份档案。

## 决定（W0）

- 语言：**Rust**（与 00 §3.2 的编译器实现一致；Python 仅用于 `doc-lint`）。
- 依赖：优先零依赖；需要时只允许 `serde`/`clap` 级别的稳定库。
- 不做：代码生成、优化、`lsfmt`、LSP、包管理。

## CLI（计划）

```bash
cargo run -- dossiers/views      # 接受 accept.ls，拒绝 reject.ls
cargo run -- dossiers/recursion
cargo run -- dossiers/slab
cargo run -- tests/conformance   # 逐文件 EXPECT
```

输出：每个文件一行 `PASS|FAIL <path> <code>`，退出码非零表示有漏过。

## 里程碑

| 周 | 能力 | 验收 |
|---|---|---|
| W1 | 解析 `val/ref/box/iso`、区域约束占位 | 能对 `views/*.ls` 给出接受/拒绝 |
| W2 | 模块 `#[cap]`、`unsafe`、`defer` 签名 | 能对 `slab/*.ls` 给出接受/拒绝 |
| W3 | `#[recursion]`、`#[bounds]`、静态栈占位 | 能对 `recursion/*.ls` 给出接受/拒绝 |
| W4–W6 | 契约/效果/诊断码映射、负例套件 | `tests/conformance/reject` 零漏过 |

## 边界

- 只实现 00 §5 用到的语法子集；其余报 `E-LS-UNSUPPORTED`（不伪装支持）。
- 所有“暂时通过”的规则必须在 `results/` 登记，不得静默放过。
- spike 的代码不是最终编译器；冻结语义后重写，不复用其架构。

## 当前状态

未开始。W1 第一件事：把 `dossiers/views/accept.ls` 解析成 AST，并对 `reject.ls` 报出 3 个预期错误。
