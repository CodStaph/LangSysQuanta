# tests/gs1/ · G-S1/S2 验证资产

> **上位**：[`spec/gs1-bench.md`](../../spec/gs1-bench.md)（三层证据链协议，任务号 GS1-0）。
> **工具**：[`tools/unsafe-surface`](../../tools/unsafe-surface)（类目计数器）。

## 目录

| 目录 | 内容 |
|---|---|
| `rust-ref/` | Rust 对照参照实现（`LS-07` 对照臂 y 轴数据点） |

## rust-ref/slab.rs

slab 分配器档案（`dossiers/slab/accept.ls`）的 Rust 参照：三个审计原语
（build_free_list / `(*head).next` 读 / `(*f).next` 写）一比一对应，
其余逻辑留在安全 Rust。编译验证：

```bash
rustc --edition 2021 --crate-type lib tests/gs1/rust-ref/slab.rs -o <tmp>/slab.rs.rlib
```

度量结论（基线报告 `results/gs1-baseline-*.md` 承载）：**unsafe 原语
种类 3（deref-write / ptr-read / ptr-write 类），与 L-Sys 档案的
unsafe-surface 种类数（3：deref-write/ptr-cast/field-access-raw）同级**——
`LS-07` 首个数据点不劣于 Rust。

其余试金石（环形缓冲/无锁队列/中断/MMIO/调度器）的 Rust 参照随 S0″
交付补齐（D-GS1-3：阶段 0 仅 slab）。

## 维护规则

1. 参照实现只求**逻辑等价**（人审对照档案），不设机器等价断言——
   参照不是被测物；
2. 每件参照必须 `cargo check`/`rustc --crate-type lib` 可编译，入库前
   人工跑一次并把结果写进基线报告；
3. unsafe 块必须逐个标注对应的 L-Sys 审计原语（注释锚点）。

> AI生成
