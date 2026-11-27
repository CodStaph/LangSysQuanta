# tests/gs3/ · G-S3 修复成本微基准任务集

> **上位**：[`spec/gs3-bench.md`](../../spec/gs3-bench.md)（协议冻结件，四项裁定 D-GS3-1..4）。
> **工具**：[`tools/gs3-bench`](../../tools/gs3-bench)。
> **任务号**：`GS3-0`（S0′ 期工程先导，不入 06 里程碑表）。

## 目录

| 目录 | 内容 | 数量 |
|---|---|---|
| `rust-reject/` | Rust 对照臂手写任务（每文件首行 `// EXPECT-RUSTC: Exxxx` 自检元数据，题面前剥除） | 17 |

L-Sys 臂任务**不在本目录**：阶段 0 复用 conformance 现有语料（spec/gs3-bench.md §3）——
`tests/conformance/reject/`（10，ls-sem 判定）＋ `tests/conformance/checker-spike/reject/`
（7，checker-spike 判定）。

## 配对表（L-Sys ↔ Rust，按错误语义族）

错误码一律以 rustc 1.99 实测为准（`gs3-bench --selftest` 逐个机检，17/17 PASS）。

| L-Sys 任务 | L-Sys 码 | Rust 码（实测） | 配对语义 |
|---|---|---|---|
| E-LS-ALIAS-r2-write-during-borrow | E-LS-ALIAS | E0506 | owner 在存活借用下写 |
| E-LS-ALIAS-r5-frozen-place-write | E-LS-ALIAS | E0594 | 冻结/共享处的写 |
| E-LS-ALIAS-r5-nested-write-site | E-LS-ALIAS | E0506 | 嵌套块写（按 place 而非写点判定） |
| E-LS-IRQ-r6-lock-rank | E-LS-IRQ | E0277 | 锁序：Rust 无静态锁 rank，配对为 `!Send` 锁句柄跨线程（近邻） |
| E-LS-RACE-r6-shared-plain-read | E-LS-RACE | E0277 | 非线程安全共享句柄的读跨域 |
| E-LS-RACE-r6-shared-plain-write | E-LS-RACE | E0277 | `&Cell`（!Sync）写跨域 |
| E-LS-RACE-r8-box-across-spawn | E-LS-RACE | E0521 | region-local 值跨域（借用生命周期逃逸） |
| E-LS-RACE-r8-ref-across-spawn | E-LS-RACE | E0521 | 引用跨域 |
| E-LS-RACE-r8-val-local-region-spawn | E-LS-RACE | E0373 | 局部值借用进 spawn（'static 违反） |
| E-LS-REGION-ESCAPE-a5-ref-field | E-LS-REGION-ESCAPE | E0597 | 局部引用经聚合字段逃逸 |
| E-LS-EFFECT-boundary-drops-unsafe | E-LS-EFFECT | E0133 | 安全签名调 unsafe 被拒 |
| E-LS-EFFECT-rawptr-in-public-field | E-LS-EFFECT | E0277 | 公共字段裸指针致 !Send 跨线程 |
| E-LS-EFFECT-stale-trusted-lock | E-LS-EFFECT | E0277 | 有声称无证明（trait bound 缺失） |
| E-LS-EFFECT-unsafe-wrapper-exposes-rawptr | E-LS-EFFECT | E0133 | 裸指针解引用需 unsafe 域 |
| E-LS-INIT-read-uninitialized | E-LS-INIT | E0381 | 未初始化使用 |
| E-LS-MOVE-use-after-move | E-LS-MOVE | E0369 | 整量 move 后使用（rustc 报首个硬使用点） |
| E-LS-UNIQ-val-alias-field | E-LS-UNIQ | E0507 | 聚合字段共享引用不可移出 |

配对为**语义近邻**（spec/gs3-bench.md §3 缺口登记）：R6 锁 rank、RACE 族
`shared`/跨域规则无 Rust 编译期等价物，均以线程安全边界族近邻替代；
错误码分布（E0277×6 / E0506×2 / E0521×2 / E0133×2 / E0594/E0373/E0597/E0381/E0369/E0507 各 1）。

## 维护规则

1. 新增任务 ⇒ 同批 `python tools/gs3-bench --selftest` 全过（Rust 任务含
   rustc 实测断言；L-Sys 任务由 conformance-run 承担健康检查）；
2. `rust-reject/` 首行 `// EXPECT-RUSTC:` 是测试元数据，与 conformance 的
   `// EXPECT:` 同语义：判定器拒绝且输出含该码；
3. 文件名必须与配对的 L-Sys reject 任务同名（换扩展名），配对表同步更新。

> AI生成
