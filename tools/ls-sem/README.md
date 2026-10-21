# ls-sem · L-Sys 语义检查器骨架

> **状态**：`受限 surface 前端 + R1–R8 子集`。实现 Σ/H/Aliases*、`bad()` 重放、Q2 模块 cap 验证、
> Q6 C ABI 标量映射、Q7 三目标矩阵；`Buffer[T]`/region/所有权、泛型多参数与约束、
> `val`/`ref`/effect/契约/`comptime`、`Result` 分配失败与 arena 预算/回收；
> 并新增 `borrow`/`freeze`/`spawn`/`shared`/`atom`/`Lock`/`Order` surface 与
> R2/R5/R6/R8。**不是完整 L-Sys 前端，也未接入 bootstrap stage1。**
> **上位**：[`semantics.md`](../../spec/semantics.md) §2、[`t4-proof.md`](../../spec/t4-proof.md) 的 M2 `recover` 小节。

## 目标

新建 Rust 语义检查器，**不复用 checker-spike 架构**。最终替换 checker-spike 作为：

- R1–R8、`Σ=(Γ,Λ,M,H)`、`Aliases*`/`Consumed*`/`ConsumeResult`；
- Q9 初始化、Q2 模块 cap、Q4 `trusted.lock`/boundary；
- conformance reject 零漏过。

## 当前能力

| 项 | 状态 |
|---|---|
| `Σ=(Γ,Λ,M,H)` | 已实现 |
| `RegionTree` 嵌套关系与 outlives/store 方向判断 | 已实现；已接入 surface parser/checker |
| 泛型 `Buffer<T>` 的容量/初始化长度/所属 region | 已实现；源码级 `Buffer.new`/`Buffer.try_new`/`push` 检查 |
| `Buffer<T>` 容量溢出拒绝 | 已实现（API 返回错误，不修改 buffer） |
| 源码级 region 块、逃逸与存入方向检查 | 已实现（受限子集；含 `release` 与聚合 LCA 传播） |
| 泛型多类型参数、trait 约束、嵌套统一/occurs check | 已实现（受限子集） |
| `val`/`ref` 模式、`eff(...)`、`requires`/`ensures`、`comptime` | 已实现（受限子集） |
| `Buffer.try_new`/`Result` 分配失败、arena 预算与 LIFO 回收 | 已实现（静态模拟） |
| Slice 运行时边界/生命周期检查 | 已实现（`runtime.rs`：handle + generation） |
| `Place`（root + field/index 路径，prefix/overlap） | 已实现 |
| `Σ=(Γ,Λ,M,H)` | 已实现 |
| `Holders` / `H*` / `Aliases*` / `Consumed*` | 已实现 |
| `store` 强更新（清后代/祖先旧足迹） | 已实现 |
| `move` / `drop` / `freeze` / `read_frozen` / `recover` | 已实现（骨架级） |
| `writable` / `is_moved` | 已实现（骨架级） |
| R2 borrow（作用域 + 写权限） | 已实现（`borrow [mut] p as r { ... }`） |
| R5 写权限（place 级 frozen/borrowed） | 已实现（`freeze p[i]` / 区域级不误伤兄弟 place） |
| R6 `atom` / `Guard` | 已实现（`shared[Atomic[T]]` + atomicOps；`Lock[T, rank]` + `rankOk`） |
| R8 跨域 | 已实现（`spawn`：`iso`/`atom`/区域安全的 `val`） |
| A-5 `Rgn*` 足迹 | 已实现（嵌套 `ref`/`val`/`box` 区域；store/return/跨域按足迹检查） |
| surface：`borrow`/`freeze`/`spawn`/`shared`/`atom`/`Lock`/`Order` | 已实现 |
| conformance 检查器门 | `python tools/conformance-run`（accept 6 / reject 9） |
| 最小不可满足核 + fix-it | 已实现（escape 的 `core (1 minimal)` + `witness`；fix-it 不含 `unsafe`） |
| `bad()` 重放 | 已实现 |
| Q2 模块 cap（词法/不继承/forbid/knobs/Mmio 范围） | 已实现（数据模型级） |
| Q6 C ABI 标量映射（char/long/位域拒绝） | 已实现（标量/签名骨架） |
| Q7 三目标矩阵与 target 校验 | 已实现（矩阵级） |
| L-Sys parser / AST / 类型检查 | **受限子集已实现**（无 module/match/trait impl/属性/unsafe/代码生成） |
| 区域约束求解器 | 仅词法 region 树 + 方向检查；并查集/LCA/worklist 求解器未实现 |
| Q4 trusted.lock / boundary 完整规则 | 未实现（checker-spike 中） |

