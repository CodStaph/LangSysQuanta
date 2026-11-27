# tools/ · 工具

| 工具 | 用途 | 状态 |
|---|---|---|
| `doc-lint` | 文档一致性（§ 引用 / H-LS / 诊断码 / ADR / 链接 / 围栏） | 可用 |
| `checker-spike/` | 最小检查器（档案 A/B/C + conformance 启发式） | 可用；W2 7/7 |
| `ls-sem/` | L-Sys 语义检查器（Σ/H/Aliases* + 受限 surface parser/checker） | 可用；支持 Buffer/region、泛型约束、val/ref/effect/契约、arena 预算 |
| `ebnf-parse` | EBNF v2.2 Earley 识别器 + `--gbnf` | 可用（tests/syntax） |
| `diag-extract` | 从 `00 §6.4` 生成/校验 `spec/diagnostics.md`（golden diff） | 可用 |
| `freeze-hash` | L1 冻结清单指纹（`spec/freeze-manifest.md` 的 golden diff） | 可用 |
| `check-docs.sh` | 本地文档门：`doc-lint` + `diag-extract` + `freeze-hash` | 可用 |
| `conformance-run` | `tests/conformance/{accept,reject}` 的 ls-sem 检查器门 | 可用 |
| `grammar-coverage` | L-Redex 分类表 vs core 语法（B3） | 可用 |
| `bench-gs5` | G-S5 测量 harness（语料阶梯/编辑脚本 E1–E5/计时指标，[`spec/gs5-bench.md`](../spec/gs5-bench.md)） | 可用（阶段 0：harness 自证；首测待 SP1） |
| `gs3-bench` | G-S3 修复成本微基准 harness（34 任务/修复循环/双求解器，[`spec/gs3-bench.md`](../spec/gs3-bench.md)） | 可用（阶段 0：stub 自证；真实模型 run 待授权） |

## doc-lint

```bash
python tools/doc-lint            # 只报错误，不因 warning 失败
python tools/doc-lint --strict   # warning 也失败（发版前用）
```

检查范围：根目录 `*.md`、`spec/**/*.md`、`dossiers/**/*.md`、`results/**/*.md`、
`tests/**/*.md`、`bootstrap/**/*.md`、`tools/**/*.md`。

`MEMORY.md` 与 `00–05` 是 local-only：它们可以作为**定义来源**（`00`/`02`），
但不作为 **usage 来源**——它们里面的未定义码不会让 `doc-lint` 失败。

规则：

- `00` 的 `§N`/`§N.M` 必须命中 `00` 的标题；其余文档优先同文件，其次全局标题表；
- `H-LS-*` 必须由 `00 §12` 定义，且至少被引用一次；
- `E-LS-*`/`W-LS-*` 必须由 `spec/diagnostics.md`（或 `spec/bls.md` 的 B-LS 扩展）定义；
- `ADR-N` 必须由 `02` 定义；`ADR-21…27` 为规划中（warning）；
- 本地链接必须存在（`../` 父项目链接跳过）；
- 代码围栏必须成对。

> 新增文档后先跑 `doc-lint`；它失败就不提交。

## diag-extract

`spec/diagnostics.md` 是发布版诊断码登记处，由本地设计稿 `00 §6.4` 抽取。

```bash
python tools/diag-extract --check   # golden diff（本地；00 缺席时 INFO 退出 0）
python tools/diag-extract --write   # 改 00 后重新生成（LF）
python tools/diag-extract           # 输出到 stdout
```

## grammar-coverage

检查 `spec/t4-proof.md t4-proof.md 的 L-Redex 分类表小节` 的 L-Redex 分类表是否**逐产生式**覆盖
`spec/semantics.md §1.2` 的 `e ::= …`：

```bash
python tools/grammar-coverage
# grammar-coverage: 21 production(s), 21 L-Redex row(s)
# PASS every core production has exactly one L-Redex row
```

它不证明 Progress，只防止分类表漏项。

## conformance-run

`04 §14.6` 的检查器门：`accept/` 必须 rc=0，`reject/` 必须返回首行 `// EXPECT:` 的码。

```bash
python tools/conformance-run
```

它先 `cargo build` ls-sem，再逐个文件跑 `ls-sem check`。Q4/Q9 的旧语料在
`tests/conformance/checker-spike/`，由 checker-spike 单独守。

## bench-gs5

G-S5（迭代速度）的可执行测量协议：四项裁定（p90 / CLI 含启动 / 10k-50k-200k 三档 /
VM 主测＋Actions 佐证）见 [`spec/gs5-bench.md`](../spec/gs5-bench.md) §2。

```bash
python tools/bench-gs5 --selftest      # 端到端自证：生成→EBNF 门→编辑→stub 管线→JSON 契约
python tools/bench-gs5 --gen --target-loc 10000 --dep-fanout 1   # 生成档位语料（确定性）
python tools/bench-gs5 --run --tier all --check-cmd "ls check {file}" --write
                                      # 阶段 1 首测：接入 ls-sem/ls check 后
```

阶段 0 的即期价值：三档语料同时是 SP1 parser 的规模负载；selftest 内置 EBNF 语法门
（生成语料与全部编辑产物必须被 `tools/ebnf-parse` 接受）。计时对象可配置
（`--check-cmd`，含 `{file}`/`{dir}` 占位），不依赖未实现的检查器。

## gs3-bench

G-S3（AI 可修复）修复成本微基准，协议见 [`spec/gs3-bench.md`](../spec/gs3-bench.md)
（四项裁定：轮预算 3 / Rust 臂阶段 0 / 17 reject 任务原样 / 全文件重写＋harness 自算 diff）。

```bash
python tools/gs3-bench --selftest                 # 自证：任务健康 + stub 双路径 + 指标 + JSON 契约
python tools/gs3-bench --run --solver stub        # 离线管线走通（relay=永不修好 / gold=孪生即修）
python tools/gs3-bench --run --solver api --write # 真实模型 run（需 GS3_SOLVER_URL/MODEL/KEY，所有者授权）
```

判定器三臂：`ls-sem check`（reject 10）/ `checker-spike`（spike reject 7）/
`rustc --crate-type lib`（`tests/gs3/rust-reject/` 手写 17）。任务集配对表与
维护规则见 [`tests/gs3/README.md`](../tests/gs3/README.md)。

## freeze-hash

`spec/freeze-manifest.md` 记录 L1 冻结候选的 SHA-256（`spec/*` + conformance 说明 + 工具）。

```bash
python tools/freeze-hash --check   # 指纹漂移则 rc=1
python tools/freeze-hash --write   # 评审后重新生成
python tools/freeze-hash           # 输出指纹块
```

它不依赖 local-only 的 `00–05`，所以本地和 CI 都会跑。

## 本地文档门

提交文档/规范改动前：

```bash
bash tools/check-docs.sh
```

它等价于 `doc-lint --strict` + `diag-extract --check` + `freeze-hash --check`。
CI 跑 `doc-lint` 和 `freeze-hash`；`diag-extract` 需要本地 `00`，在发布检出里会自动跳过。

> AI生成
