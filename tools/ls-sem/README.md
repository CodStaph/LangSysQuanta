# ls-sem · L-Sys 语义检查器骨架

> **状态**：`骨架`。第一版只实现 Σ/H/Aliases* 与 `bad()` 重放；**不解析 L-Sys 源码**。
> **上位**：[`semantics.md`](../../spec/semantics.md) §2、[`t4-proof.md`](../../spec/t4-proof.md) §3.5.3。

## 目标

新建 Rust 语义检查器，**不复用 checker-spike 架构**。最终替换 checker-spike 作为：

- R1–R8、`Σ=(Γ,Λ,M,H)`、`Aliases*`/`Consumed*`/`ConsumeResult`；
- Q9 初始化、Q2 模块 cap、Q4 `trusted.lock`/boundary；
- conformance reject 零漏过。

## 当前能力

| 项 | 状态 |
|---|---|
| `Place`（root + field/index 路径，prefix/overlap） | 已实现 |
| `Σ=(Γ,Λ,M,H)` | 已实现 |
| `Holders` / `H*` / `Aliases*` / `Consumed*` | 已实现 |
| `store` 强更新（清后代/祖先旧足迹） | 已实现 |
| `move` / `drop` / `freeze` / `read_frozen` / `recover` | 已实现（骨架级） |
| `writable` / `is_moved` | 已实现（骨架级） |
| `bad()` 重放 | 已实现 |
| L-Sys parser / AST / 类型检查 | **未实现** |
| 区域约束求解器 | **未实现** |
| Q2/Q4/Q9 完整规则 | **未实现** |

## CLI

```bash
cargo run --manifest-path tools/ls-sem/Cargo.toml -- selftest
cargo run --manifest-path tools/ls-sem/Cargo.toml -- demo
cargo run --manifest-path tools/ls-sem/Cargo.toml -- check <file.ls>
```

- `selftest`：Σ/H/Aliases* 自检；
- `demo`：重放 `bad()`，期望 `REJECT E-LS-UNIQ`，并打印 `(s,0)`；
- `check`：当前只检查文件可读，返回 2 并说明 parser 未实现；不会假装通过。

## 测试

```bash
cargo test --manifest-path tools/ls-sem/Cargo.toml
```

覆盖：

- `bad()` 被拒且包含 `(s,b)`；
- 只有唯一 holder 被消费时 `recover` 成功；
- `move` 转移 `H` 并标记 root moved；
- `Consumed*` 按出现位置报告；
- 根强更新清空旧足迹。

## 下一步

1. 最小 parser：canonical EBNF 子集（`let/freeze/recover/存储/struct 字段`）；
2. AST → `Σ` 的 R1/R3/R4/R5 规则；
3. 区域约束求解器（并查集 + LCA + worklist）；
4. 接 `tests/conformance/reject`，目标零漏过；
5. 再迁移 Q2/Q4/Q9 与 checker-spike 的档案检查。
