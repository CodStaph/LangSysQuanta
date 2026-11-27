# spec/gs5-bench.md · G-S5 测量协议（增量检查 / 冷编译基准）

> **上位**：[`00`](../00-LangSysQuanta-设计初稿.md) §1.1（G-S5 判据）、00 §6.11（分析模块化边界 / D22 缓存键表）、
> 00 §7.9（`compile_time_per_round`）、00 §9（S1/S2 DoD 的 G-S5 首测点）、00 §10.4（判决纪律）、
> [`02`](../02-架构评审与ADR.md) ADR-8（分析模块化）；
> [`foundations.md`](foundations.md) F3（> 200ms 的单次求解不得进入编辑循环）。
> **工具**：[`tools/bench-gs5`](../tools/bench-gs5)（本协议的可执行实现；语料生成 + 编辑脚本 + 计时 + 指标输出）。
> **状态**：`冻结（裁定点，2026-11-28；四项裁定见 §2）`。修订走本文档 Change Log（只增不减）。

---

## 1. 范围与问题定义

### 1.1 测量对象

G-S5 承诺两件事：

| 判据 | 初稿口径（00 §1.1） | 本协议操作化 |
|---|---|---|
| 增量检查 | `增量检查 < 200ms / 10kLOC` | 单轮编辑后在 N-LOC 语料上执行检查命令的进程墙钟时间，p90 < 200ms（含启动，全档） |
| 冷编译 | `冷编译 ≤ Rust 同规模项目 0.5×` | 空缓存全量检查墙钟时间 ≤ 同任务 Rust 参照（`cargo build --release`）的 0.5×；阶段 2 接入 |

阶段 1 只判第一行；第二行在 S2 后端落地后测量（00 §9 S2 DoD）。

### 1.2 「10kLOC」的语义：档位，不是除数

10k 是语料规模档位，**禁止**解释为 `t / LOC` 归一化。依据 00 §6.11（D22）：
单函数编辑的失效面为 O(1)（函数级缓存、全程序分析仅链接期），故编辑循环时间
理论上与项目总规模无关。若 `t_edit` 随总规模上涨，判为**缓存键设计缺陷或全局
分析泄漏进编辑循环**，先修实现再谈毫秒数。

因此测量形态是**规模平坦性曲线**：三档语料各测同一编辑脚本族，曲线斜率
（50k 档相对 10k 档、200k 档相对 50k 档的 p90 增量）是 D22 的机器验证面。

## 2. 冻结裁定（2026-11-28，仓库所有者）

| # | 自由度 | 裁定 | 语义 |
|---|---|---|---|
| D-GS5-1 | 判据分位 | **p90** | 判死线绑 p90；p99 / max 仅在结果 JSON 中披露，不参与判决 |
| D-GS5-2 | 200ms 计时口径 | **S1 用 CLI 含启动** | 从进程创建到进程退出的墙钟时间（fork + exec + 解析 + 检查 + 输出）；LSP 常驻口径在 S1 末补测，只披露不判 |
| D-GS5-3 | 规模阶梯 | **10k / 50k / 200k 三档** | 三档全部过线才判 PASS；阶梯由 `tools/bench-gs5 --gen` 确定性生成 |
| D-GS5-4 | 测量环境 | **本机 VM 固定窗口为主 + GitHub Actions 佐证** | 主测环境出判决；Actions 同协议跑一遍作披露佐证；两环境结论冲突时以主测为准，并在 run 记录中登记差异归因 |

## 3. 口径（五项自由度的钉死值）

| 项 | 口径 |
|---|---|
| LOC 计数 | 非空、非注释物理行；排除 `// EXPECT:` 语料注解行与生成器头部标记行 |
| 程序状态 | **accept 态与 reject 态都测**：accept 态 = 编辑前语料 0 诊断；reject 态 = 编辑后语料含 ≥1 诊断；两态的时延都进判决 |
| 重复与预热 | 每个（档位 × 编辑 × 状态）格子 ≥ 30 次计时，弃前 2 次 warm-up，取余下样本算分位 |
| 分位插值 | 线性插值（`statistics.quantiles(method="inclusive")`，与 numpy linear 同义）；跨实现可比的协议指定值 |
| 计时原语 | `time.perf_counter()` 墙钟，包住整个子进程生命周期（D-GS5-2），包含 stdout/stderr 的写盘等待 |
| 编辑定界 | 每轮计时仅含「应用编辑 → 执行检查命令」；编辑脚本由 harness 预生成，语料在轮间重置（幂等） |

