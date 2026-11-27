# spec/freeze-manifest.md · L1 冻结清单

> **状态**：`候选`（W0）。
> **作用**：记录 L1 规范冻结候选的**内容指纹**；规则改动必须重新生成并评审。
> **生成**：`python tools/freeze-hash --write`
> **校验**：`python tools/freeze-hash --check`（已接入 `tools/check-docs.sh` 与 CI）

## 1. 范围

L1 规范冻结候选 = 下列文件的内容。**不包含**实现（`bootstrap/`、`tools/ls-sem`），
也不包含 `00–05` 设计稿（local-only，不可复现）。

## 2. 指纹

<!-- freeze-hash:begin -->
```text
a781e19bb2e81571e6eee4275656dddeaa261887d1a1c56deac39a2330575788  spec/f0.md
1b05959b75df78424165a7e2d096753a8b8db3bef795f6ecb798245754e24b6d  spec/semantics.md
283f8f50164a004ec533042026a0240d93bd160a0d19e5874af41ee723673560  spec/modes.md
6a9024a1f392c1d0a3075501bb0b8f1a64310c6e37cd17ce1275a6047049925b  spec/effects.md
c6fa2c6d50438c13777564337d7f44c244a6ea0b032735e9f42138d52c03b358  spec/cap-context.md
49b548fe391b507b6d36700ea66d15d9580d089845edd0f9fcad0656efc27e94  spec/diagnostics.md
051b09ec1a1185c7fe4297bc0e436854041f6796848a5e21ae5abc9377fe468b  spec/feature-coverage.md
2ed09bbdfd1f649e4a9014e96eedb68d49046d6fe59e0e0dc937e469917a4d41  spec/elaboration.md
dcd0253770672ee6a2d11e5aa81e15326b7c614eebd83ed3d88ff2617602d8a6  spec/langSysQuanta.ebnf
254eebe97e77dd15c889266f9e6d694fd4f51f14eddc8b68570db6da7366f4b9  spec/langSysQuanta.gbnf
65213e4f3af38157a05239f41cc15450a5133e91b09552d1b9ae0287dd52025d  spec/bls.md
1ebd879014fbc403765565c6f28d1b5686b615b6207098ae5fbbc395f08efcd9  spec/ub.md
50c858dca034d38c9dc2874083e11f199b18131ad9afd32da77865a36fdd5c6b  tests/conformance/README.md
c03f8d815da3f0a4fc22df5e1739d1627a235d22dc5a1a85ec3541a7c0211cc7  tests/conformance/pending/README.md
f36f3ee4fa74462405b8ead7a752c0267b6d4042c3685797ff9c446b1abea271  tests/syntax/00-s5/s5-03b-borrow-cast.ls
82609cfc39e6c122b0dff831598713db5d7a5f9ce3e2381215d032e189bb3910  tools/doc-lint
6b5ea58cb26e99a5e7de3933a1764337ed513bcf34391b5d5d7df0342d1da174  tools/diag-extract
e26cd8d769866897a888246fbeca235277a9c437688374eff723e8545747962f  tools/freeze-hash
d13560c0e2da2842855d280698a88c8774ae238add567067d4d336b609d25a4c  tools/req-registry
4e6fd1f6549dafe27c5d5b558410e441fb1fcf3e3f7479bc62dc3aa53b189416  tools/dag-check
170ef37aba8854212f1e9438e96acf94319126192609a1fc1d5377d7ba9c22d0  tools/metrics
f20e3b553c344cb807032c09ef6deaea457ffcea1bb4a028306b01c39b178546  tools/sec-audit
e68d16a07b21babb707c2196c734f3b2d8072fe439ac4dfb6d328234768eea59  tools/g0-scan
7abd9b70925d14916ff910c514fa8195d6675ee23807d90db6ca8c9ec0df96a8  tools/red-timing
0148b065343656e9d92c322a81633eff99865120be5004cf55786c3808c53012  tools/bench-gs5
edb23906ef13bf28d9e39cd214f80982fe8d17d062bc4e6e591cc96c9a8b71c2  spec/gs5-bench.md
fec2dbcda14af0289cb91d6acea15a8a5fd513c878b05a685c755f7cfd1e235a  tools/gs3-bench
85a30b44f6736a3ad20709aeed4025d4d9d2e62d88222a4510ec5a22212ca920  spec/gs3-bench.md
4a42bffd47b81bbc439480a85ac8820e60e2aef1897524ceb5c577f8548a80a6  tests/gs3/README.md
33e5d2138df67479363ccd918d971dd0e116a5ddb97e14b39f2065816c3578b6  tools/corpus-coverage
d72ff2b0aa342debbac9238fce9bd94ec7604c94b200ed7561b7f8e2cd4a2d1a  spec/test-matrix.md
e98423db8db7fe7b701a458b13fbd6e1326228fb4b185c38600a534708fb1308  spec/gs1-bench.md
b40a59aed7365d4bf5c6eec4777d40dc9fb37bdbf77ebfa731ee4e38e43de7a0  tools/unsafe-surface
d5811b8dd46170b7d01f6dffb8dc569fa71f1a511300a7d0271672156ab2a68c  tests/gs1/README.md
```
<!-- freeze-hash:end -->