## CLI

```bash
cargo run --manifest-path tools/ls-sem/Cargo.toml -- selftest
cargo run --manifest-path tools/ls-sem/Cargo.toml -- demo
cargo run --manifest-path tools/ls-sem/Cargo.toml -- targets
cargo run --manifest-path tools/ls-sem/Cargo.toml -- abi <triple> <ctype>
cargo run --manifest-path tools/ls-sem/Cargo.toml -- caps
cargo run --manifest-path tools/ls-sem/Cargo.toml -- check <file.ls> [--arena-budget N]
```

- `selftest`：Σ/runtime/Q2/Q6/Q7 自检；
- `demo`：重放 `bad()`，期望 `REJECT E-LS-UNIQ`；
- `targets`：打印 v0 三目标矩阵；
- `abi`：按 target 映射 C 标量（如 `char`/`long`），位域/`long double` 拒绝；
- `caps`：Q2 负例 demo（子模块不继承、forbid、knob 放宽）；
- `check`：解析并检查受限子集；诊断带 `file:line:col`，接受时打印 arena 统计并返回 0，拒绝返回 1；
  `--arena-budget` 默认 1 MiB。示例 fixture：`tests/fixtures/regions_generics_alloc.ls`；
  最小核样例：`tests/fixtures/unsat_core_escape.ls`。

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
- region 子项的值可存入子孙 region；反向存储及跨兄弟 region 被拒；
- `Buffer<T>` 固定容量与满载时无副作用；
- 源码级：region 逃逸/跨兄弟存储拒绝、外层值存入内层允许、未知 region 拒绝；
- 聚合 region 传播：struct 字段/Option 负载取 LCA，逃逸到函数外被拒；
- 聚合 Buffer 存储方向：内层 Holder 存外层 Buffer 拒绝，外层 Holder 存内层允许；
- `Buffer.release()` / `drop p` 消费与 use-after-release/drop 拒绝；`.len`/`.cap` 类型级读取；
- `Buffer.push` 的静态容量跟踪（超过容量报 `E-LS-BUFFER-CAP`）；
- `Buffer.new`/`try_new` 容量支持常量表达式并做静态 arena 预算检查；
- `drop`/`release` 对 arena 栈顶分配执行 LIFO 回收（非栈顶暂不回收）；
- `Buffer.slice` 传播 buffer region 并标记借用；活跃 slice 期间移动/释放 buffer 报 `E-LS-ALIAS`；
- 聚合 drop 按字段逆序回收 Buffer 分配，嵌套 struct/Option/Result 递归收集；
- 运行时 `RuntimeArena`：Slice 边界、越界读写、release/region release 后使用均返回错误；
- Slice 随聚合值做 region LCA 与逃逸/存储方向检查；
- `let` 初始化对非 Copy 值执行移动，后续使用报 `E-LS-MOVE`；
- 泛型：多参数 struct/fn、嵌套统一、缺失约束与具体类型不满足约束均拒绝；
- `val`/`ref` 逃逸/移动、未声明 effect、契约类型、`comptime` 运行时表达式拒绝；
- `Buffer.try_new` + `?` 通过；预算不足时 `try_new` 记录 rejection 而不产生编译错误；
- 兄弟 region 回收后可复用预算，嵌套 region 共享预算，函数退出回收。
- Q2：cap 不继承、forbid 向下封闭、knob 只能收紧、Mmio 范围包含；
- Q6：target-specific `char`/`long`、`long double`/位域拒绝；
- Q7：未知 triple/超出目标能力被拒。

## 下一步

1. 扩展 surface 子集：`match`、`freeze`/`recover`、数组/Slice 索引、模块与 `use`；
2. AST → `Σ` 的 R1–R8 规则接入（当前 surface checker 使用简化的所有权状态机）；
3. 区域约束求解器（并查集 + LCA + worklist），替换词法树 + 方向检查；
4. 接 `tests/conformance/reject`，目标零漏过；
5. 把 Q2/Q6/Q7 从数据模型接到 parser/AST 与 `ls.toml`；
6. 迁移 Q4 `trusted.lock`/boundary 与 checker-spike 的档案检查；
7. 将 surface 前端与 bootstrap `names_stage.ls` 打通，消除“两套前端”差距。
