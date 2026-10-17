# 档案 A · 零拷贝包解析 + iovec + Cursor

> 权威描述：[`03-开发与工程实践评审.md`](../../03-开发与工程实践评审.md) §4.0。
> 对应决策：Q1（`val` 字段/游标能否返回）；ADR-19；`LS-P10`、`H-LS-28`。

## 目标

证明「无生命周期注解」下可以返回指向源缓冲的**视图**，且不复制：

- `Packet { payload: val[Slice] }` 可从 `parse` 返回；
- `Cursor { src: val[Slice], pos }` 可返回、可 `ref` 可变；
- `IoVec` 只搬视图头，不复制 payload。

## 文件

| 文件 | 内容 |
|---|---|
| `accept.ls` | 应被检查器接受：`view`、`Header`、`Packet`、`parse`、`Cursor`、`IoVec` |
| `reject.ls` | 应被拒绝：`ref` 字段返回、`Packet` 进 `static`、跨模块 `recover` |

## 验收清单

| # | 检查 | 判据 | 结果 | 证据 |
|---|---|---|---|---|
| A-1 | `parse` 被接受 | 返回 `Packet` 合法；ρ 由 `src` 推断 | 未评审 | — |
| A-2 | 零拷贝 | 生成 IR/汇编中 `parse` 无 `memcpy` | 未评审 | — |
| A-3 | `Cursor` 可返回 | `cursor()` 通过，`next_u8` 可写 | 未评审 | — |
| A-4 | `IoVec` 无复制 | `scatter` 只搬视图头 | 未评审 | — |
| A-5 | 生命周期负例 | 源区域结束后使用 `Packet` ⇒ 拒绝 | 未评审 | — |
| A-6 | `ref` 负例 | `BadCursor` 被拒（`E-LS-REGION-ESCAPE`） | 未评审 | — |
| A-7 | `recover` 边界 | 跨模块 `recover` 被拒（`E-LS-UNIQ`） | 未评审 | — |
| A-8 | unsafe 预算 | `view` 之外 0 个 unsafe 原语 | 未评审 | — |

## 失败后果

- A-2/A-3 失败：LS-P10 需修订，必须引入显式 `View[T]` 或生命周期参数 ⇒ `LS-25`，分支定位重估；
- A-6 漏过：视图规则 soundness 失败，停止 S1；
- A-8 超预算：记录原语并评审 ADR-19。