## 3. 记录（人工维护）

| 项 | 值 |
|---|---|
| 生成日期 | 2026-11-28（GS1-0 三层证据链落地重冻结，SCOPE 31→34）；同日：TM-0 29→31、G-S3 26→29、G-S5 24→26；2026-11-27 G4-07 23→24；P2 21→23、P1 18→21、P0 同日；首次 2026-10-19 |
| HEAD | 见 `git log -1`（W0 提交） |
| 固定点 | `6158f95f…0f7d`（QEMU TCG 实测，`stage2 == stage3`，2026-11-27 R2.6-F 后）；历史：`e28e19e0…1a7`（R2.5）、R2.2 `fb8b8e32…390`、B7 `0b217692…fe584`、R3.6 `76c7cfe0…da72`、B5-7 `441ca62c…6e80` |
| 规则计数 | EBNF 119 产生式；GBNF 116 规则 |
| 诊断码 | 41（`spec/diagnostics.md`，含 TM-0 补登记 `E-LS-MODE`）+ 10 B-LS（`spec/bls.md`：ARITY/CAP/COHERENCE/COMPTIME/DUP/EFFECT/MAIN/NO-IMPL/REGION-ESCAPE/UNSUPPORTED） |
| 语料 | 以 `python tools/conformance-run` 输出为准（机器校验，2026-11-27 起）：`accept/` 6、`reject/` 10、`checker-spike/` 4+7、`pending/` 0。“记录”行不再人工维护计数 |
| 冻结变更记录 | 2026-11-27 P0：`tools/diag-extract` 新增 `--selfcheck`（CI 接入）；2026-11-27 P1： SCOPE 新增 `tools/req-registry`、`tools/dag-check`、`tools/metrics`（三件为门禁/评估脚本，纳入本清单变更即强制评审）；固定点行修正为 R2.6-F 实测值；2026-11-27 P2：SCOPE 新增 `tools/sec-audit`、`tools/g0-scan`（门禁脚本，21→23）；2026-11-27 G4-07：SCOPE 新增 `tools/red-timing`（RED 时序构成断言门禁脚本，23→24；SDD-Plus §6 G4-07 原声明裁剪项经追认转为实施）；2026-11-28 G-S5：SCOPE 新增 `spec/gs5-bench.md`（G-S5 测量协议，四项裁定 p90/CLI 含启动/三档阶梯/VM 主测＋Actions 佐证）与 `tools/bench-gs5`（协议可执行 harness，24→26；任务号 GS5-0）；2026-11-28 G-S3：SCOPE 新增 `spec/gs3-bench.md`（G-S3 修复成本微基准协议，四项裁定轮预算 3/Rust 臂阶段 0/17 任务原样/全文件重写）与 `tools/gs3-bench`（可执行 harness）与 `tests/gs3/README.md`（任务集登记与配对表，26→29；`tests/gs3/rust-reject/` 17 个任务由 selftest rustc 断言守护；任务号 GS3-0）；2026-11-28 TM-0：SCOPE 新增 `spec/test-matrix.md`（测试设计规范，D-TM-1 双例规则升门禁/D-TM-2 变异器先 spike/D-TM-3 组合正例入 accept）与 `tools/corpus-coverage`（双例机断第十门，check-docs.sh 九门→十门，CI 同步接入；基线豁免快照 2026-11-28 只减不增；conformance 语料 +3 负例 +5 正例经既有 SCOPE 条目重冻结；任务号 TM-0）。随裁定扩登记：00 §6.4 补 `E-LS-MODE` 码（诊断码 40→41，SDD-Plus §4.6；ls-sem 骨架实发码首例追认，其余 20 余个内部码仍待 SP2 批量登记），REQ-registry 接 REQ-044（不入本清单，req-registry --check 机器校验）。门禁工具变更属受控评审项 |
| 变更记录追加 | 2026-11-28 GS1-0：SCOPE 新增 `spec/gs1-bench.md`（G-S1/S2 三层证据链协议：L1 静态墙/L2 形式层/L3 运行时＋UB 矩阵 15 行四裁定 D-GS1-1..4）、`tools/unsafe-surface`（unsafe 原语种类计数器，类目表 v1）、`tests/gs1/README.md`（Rust 参照登记；slab.rs 参照编译验证过，31→34；任务号 GS1-0）；UB 矩阵断言折叠进 corpus-coverage 第二表，门禁数不变 |

> **打 tag 前**必须：① `bash tools/check-docs.sh` 绿；② `checker-spike` 的
> `accept/`/`reject/` 都 rc=0；③ 本文件 `--check` 通过。
> tag 命令：`git tag -a spec-freeze-candidate -m "L1 spec freeze candidate"`。
> 打 tag 后修改冻结内容必须走 `04 §9` 的变更规则。

## 4. 变更规则

1. 任何纳入范围的文件改动 → `--write` 重新生成 → 在提交里显式说明；
2. `--check` 失败 = 指纹漂移，必须评审后才能更新；
3. 打 tag 后修改冻结内容必须走 `04 §9`。

> AI生成
