# S3-1 · build.sh 去种子（主路径 stage2-only）

> 状态：**实现完成，QEMU 全量验证通过（2026-11-27）**；
> commit：随 S3-1/S3-2 提交批次入库（证据命令与输出见 §4）。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §6（去种子）、§6.1；
> 前序：固定点 `stage2 == stage3`（`6158f95f…0f7d`，R2.6-F 后 QEMU 实测，去种子的前提）。
> 关键事实：seed 的 CLI 是 `-o <out>`；stage1 家族（names_stage）的 CLI 是
> **位置参数** `<in> <out>`（`argc >= 3`，argv[1]/argv[2]，见 `modules/90-main.ls`
> 的 `argc() < 3` usage 分支）——两条链不可混用。

## 1. 范围

| 项 | 状态 |
|---|---|
| 主路径：`build/stage2_self` 存在时**编译器链与 src 基线**由它编译 | ✅ |
| 主路径零 C 编译器、零 seed | ✅ |
| 冷启动路径：seed → stage1-names → stage2_self 一次性拉起后接管 | ✅ 保留（审计/复现/干净 CI） |
| `FORCE_SEED_CHAIN=1` 显式重走冷启动 | ✅ |
| seed `--run` 解释器角色 | ✅ 保留（测试基础设施，非构建路径） |
| seed 编译 16 个 bls 里程碑测试产物（run-linux.sh 内，测试基础设施） | ✅ 职责分离：M0/M1a/M1b 断言语义与历史一致 |
| Windows 开发宿主 | 保留 seed.exe 交叉构建（无法执行 Linux ELF；执行验证走 run-qemu.sh） |
| run-stage1.sh 固定点段 | 改造：stage1-names 复跑自举 cmp + 固定点 cmp + 主路径二次构建断言 |
| 新增 `bootstrap/ci/ensure-seed.sh` | ✅ 仅在 seed 缺失时构建（SKIP_SEED_CC=1 时报错）；四处调用 |

## 2. 实现

| 文件 | 改动 |
|---|---|
| `bootstrap/build.sh` | Linux 分支重构为双路径：`stage2_self` 存在 → 主路径；否则冷启动（seed 用 `-o` 编译 stage1-names，stage1-names 用位置参数自举 stage2_self）。产物范围收敛为**编译器链 + src 基线**（16 个 bls 里程碑测试产物移至 run-linux.sh 的 seed 段，见 §3 分诊记录） |
| `bootstrap/ci/ensure-seed.sh` | 新增：seed 缺失且非 SKIP_SEED_CC 时按宿主构建（Windows `-O2` 宿主编译 / Linux freestanding 交叉标志同 build.sh） |
| `bootstrap/ci/run-linux.sh` | build.sh 后：ensure-seed + seed 编译 16 个 bls 测试产物（同历史 build.sh Linux 分支的 seed 行）；后续行为断言全部不变 |
| `bootstrap/ci/run-stage1.sh` | ① build.sh 后与 compiled 段开头各调用一次 ensure-seed；② **compiled 测试段回退历史管线**：seed 生成 `build/stage1-seed`，30 处测试调用全部改用（自编译 codegen 缺陷未修前的保守面，见 §3）；③ 自举段改造：`stage1-names`（自编译版）复跑 `names_stage.ls → stage2_self_b`，`cmp stage2_self_b stage2_self`（自宿主确定性）；固定点段不变；④ compiled 段末尾新增**主路径二次构建断言**：再次 `build.sh` 必须输出 `selfhost: main path`，且 stage2_self 编译 calc.ls 的产物执行 exit 14/`calc ok` |
| `bootstrap/ci/run-interp.sh` | 开头调用 ensure-seed（同 ① 理由） |

## 3. 语义对照

| 场景 | 旧行为 | 新行为 |
|---|---|---|
| 干净 Linux 检出（CI/QEMU guest） | seed 编译全部 23 个产物 | 冷启动：seed 编译 1 次（stage1-names），stage1-names 自举 stage2_self，stage2_self 编译 src 基线 7 个；16 个 bls 里程碑测试产物由 run-linux.sh 内的 seed 编译（断言语义不变） |
| Linux 增量（stage2_self 已存在） | 每次都重走 seed 链 | 主路径：编译器链 + src 基线由 stage2_self 编译，seed/C 编译器不在场 |
| 审计/复现 | 隐式走 seed 链 | `FORCE_SEED_CHAIN=1` 显式冷启动 |

**关键发现（分诊记录）**：names_stage 家族并非 seed 能力的超集，且**自编译产物存在既有 codegen 缺陷**。两层发现：

1. **seed 专属面**（4/16）：`unicode`/`match`/`payload`/`io` 被 names_stage 拒绝
   （解释模式实测：`ctl: bad if expr`、`match: expected return`、
   `struct: bad let expr`；根因是 names_stage 的已知窄面，如 match arm 仅
   `{ return expr; }`）。这 4 个从未进入 stage1 家族验证面（历史仅 seed 编译）。
   处置：职责分离——B-LS 里程碑测试产物归 seed（测试基础设施），
   编译器链与 src 基线归 stage2_self（构建路径）。
