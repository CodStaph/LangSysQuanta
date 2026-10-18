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

**W1 完成**：

- `dossiers/views/accept.ls`：0 诊断，unsafe=0，zero_copy_source=true；
- `dossiers/views/reject.ls`：3/3 预期错误（`E-LS-REGION-ESCAPE` / `E-LS-STATIC` / `E-LS-UNIQ`）；
- Q1 关闭，见 `results/A-views.md`。

**W3 完成（档案 B，先于 W2 做）**：

- `dossiers/recursion/accept_rec.ls`、`accept_stack.ls`：0 诊断，unsafe=0；
- `dossiers/recursion/reject.ls`：3/3 预期错误（`E-LS-RECURSION` / `E-LS-STACK` / `E-LS-DIAL`）；
- 新增：属性参数解析（`recursion(bound = N)`、`bounds(off)`）、静态栈预算检查
  （保守 128 B/帧 vs 8 KiB）、目录按前缀扫描（`accept*.ls` / `reject*.ls`）；
- 结论：**条件通过**，见 `results/B-recursion.md`；Q3 待 B-6/B-7 证据齐备后关闭。

**W4 部分（M2 负例首批）**：

- 新增 `E-LS-MOVE`（显式 `move` / `box`/`iso` 整变量隐式 move 后再次使用）与
  `E-LS-INIT`（`let x: T;` 后、首次赋值前使用）的保守启发式；
- `tests/conformance/reject/` 首批 3 条：
  `E-LS-UNIQ-val-alias-field.ls`、`E-LS-MOVE-use-after-move.ls`、
  `E-LS-INIT-read-uninitialized.ls`，本地 `SUMMARY PASS`；
- `tests/conformance/accept/accept-init-first-assignment.ls`：Q9 首次赋值 = 初始化，0 诊断；
- 目录扫描现在同时接受 `reject*.ls` 与首行 `// EXPECT:` 的 conformance 文件；
- 局限：只跟踪整变量，不跟踪字段；`val` 视为可别名（不因 `let q = p` 报 MOVE）。

**W2 完成（档案 C / slab，2026-10-18）**：

- 解析模块 `#[cap(Unsafe)]` 属性；
- `dossiers/slab/reject.ls` 7/7 命中：
  `E-LS-PROV`（重复 `free`/`push`）、`E-LS-MOVE`（`Mmio` 复制）、
  `E-LS-LEAK`（`DmaToken` 经 `let _` 丢弃）、`E-LS-DIAL`、
  `E-LS-REGION-ESCAPE`（`Alloc[Region]` 字段）、`E-LS-STATIC`（`static mut`）、
  `E-LS-CAPCTX`（无 cap 的 unsafe 块）；
- CI 已移除 slab 的 `continue-on-error`，slab 现在是硬性 7/7。

**Q4 / effects.md §4.1（spike，2026-10-18）**：

- 新增 `E-LS-CAPCTX` 与 `E-LS-EFFECT` 检查；
- 条件 1：非 `unsafe fn`、参数/返回不含 `rawptr`；
- 条件 2：模块 `#[cap(Unsafe)]` 或显式 `Cap[Unsafe]`；
- 条件 3：`#[trusted]` 属性，或模块 cap 作为 audit 上下文近似；
- 正/负例：`accept-unsafe-termination.ls`、`E-LS-EFFECT-unsafe-wrapper-exposes-rawptr.ls`；
- 未读 `trusted.lock`，公开字段的传递 `rawptr` 未展开；完整化留 `ls-sem`；
- spike 只对带 `eff(...)` 的函数执行 Q4 判定；模块 `#[cap(Unsafe)]` 视为 unsafe API 上下文。

**下一步**：`ls-sem` 的 R1–R8/`H`/初始化/信任闭包；checker-spike 不再扩展架构。
