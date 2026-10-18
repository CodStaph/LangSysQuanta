# A · 零拷贝视图（dossiers/views）

状态：**条件通过**（Q1 已关闭；A-2/A-5 待后续阶段）
负责人：语言负责人（角色）
复核：checker-spike（W1）
commit：`173d1b6`
命令：`cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- dossiers/views`
证据：

```text
== dossiers/views/accept.ls ==
PASS dossiers/views/accept.ls diagnostics=0 unsafe=0 zero_copy_source=true
== dossiers/views/reject.ls ==
  OK       E-LS-REGION-ESCAPE
  OK       E-LS-STATIC
  OK       E-LS-UNIQ
PASS dossiers/views/reject.ls expected=3 actual=3
SUMMARY PASS
```

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| A-1 | `parse` 被接受 | **通过** | accept.ls diagnostics=0 |
| A-2 | `parse` 无 `memcpy` | **条件** | 源码级无 bulk-copy 调用；IR/汇编未验证 |
| A-3 | `Cursor` 可返回 | **通过** | accept.ls 接受 `cursor()` / `next_u8` |
| A-4 | `IoVec` 无复制 | **通过** | accept.ls 接受 `scatter`；源码级无 bulk-copy |
| A-5 | 源区域结束后使用被拒 | **待验证** | spike 尚未实现区域作用域分析 |
| A-6 | `BadCursor` 被拒 | **通过** | `E-LS-REGION-ESCAPE` |
| A-7 | 跨模块 `recover` 被拒 | **通过** | `E-LS-UNIQ`（未消费别名） |
| A-8 | unsafe ≤ 1 | **通过** | unsafe=0；`view` 为 prelude 原语 |

## 结论

- **Q1 关闭**：`val` 字段可从函数返回；含 `val` 字段的结构体是区域参数化的（ρ 由源推断）；
  `ref` 字段不可返回；`Cursor { src: val[Slice], pos }` 是可返回、可 `ref` 可变的推荐模式。
- `recover` 的「消费全部别名」规则在单函数内可检查；跨模块仍禁止。
- **未关闭项**：A-2 需要 codegen/IR 才能证明零 `memcpy`；A-5 需要区域作用域分析。
  两项均不阻塞 Q1，但阻塞「档案 A 完全通过」。

## 对设计的影响

- 维持 `LS-P10`（无生命周期注解）；视图通过 `val` 字段表达，不需要显式 `'a`。
- `spec/modes.md` 可以开始起草，先冻结 §3（R1–R8）与 §4（视图规则）。
- `E-LS-REGION-ESCAPE` 的 fix-it 应优先建议「改 `val` 字段 / 用 Cursor / 复制」，不得建议 `unsafe`。

## 后续动作

| 动作 | 阶段 | 负责人 |
|---|---|---|
| A-2：在 IR/汇编检查 `parse` 无 `memcpy` | S0′ | 工具链 |
| A-5：区域作用域负例（源区域结束后使用 `Packet`） | S1 / modes.md | 语言负责人 |
| 把 §4 视图规则并入 `spec/modes.md` | W1–W3 | 语言负责人 |
