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
12cd7ca3325f297f7e317821653978d5cdf980cf63b0cbc6ef67df7f103c84c3  spec/semantics.md
5233f800dac83a63b6b6862437c6eb2c6b1c9da8cc832d786e90d5a93b1898dd  spec/modes.md
6572c6713bb330760a6260781cc75e4aae1fd4f3c9bf4b8b24aad18d7f99cce6  spec/effects.md
c6fa2c6d50438c13777564337d7f44c244a6ea0b032735e9f42138d52c03b358  spec/cap-context.md
ffe4d03d486988a7199e209aa39e3a50ec04cd175d8c996911842115936ff6d3  spec/diagnostics.md
b5f4030adcd43d1b38a59ce4238bd46a445ef4c4aebd7446a677e5054a8a36ef  spec/feature-coverage.md
2ed09bbdfd1f649e4a9014e96eedb68d49046d6fe59e0e0dc937e469917a4d41  spec/elaboration.md
4f36012d170686c99963a2bbabf741b57d44f6d4e400bd6df34325f6b11bba0e  spec/langSysQuanta.ebnf
b04ddee2e6ed928482dc48e772f71064e07958922c2bfb44654748d3fdd4af59  spec/langSysQuanta.gbnf
a523c22c9bcd04751bcbeae468b8a1bbba08dec6e564c0effc826080a9b468f1  spec/bls.md
47f0702b2d04188fc703b5aa8e29e8a7dd02170a538e5cb4e5711e74052115ca  spec/ub.md
29128af4d9d81dc0d12efc693f65aa14af65378b700832e8c711c661f8a6e19e  tests/conformance/README.md
c03f8d815da3f0a4fc22df5e1739d1627a235d22dc5a1a85ec3541a7c0211cc7  tests/conformance/pending/README.md
f36f3ee4fa74462405b8ead7a752c0267b6d4042c3685797ff9c446b1abea271  tests/syntax/00-s5/s5-03b-borrow-cast.ls
57f2268da0fee0b4f32589d6140353869a26f7d1322c839cb11907cb725532a7  tools/doc-lint
9cc5201a5f5f7bcd9aef08027fc63ae1b52bd0486090c4237e36385e53154049  tools/diag-extract
1978f75ba325180719f556e0abe2fedb58d5df00abbe017f82260e6ad2e80206  tools/freeze-hash
```
<!-- freeze-hash:end -->

## 3. 记录（人工维护）

| 项 | 值 |
|---|---|
| 生成日期 | 2026-10-19 |
| HEAD | 见 `git log -1`（W0 提交） |
| 固定点 | `440e2188…ce29`（QEMU TCG 实测，`stage2 == stage3`） |
| 规则计数 | EBNF 117 产生式；GBNF 114 规则 |
| 诊断码 | 40（`spec/diagnostics.md`）+ 2 B-LS（`spec/bls.md`） |
| 语料 | `accept/` 4、`reject/` 7、`pending/` 15 |

> **打 tag 前**必须：① `bash tools/check-docs.sh` 绿；② `checker-spike` 的
> `accept/`/`reject/` 都 rc=0；③ 本文件 `--check` 通过。
> tag 命令：`git tag -a spec-freeze-candidate -m "L1 spec freeze candidate"`。
> 打 tag 后修改冻结内容必须走 `04 §9` 的变更规则。

## 4. 变更规则

1. 任何纳入范围的文件改动 → `--write` 重新生成 → 在提交里显式说明；
2. `--check` 失败 = 指纹漂移，必须评审后才能更新；
3. 打 tag 后修改冻结内容必须走 `04 §9`。
