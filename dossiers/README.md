# dossiers/ · 三份硬模式档案（S-1 交付物 L）

> 说明：[`03-开发与工程实践评审.md`](../03-开发与工程实践评审.md) §4 是权威描述；
> 本目录只放**可解析代码**与**验收清单**。
> **这些文件是 S-1 的准入条件，不是示例。**

## 索引

| 档案 | 目标 | unsafe 预算 | 关键判决 | 结果 |
|---|---|---:|---|---|
| [A · views](views/README.md) | 零拷贝包解析 + iovec + Cursor | ≤ 1（prelude `view`） | `val` 字段/游标能否返回 | [A-views](../results/A-views.md) |
| [B · recursion](recursion/README.md) | 设备树显式栈 + 有界递归 | 0 | 递归上界与静态栈 | [B-recursion](../results/B-recursion.md) |
| [C · slab](slab/README.md) | slab + 侵入式链表 + refcount/RCU + C 驱动 | ≤ 5（6–8 条件通过） | 模块 cap 能否压住 unsafe 面积 | [C-slab](../results/C-slab.md) |

## 评审流程

1. 先跑 `reject.ls` 的负例（必须全拒），再跑 `accept.ls`（必须全接受）；
2. 结果写入 `results/<id>.md`，绑定 commit + 命令 + 输出；
3. 作者 + 非作者双人复核；solo 时作者 + 外部评审；
4. 结论只有四种：`未评审 / 通过 / 条件通过 / 失败`。

## 目录约定

```text
dossiers/<id>/
  README.md      目标、清单、失败后果
  accept.ls      应被检查器接受
  reject.ls      应被检查器拒绝（每条首行 // EXPECT: <code>）
```

## 当前状态

| 档案 | 状态 | 证据 |
|---|---|---|
| A · views | **条件通过** | `results/A-views.md`；A-2/A-5 待后续阶段 |
| B · recursion | **通过** | `results/B-recursion.md`；B-6 按 `04 §8` 延后到 S1 |
| C · slab | **条件通过** | `results/C-slab.md`；checker-spike 7/7，C-5/C-6/C-7 未做 |

检查器在 `tools/checker-spike/`；CI 把 A/B/C 作为硬门禁（`.github/workflows/bootstrap.yml`）。
本表与 `results/` 的判定必须保持一致。
