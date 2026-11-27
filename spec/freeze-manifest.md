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
ffe4d03d486988a7199e209aa39e3a50ec04cd175d8c996911842115936ff6d3  spec/diagnostics.md
051b09ec1a1185c7fe4297bc0e436854041f6796848a5e21ae5abc9377fe468b  spec/feature-coverage.md
2ed09bbdfd1f649e4a9014e96eedb68d49046d6fe59e0e0dc937e469917a4d41  spec/elaboration.md
dcd0253770672ee6a2d11e5aa81e15326b7c614eebd83ed3d88ff2617602d8a6  spec/langSysQuanta.ebnf
254eebe97e77dd15c889266f9e6d694fd4f51f14eddc8b68570db6da7366f4b9  spec/langSysQuanta.gbnf
65213e4f3af38157a05239f41cc15450a5133e91b09552d1b9ae0287dd52025d  spec/bls.md
1ebd879014fbc403765565c6f28d1b5686b615b6207098ae5fbbc395f08efcd9  spec/ub.md
29128af4d9d81dc0d12efc693f65aa14af65378b700832e8c711c661f8a6e19e  tests/conformance/README.md
c03f8d815da3f0a4fc22df5e1739d1627a235d22dc5a1a85ec3541a7c0211cc7  tests/conformance/pending/README.md
f36f3ee4fa74462405b8ead7a752c0267b6d4042c3685797ff9c446b1abea271  tests/syntax/00-s5/s5-03b-borrow-cast.ls
82609cfc39e6c122b0dff831598713db5d7a5f9ce3e2381215d032e189bb3910  tools/doc-lint
6b5ea58cb26e99a5e7de3933a1764337ed513bcf34391b5d5d7df0342d1da174  tools/diag-extract
a7486b58c92c94cf97ba453895caaa11e0468a357fa6752957d75b47e7a82857  tools/freeze-hash
d13560c0e2da2842855d280698a88c8774ae238add567067d4d336b609d25a4c  tools/req-registry
4e6fd1f6549dafe27c5d5b558410e441fb1fcf3e3f7479bc62dc3aa53b189416  tools/dag-check
fa5ccb74ac982eed8cb1100e7e32211d87fa3aa9f24c0fc743cea965c7358fd6  tools/metrics
f20e3b553c344cb807032c09ef6deaea457ffcea1bb4a028306b01c39b178546  tools/sec-audit
e68d16a07b21babb707c2196c734f3b2d8072fe439ac4dfb6d328234768eea59  tools/g0-scan
7abd9b70925d14916ff910c514fa8195d6675ee23807d90db6ca8c9ec0df96a8  tools/red-timing
```
<!-- freeze-hash:end -->

## 3. 记录（人工维护）

| 项 | 值 |
|---|---|
| 生成日期 | 2026-11-27（G4-07 断言落地重冻结，SCOPE 23→24；P2 整改重冻结 SCOPE 21→23、P1 SCOPE 18→21、P0 同日；首次 2026-10-19） |
| HEAD | 见 `git log -1`（W0 提交） |
| 固定点 | `6158f95f…0f7d`（QEMU TCG 实测，`stage2 == stage3`，2026-11-27 R2.6-F 后）；历史：`e28e19e0…1a7`（R2.5）、R2.2 `fb8b8e32…390`、B7 `0b217692…fe584`、R3.6 `76c7cfe0…da72`、B5-7 `441ca62c…6e80` |
| 规则计数 | EBNF 119 产生式；GBNF 116 规则 |
| 诊断码 | 40（`spec/diagnostics.md`）+ 10 B-LS（`spec/bls.md`：ARITY/CAP/COHERENCE/COMPTIME/DUP/EFFECT/MAIN/NO-IMPL/REGION-ESCAPE/UNSUPPORTED） |
| 语料 | 以 `python tools/conformance-run` 输出为准（机器校验，2026-11-27 起）：`accept/` 6、`reject/` 10、`checker-spike/` 4+7、`pending/` 0。“记录”行不再人工维护计数 |
| 冻结变更记录 | 2026-11-27 P0：`tools/diag-extract` 新增 `--selfcheck`（CI 接入）；2026-11-27 P1： SCOPE 新增 `tools/req-registry`、`tools/dag-check`、`tools/metrics`（三件为门禁/评估脚本，纳入本清单变更即强制评审）；固定点行修正为 R2.6-F 实测值；2026-11-27 P2：SCOPE 新增 `tools/sec-audit`、`tools/g0-scan`（门禁脚本，21→23）；2026-11-27 G4-07：SCOPE 新增 `tools/red-timing`（RED 时序构成断言门禁脚本，23→24；SDD-Plus §6 G4-07 原声明裁剪项经追认转为实施）。门禁工具变更属受控评审项 |

> **打 tag 前**必须：① `bash tools/check-docs.sh` 绿；② `checker-spike` 的
> `accept/`/`reject/` 都 rc=0；③ 本文件 `--check` 通过。
> tag 命令：`git tag -a spec-freeze-candidate -m "L1 spec freeze candidate"`。
> 打 tag 后修改冻结内容必须走 `04 §9` 的变更规则。

## 4. 变更规则

1. 任何纳入范围的文件改动 → `--write` 重新生成 → 在提交里显式说明；
2. `--check` 失败 = 指纹漂移，必须评审后才能更新；
3. 打 tag 后修改冻结内容必须走 `04 §9`。

> AI生成
