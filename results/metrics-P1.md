# 指标快照 · 2026-11-27

> 采集：`python tools/metrics`（SDD-Plus §10 最小指标集，全量自动采集，无人工填报）；
> 口径与局限随行标注；Gate 一次通过率需 CI Actions 运行记录，本工具暂不采集（v1）。

## 指标

| 指标 | 值 | 采集方法 |
|---|---|---|
| 语料执行率 | SUMMARY PASS (accept=6, reject=10, checker-spike=4+7, pending=0)（绿） | 实跑 `tools/conformance-run`，目录即注册 ⇒ 执行面＝注册面 |
| 登记码语料覆盖率 | 14/43（§1 有真实负例的行） | 解析 `spec/REQ-registry.md` §1 负例列文件存在性；分工见 feature-coverage §3 |
| 全量回归证据轮次 | 52（含确定性复跑；最近：R4.4-r4.5-reclaim.md、R4.6-free.md、R4.7-handle-quota.md） | 解析 `results/*.md` 的 RESULT=PASS 行；单人等价口径见 AGENTS.md 附表 |
| 缺陷归因分布 | A=1 B=0 C=0 | 解析 `results/*.md` `归因：` 字段（P1-3 模板引入，历史文件回填前为 0） |
| 指纹门重签发次数 | 51 | `git log --follow spec/freeze-manifest.md` 计数（评审/拦截事件代理量） |
| 当前固定点 | `6158f95f…0f7d` | `spec/freeze-manifest.md` 记录行 |

## 劣化看护（§10）

- 连续两个里程碑劣化的指标必须在下一次 Go/No-Go（`results/s1-review.md`）触发专项复盘；
- 语料执行率跌破 100% ＝ 注册完备性事故（§8.4 差集 ≠ 0），即时阻断。

> AI生成
