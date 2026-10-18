# tools/ · 工具

| 工具 | 用途 | 状态 |
|---|---|---|
| `doc-lint` | 文档一致性（§ 引用 / H-LS / 诊断码 / ADR / 链接 / 围栏） | 可用 |
| `checker-spike/` | 最小检查器（接受/拒绝档案） | W1 决定语言后创建 |

## doc-lint

```bash
python tools/doc-lint            # 只报错误，不因 warning 失败
python tools/doc-lint --strict   # warning 也失败（发版前用）
```

检查范围：根目录 `*.md`、`spec/**/*.md`、`dossiers/**/*.md`、`results/**/*.md`、`tests/**/*.md`。

规则：

- `00` 的 `§N`/`§N.M` 必须命中 `00` 的标题；其余文档优先同文件，其次全局标题表；
- `H-LS-*` 必须由 `00 §12` 定义，且至少被引用一次；
- `E-LS-*`/`W-LS-*` 必须由 `00 §6.4` 定义；
- `ADR-N` 必须由 `02` 定义；`ADR-21…27` 为规划中（warning）；
- 本地链接必须存在（`../` 父项目链接跳过）；
- 代码围栏必须成对。

> 新增文档后先跑 `doc-lint`；它失败就不提交。
