# tools/ · 工具

| 工具 | 用途 | 状态 |
|---|---|---|
| `doc-lint` | 文档一致性（§ 引用 / H-LS / 诊断码 / ADR / 链接 / 围栏） | 可用 |
| `checker-spike/` | 最小检查器（档案 A/B/C + conformance 启发式） | 可用；W2 7/7 |
| `ls-sem/` | L-Sys 语义检查器骨架（Σ/H/Aliases*，Rust 零依赖） | 骨架；parser/求解器待做 |
| `ebnf-parse` | EBNF v2.2 Earley 识别器 + `--gbnf` | 可用（tests/syntax） |
| `diag-extract` | 从 `00 §6.4` 生成/校验 `spec/diagnostics.md`（golden diff） | 可用 |
| `freeze-hash` | L1 冻结清单指纹（`spec/freeze-manifest.md` 的 golden diff） | 可用 |
| `check-docs.sh` | 本地文档门：`doc-lint` + `diag-extract` + `freeze-hash` | 可用 |

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
