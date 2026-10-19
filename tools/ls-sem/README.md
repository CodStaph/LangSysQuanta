# ls-sem · L-Sys 语义检查器骨架

> **状态**：`骨架 + Q2/Q6/Q7 第一版`。实现 Σ/H/Aliases*、`bad()` 重放、Q2 模块 cap 验证、
> Q6 C ABI 标量映射、Q7 三目标矩阵；**仍不解析 L-Sys 源码**。
> **上位**：[`semantics.md`](../../spec/semantics.md) §2、[`t4-proof.md`](../../spec/t4-proof.md) 的 M2 `recover` 小节。

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
| Q2 模块 cap（词法/不继承/forbid/knobs/Mmio 范围） | 已实现（数据模型级） |
| Q6 C ABI 标量映射（char/long/位域拒绝） | 已实现（标量/签名骨架） |
| Q7 三目标矩阵与 target 校验 | 已实现（矩阵级） |
| L-Sys parser / AST / 类型检查 | **未实现** |
| 区域约束求解器 | **未实现** |
| Q4 trusted.lock / boundary 完整规则 | 未实现（checker-spike 中） |

## CLI

```bash
cargo run --manifest-path tools/ls-sem/Cargo.toml -- selftest
cargo run --manifest-path tools/ls-sem/Cargo.toml -- demo
cargo run --manifest-path tools/ls-sem/Cargo.toml -- targets
cargo run --manifest-path tools/ls-sem/Cargo.toml -- abi <triple> <ctype>
cargo run --manifest-path tools/ls-sem/Cargo.toml -- caps
cargo run --manifest-path tools/ls-sem/Cargo.toml -- check <file.ls>
```

- `selftest`：Σ/Q2/Q6/Q7 自检；
- `demo`：重放 `bad()`，期望 `REJECT E-LS-UNIQ`；
- `targets`：打印 v0 三目标矩阵；
- `abi`：按 target 映射 C 标量（如 `char`/`long`），位域/`long double` 拒绝；
- `caps`：Q2 负例 demo（子模块不继承、forbid、knob 放宽）；
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
- 根强更新清空旧足迹；
- Q2：cap 不继承、forbid 向下封闭、knob 只能收紧、Mmio 范围包含；
- Q6：target-specific `char`/`long`、`long double`/位域拒绝；
- Q7：未知 triple/超出目标能力被拒。

## 下一步

1. 最小 parser：canonical EBNF 子集（`let/freeze/recover/存储/struct 字段`）；
2. AST → `Σ` 的 R1/R3/R4/R5 规则；
3. 区域约束求解器（并查集 + LCA + worklist）；
4. 接 `tests/conformance/reject`，目标零漏过；
5. 把 Q2/Q6/Q7 从数据模型接到 parser/AST 与 `ls.toml`；
6. 迁移 Q4 `trusted.lock`/boundary 与 checker-spike 的档案检查。