## 4. 测量协议

### 4.1 语料阶梯

1. 基准模块取自 00 §10.1 系统基准集的最小可检查子集（分配器 / 环形缓冲 / 调度器骨架）；
2. `tools/bench-gs5 --gen --target-loc N` 按固定种子机械扩展基准模块为 N-LOC 语料，
   模块名 / 函数名带序号，模块间默认零引用（独立岛），可选 `--dep-fanout K` 控制
   跨模块调用链宽度（K=0 为默认；非 0 时用于 E5 的下游传播测量）；
3. 语料必须是冻结 EBNF（v2.3）的合法 surface 文本——生成器不引入语法缺口；
4. 每次生成的语料 SHA-256 与种子随 run 记录输出；语料目录不入库（`.temp/` 下按需重建，逐字节可复现）。

### 4.2 编辑脚本与期望失效表

编辑脚本固定为五种（E1–E5），每种在每档语料上抽取相同分布的位置。期望失效面
逐条对表 00 §6.11 缓存键表，**任何一格实测失效面劣于期望即 FAIL**（先修缓存，
毫秒数不豁免）：

| 编辑 | 内容 | 期望失效（00 §6.11） |
|---|---|---|
| E1 | 函数体改一行（改一个整型字面量，签名不动） | 1 个函数 |
| E2 | 改函数签名（改一个参数类型） | 1 个函数 + 全部直接调用者 |
| E3 | 新增独立函数（无人调用） | 0（新增条目，无缓存失效） |
| E4 | 新增 impl 或泛型实例（触及既有类型） | 本 crate 单态化实例集合 |
| E5 | 改被依赖的公共函数（`--dep-fanout > 0` 时有效） | 下游 crate 图传播面 |

失效面计数由检查命令的结构化诊断侧信道提供（阶段 1 起 `ls check --emit-invalidation`；
阶段 0 无实现时该列为 `null` 并标注 `unmeasured`，不下判）。

### 4.3 指标族

| 指标 | 定义 | 判据 |
|---|---|---|
| `compile_time_incremental` | 单轮编辑后检查命令墙钟（3 档 × E1–E5 × 2 态） | 每格 p90 < 200ms（D-GS5-1/2/3） |
| `scale_flatness` | 相邻档位 p90 差值（10k→50k、50k→200k） | 每步增量 < 20ms；斜率为正即登记缓存泄漏嫌疑 |
| `invalidated_functions_per_edit` | 单轮编辑实测失效函数数 | = 00 §6.11 期望表（§4.2）；劣于期望即 FAIL |
| `compile_time_cold` | 空缓存全量检查墙钟 | 阶段 1 报告值；阶段 2 起 ≤ 0.5× Rust 参照 |
| `rust_cold_reference` | 同任务 Rust 参照 `cargo build --release` 墙钟 | 阶段 0 起采集存档（对照臂，判据在阶段 2 生效） |
| `boot_time_reference` | B-LS 自举链 `bootstrap/build.sh` → stage3 全程墙钟 | 阶段 0 起采集存档（自家工具链历史锚点，无判据） |

### 4.4 环境与统计纪律

1. 主测环境：本机 VM 固定窗口——进程绑核（Windows：`Start-Process -ProcessorAffinity` /
   `pintool`；Linux：`taskset`），关闭无关负载，记录采集起止时间；
2. 环境指纹必采：CPU 型号 / 核数 / OS 版本 / Python 版本 / 检查器版本（git describe）/
   绑核掩码 / 采集窗口长度；
3. 每格报告 p50 / p90 / p99 / max / CV；**CV > 5% 的格子标记 `invalid: true` 不参与判决**，
   该格作废并在同窗口内重测一次；复测仍 > 5% 则整 run 失败并登记；
4. Actions 佐证跑（D-GS5-4）：同一 run-id 前缀触发 CI 工作流，runner 型号入指纹；
   佐证结果不判 PASS/FAIL，只落 `evidence_ci` 字段；