2. **自编译编译器 codegen 缺陷**：自编译版二进制（stage2_self）编译含
   struct 字段访问的程序失败（`stage1_names.ls` → `struct: unknown field`，
   QEMU 实测 rc=4），而同一逻辑在三条对照路径上均通过：seed `--run` 解释
   （本轮 guest 解释段全绿）、seed 构建的 stage1-names（历史 compiled 段全绿）、
   以及无 struct 的测试（calc/offset 族）。**固定点无法暴露此缺陷**：
   names_stage.ls 自身不含 struct 字段访问（B-LS 编译器容器单态化，
   05 §3.2），自编译幂等路径不经过该 codegen 分支；历史上 stage2_self 仅被
   断言过 4 个无 struct 程序（calc/high/big/huge offset）。
   处置：compiled 测试段回退历史管线（seed 构建 `stage1-seed`，30 处测试
   调用全部改用之）；自编译产物仍由自宿主确定性 + 固定点断言覆盖；
   **“stage2_self 类自编译编译器对全语料的编译质量”登记为缺口**，
   与 DDC（双 C 编译器差分）同框立项（05 §6.3 第 2 条的深层动机）。

## 4. 验证

### 4.1 本地（Windows 宿主）

| 项 | 结果 |
|---|---|
| `bash -n`（build.sh / ensure-seed.sh / run-stage1.sh / run-interp.sh） | PASS |
| `bootstrap/ci/run-interp.sh`（seed --run 全部 B-LS 测试） | PASS（含 Unicode 列、非法 UTF-8 拒绝） |
| `bootstrap/build.sh` Windows 分支 | PASS（seed.exe 交叉构建 + 全产物；S3-2 的模块拼接 cmp 断言一并生效） |

### 4.2 宿主 run-stage1（Windows/MSYS，解释段）

`bootstrap/ci/run-stage1.sh`：解释段全绿（含 `stage2_a == stage2_b` 确定性复跑）；
compiled 段按宿主约定 SKIP。

### 4.3 QEMU 全量（冷启动链 + 固定点 + 主路径二次构建）

`QEMU_TIMEOUT=7200 bootstrap/ci/run-qemu.sh`：**RESULT=PASS**（guest 约 84 分钟，
2026-11-27 第 4 轮；前 3 轮失败见 §3 分诊记录与提交说明）。关键行：

```text
selfhost: cold start - seed chain produced build/stage2_self
selfhost: built compiler chain + src baselines (build/stage1-*)
bootstrap CI: M0/M1a/M1b + Unicode (UTF-8) OK        ← 16 个里程碑断言（seed 管线，语义不变）
interp: all B-LS tests passed
selfhost: main path - compiler = build/stage2_self (seed out of the build)   ← run-stage1.sh 内实测主路径
PASS interpreted stage1 determinism (stage2_a == stage2_b)
PASS self-host determinism (stage1-names reproduces stage2_self)            ← 新断言
PASS fixed point: stage2 == stage3
PASS S3-1 selfhost main path (second build.sh seed-free; stage2_self artifact OK)   ← 新断言
6158f95f620bb5daf56db70e58830779a1f6a19ca2ad4d04075550e73a380f7d  build/stage2_self
6158f95f620bb5daf56db70e58830779a1f6a19ca2ad4d04075550e73a380f7d  build/stage3_self
```

固定点指纹与 R2.6-F 基线完全一致（`6158f95f…0f7d`）。

## 5. 结论与边界

- **结论**：主路径构建不再依赖 C 编译器与 seed；seed 的三个角色收敛为两个
  （冷启动拉起、`--run` 解释器/里程碑测试产物编译），第三个角色（日常构建
  编译器）已由 stage2_self 接管。
- **发现（诚实降级）**：自编译编译器对含 struct 字段访问程序的 codegen
  存在缺陷（§3 第 2 层；复现：`stage2_self stage1_names.ls out` →
  `struct: unknown field`）。在修复前 compiled 测试段保持 seed 管线；
  该缺陷与“自举质量只能由固定点+4 程序背书”的验证面局限同源，
  升级验证需 DDC/反汇编差分，随 Stage 3 后续立项。
- **边界 1**：干净环境（CI/guest）仍走冷启动——去种子不是"删除 seed"，
  而是"退出日常构建路径"；删除 seed 属 Stage 3 后续的 DDC/双 seed 信任锚点议题。
- **边界 2**：`stage1-names` 产物名沿用，但冷启动下语义 = seed 家族第一代，
  主路径下语义 = stage2_self 自编译产物（源码未变时与 stage2_self 逐字节相同，固定点）。
- **边界 3**：Windows 宿主无法执行 Linux ELF，主路径在该宿主不可达
  （05 §0.1：Windows 只是开发宿主）；其执行验证由 run-qemu.sh 承担。

> AI生成
