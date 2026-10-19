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
e2ce3e7d638680ab550d729046ea98b194312843d277e9a12546e82b222493aa  spec/f0.md
25b2f54fd1655795a864c805e5e9c2e68f358342763c66f049a1d183c2c74070  spec/semantics.md
67123091b9d139554f6c65773e035bdf6284f7beb43ebb1caeca7004523f91d9  spec/modes.md
b207417000dd1301a8e84b3e06a5f3058f1791d840b003bf9b8a6e8f08e832f4  spec/effects.md
c6fa2c6d50438c13777564337d7f44c244a6ea0b032735e9f42138d52c03b358  spec/cap-context.md
ffe4d03d486988a7199e209aa39e3a50ec04cd175d8c996911842115936ff6d3  spec/diagnostics.md
3ba029061a4579b1df461c5cbae6ade908c283dd249b6daeba28922e54385533  spec/feature-coverage.md
207298db1b6be41d660cfa80f3bf5179bd699594999fd640af4e3b901c02c596  spec/elaboration.md
4f36012d170686c99963a2bbabf741b57d44f6d4e400bd6df34325f6b11bba0e  spec/langSysQuanta.ebnf
b04ddee2e6ed928482dc48e772f71064e07958922c2bfb44654748d3fdd4af59  spec/langSysQuanta.gbnf
a523c22c9bcd04751bcbeae468b8a1bbba08dec6e564c0effc826080a9b468f1  spec/bls.md
cda57474173ebd86c6907f5d2701be33e60deba975d3b4a3443a8e6f974947f6  spec/ub.md
97ece1fbc93e9ea10bd0d4d42d42f3c819573135cc994c43716a5afa371fe458  tests/conformance/README.md
3b5827da4705f2339e89e0ff80b305f980ff136738830b98b00c3fbbcf3971a6  tests/conformance/pending/README.md
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