5. 判决纪律沿用 00 §10.4：`results/gs5-<run-id>.json` 产出前，任何文档不得引用该 run 的结论。

## 5. 结果契约

`tools/bench-gs5 --write` 落 `results/gs5-<run-id>.json`（`<run-id>` = `UTC 时间戳-种子短哈希`），
schema 如下；stdout 摘要行 `GS5 VERDICT <run-id> PASS|FAIL` 可作 CI 断言面：

```text
{
  "run_id": "...",
  "protocol": {"spec": "spec/gs5-bench.md", "version": "1.0.0",
               "decisions": ["D-GS5-1", "D-GS5-2", "D-GS5-3", "D-GS5-4"]},
  "environment": {"cpu": "...", "cores": 0, "os": "...", "python": "...",
                  "checker": "<git describe>", "affinity": "...",
                  "window": ["<start UTC>", "<end UTC>"]},
  "corpora": [
    {"tier": "10k|50k|200k", "target_loc": 0, "loc": 0,
     "modules": 0, "dep_fanout": 0, "seed": 0, "sha256": "...",
     "dir": ".temp/bench-gs5/corpus-<loc>"}
  ],
  "grid": [
    {"tier": "10k", "edit": "E1", "state": "accept", "warmup": 2,
     "n": 30, "p50_ms": 0.0, "p90_ms": 0.0, "p99_ms": 0.0,
     "max_ms": 0.0, "cv_pct": 0.0, "rc": 0, "rc_consistent": true,
     "remeasured": false, "invalid": false,
     "invalidated_functions": null}
  ],
  "cold": {"check_ms": 0.0, "rust_reference_ms": 0.0,
           "boot_reference_ms": 0.0},
  "verdict": {"criterion": "p90<200ms all tiers (D-GS5-1..3)",
              "pass": false, "invalid_cells": 0,
              "scale_flatness_ms": {"10k_to_50k": 0.0, "50k_to_200k": 0.0},
              "evidence_ci": null, "notes": ""}
}
```

`invalidated_functions` 字段：阶段 0 为期望值常量（`E4` 为字符串 `"crate"`），
阶段 1 起由检查命令的结构化诊断侧信道回填实测值（00 §6.11 对表）。

## 6. 阶段与承接

| 阶段 | 时机 | 内容 | 判据生效面 |
|---|---|---|---|
| 0（先导） | S0′ 期并行（任务号 `GS5-0`） | 语料生成器 + harness + `--selftest`（内置 EBNF 语法门：生成语料与全部编辑产物必须被 `tools/ebnf-parse` 接受）；`rust_cold_reference` 与 `boot_time_reference` 基线采集存档；§4.2 期望失效表随本文档冻结（SP1 检查器实现完成后的验收对表基线） | 无（仅存档与 harness 自证） |
| 1（S1 首测） | SP1 后（00 §9 S1 DoD） | 接入 `ls check`（CLI 含启动口径）；`compile_time_incremental` / `scale_flatness` / `invalidated_functions_per_edit` 三指标下判 | p90 < 200ms 全档 |
| 2（S2） | 原生后端落地后 | `compile_time_cold` 对 0.5× Rust 参照下判；LSP 常驻口径补测披露 | 冷编译 0.5× |

阶段 0 产物对本仓库的即期价值：三档语料同时是 SP1 parser（06 §1 SP1「全部语料解析为 AST」）
的现成规模负载；`rust_cold_reference` 是 00 §10.1 对照实现要求项的首笔存档。

## Change Log

| 版本 | 日期 | 变更摘要 |
|---|---|---|
| 1.0.0 | 2026-11-28 | 首次冻结：四项裁定（D-GS5-1 p90 / D-GS5-2 CLI 含启动 / D-GS5-3 三档阶梯 / D-GS5-4 VM 主测 + Actions 佐证）；口径五项、协议四件套（语料阶梯 / 编辑脚本 E1–E5 对表 00 §6.11 / 指标族 / 环境统计纪律）；结果契约 JSON schema；阶段 0–2 承接表；任务号 GS5-0（工程先导，S0′ 期并行，不入 06 里程碑表） |

> AI生成
