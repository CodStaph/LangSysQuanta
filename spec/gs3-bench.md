# spec/gs3-bench.md · G-S3 修复成本微基准协议（阶段 0）

> **上位**：[`00`](../00-LangSysQuanta-设计初稿.md) §0（差异化落点：写错后可局部归因、可机器修复、不扩大 unsafe）、
> 00 §7.8（修复闭环）、00 §7.9（指标表：目标列"冻结于 run-id"，本协议给出阶段 0 冻结件）、
> 00 §10.3（四臂与 EL-1）、00 §10.4（判决纪律）、00 §1.1 G-S3 / `H-LS-11`；
> [`gs5-bench.md`](gs5-bench.md)（同族协议先例：run-id 绑定与 JSON 契约）。
> **工具**：[`tools/gs3-bench`](../tools/gs3-bench)（任务注册表 + 修复循环 runner + 双求解器适配器 + 指标输出）。
> **任务集**：`tests/conformance/reject/`（10）+ `tests/conformance/checker-spike/reject/`（7）
> ＋ 对照臂 `tests/gs3/rust-reject/`（17 手写）。
> **状态**：`冻结（裁定点，2026-11-28；四项裁定见 §2）`。修订走本文档 Change Log（只增不减）。

---

## 1. 范围与问题定义

G-S3 的主卖点是**修复面**而非生成面（00 §0：EL-1 客场作战，`first_check_rate` 在
预训练熟悉度补齐前不承载主张）。阶段 0 用现有可执行资产（conformance 语料即为
判定器拒绝的缺陷程序）建立**修复成本微基准**：模型在环、逐轮判定、指标绑定
run-id。n=17 是先导规模：只出每任务明细与方向性汇总，**禁止任何显著性声明**。

### 1.1 测什么

| 指标（00 §7.9 对齐） | 定义 | 阶段 0 角色 |
|---|---|---|
| `mean_rounds` | 任务从题面到判过的模型调用轮数（上限 = D-GS3-1 轮预算） | 主指标（vs Rust 对照臂） |
| `resolved_rate` | 轮预算内判过的任务占比 | 报告值 |
| `repair_diff_bytes` | difflib unified diff 字节数（题面 → 模型终稿），harness 自算 | 报告值 |
| `excess_diff_bytes` | difflib unified diff 字节数（gold 孪生 → 模型终稿），仅登记了 gold 的任务 | 报告值（超修惩罚） |
| `unsafe_delta` | 终稿 vs 题面的 `unsafe` 计数差（按词边界） | **硬门禁字段**：全集合计 > 0 ⇒ `hard_gate_violation` |
| `deletive_fix` | 删行数 ≥ 增行数 的净删除式修复 | 仅报告（反作弊缺口登记，§7） |

## 2. 冻结裁定（2026-11-28，仓库所有者）

| # | 自由度 | 裁定 | 语义 |
|---|---|---|---|
| D-GS3-1 | 求解器口径 | **温度 0；单一模型版本钉入 run 记录；轮预算 3（严格档）** | 每任务最多 3 次「模型输出 → 判定器复检」；解析失败/空输出也计为一次轮预算消耗 |
| D-GS3-2 | Rust 对照臂 | **阶段 0 即建立**（17 个手写任务，`tests/gs3/rust-reject/`，文件名与 L-Sys 任务一一映射） | 同模型、同循环、同轮预算；判定器为 `rustc` |
| D-GS3-3 | 任务集构成 | **17 个 reject 原样**（不重构、不注入；真实错误分布） | 题面 = 原文件剥除首行 `// EXPECT:` 元数据之后的内容 |
| D-GS3-4 | 修复输出格式 | **全文件重写**；`repair_diff_bytes`/`excess_diff_bytes` 一律由 harness 用 `difflib` 对落盘终稿自算 | 不采信模型自报 diff；harness 剥除输出中的成对代码围栏后整段落盘 |

## 3. 任务集与判定器

| 臂 | 任务 | 判定命令 | 通过/失败语义 |
|---|---|---|---|
| L-Sys（ls-sem） | `tests/conformance/reject/*.ls`（10） | `ls-sem check <file>` | rc=0 通过；rc=1 失败（诊断 stdout） |
| L-Sys（spike） | `tests/conformance/checker-spike/reject/*.ls`（7） | `checker-spike <file>`（release 二进制） | rc=0 通过；rc=1 失败 |
| Rust | `tests/gs3/rust-reject/*.rs`（17 手写） | `rustc --edition 2021 --crate-type lib <file>` | rc=0 通过；rc≠0 失败（错误码 stderr） |

配对原则（按错误语义族，非逐码等价）与已知缺口：

- Rust 侧首行 `// EXPECT-RUSTC: Exxxx` 为任务自检元数据（题面前剥除，
  不进入模型上下文），由 `gs3-bench --selftest` 用 rustc 实测校验
  "原题确实被拒且触发该码"；
- 配对为**语义近邻**而非等价转换，例如：L-Sys 锁 rank（静态锁序规则）在 Rust 无
  编译期对应物，配对为 `Rc<Mutex<_>>` 的 `!Send` 违规（E0277）；L-Sys RACE 族的
  `shared`/跨域规则配对为 Send/Sync / 'static 边界族（E0277/E0521/E0373）；
- 错误码以 **rustc 实测**为准（17/17 已验证；详见 `tests/gs3/README.md` 配对表）。

## 4. 循环协议（阶段 0）

```
题面（程序全文 + 固定任务指令模板，无错误码提示）
── 每轮 ──────────────────────────────
  模型输出（全文件重写）
    → harness：剥代码围栏 → 落盘 .temp/gs3-bench/<task>/round-N.out
    → 判定器复检
    → rc=0：rounds = 当前轮号，resolved，退出
    → rc≠0：判定器完整输出回灌上下文，进入下一轮
── 轮预算耗尽（3 轮）→ unresolved
```

1. 上下文 = system 指令 + 题面 +（逐轮累计的）judged 输出与判定器诊断；
   模型只看得到判定器说了什么，看不到期望错误码；
2. prompt 模板为仓库内常量，SHA-256 随 run 记录输出（复现要件）；
3. API 适配器：`GS3_SOLVER_URL` / `GS3_SOLVER_MODEL` ＋凭据二选一：
   `GS3_SOLVER_KEY` 环境变量或 `GS3_SOLVER_KEY_FILE` 文件路径
   （文件路径避免凭据出现在命令行与环境转储；OpenAI chat-completions
   兼容口径）；**key 永不进入任何日志、run 记录或 JSON 产物**；
   无凭据时工具只允许以 `--stub` 求解器运行；
4. 真实模型 run 的费用由仓库所有者承担并先行明确授权（`--run` 的 API 模式
   在 selftest 与 CI 中被禁用）。

## 5. 结果契约

`tools/gs3-bench --run --write` 落 `results/gs3-<run-id>.json`
（`<run-id>` = `gs3-<UTC 时间戳>-<种子短哈希>`）：

```text
{
  "run_id": "...",
  "protocol": {"spec": "spec/gs3-bench.md", "version": "1.0.0",
               "decisions": ["D-GS3-1", "D-GS3-2", "D-GS3-3", "D-GS3-4"],
               "prompt_sha256": "..."},
  "environment": {"python": "...", "checker": "<git describe>",
                  "solver": {"mode": "stub|api", "model": "...",
                             "temperature": 0.0, "round_budget": 3,
                             "api_url_host": "host-name-only"},
                  "window": ["<start UTC>", "<end UTC>"]},
  "tasks": [
    {"id": "<file stem>", "lang": "lsys-lssem|lsys-spike|rust",
     "expected_code": "...", "source": "<repo path>",
     "gold": "<repo path|null>",
     "rounds_used": 0, "resolved": false,
     "repair_diff_bytes": 0, "excess_diff_bytes": null,
     "unsafe_delta": 0, "deletive_fix": false,
     "round_rc": [1, 1, 1], "log_dir": ".temp/gs3-bench/<task>"}
  ],
  "summary": {"n": 34, "resolved": 0, "resolved_rate": 0.0,
              "mean_rounds_resolved": null, "mean_rounds_all": 0.0,
              "mean_repair_diff_bytes_resolved": null,
              "unsafe_delta_total": 0, "deletive_fixes": 0,
              "hard_gate": {"unsafe_delta_ok": true, "violations": []}},
  "verdict": {"stage": "0-pilot",
              "claim": "none: descriptive only (significance testing is not
                        permitted at n=17; thresholds frozen at stage 1/2)"}
}
```

## 6. gold 孪生（仅 3 个最强配对）

| 任务 | gold | 修法语义 |
|---|---|---|
| `E-LS-ALIAS-r2-write-during-borrow` | `tests/conformance/accept/accept-r2-borrow-then-write.ls` | 把 owner 写移出借用存活区 |
| `E-LS-RACE-r8-box-across-spawn` | `tests/conformance/accept/accept-r8-iso-spawn.ls` | box → iso 显式转移所有权 |
| `E-LS-RACE-r8-val-local-region-spawn` | `tests/conformance/accept/accept-r8-val-static-spawn.ls` | val 提升到 static-region 再跨域 |

其余 14 任务 gold = null（不存在结构孪生），`excess_diff_bytes` 不计算。
Rust 臂阶段 0 无 gold 对照（任务为手写最小程序，无标准修法版本）。

## 7. 已知缺口（诚实登记，阶段 1/2 处置）

1. **删行式修复**：模型可用删除报错语句通过判定器。阶段 0 仅以
   `deletive_fix` 字段报告占比，不下判；真正的反作弊 = 阶段 2 维护任务
   （00 §10.1：维护任务 ≥ 50%）＋ `regression_rate = 0` 硬门（原通过用例
   不得退化——阶段 2 引入配对测试 oracle）；
2. **显著性纪律**：n=17 先导，禁止 p 值/显著性声明（00 §10.3：检验口径与
   停止规则先冻结再跑——阶段 2 扩任务集后另行冻结）；
3. **EL-1 单边逻辑**：预训练熟悉度账单记 L-Sys 侧；Rust 臂获胜对 L-Sys 是
   不利方向的真信号，L-Sys 臂获胜受"任务更小"混淆（阶段 1 消融列补强，
   阶段 2 equal-data 臂才是 H-LS-11 升级证据）；
4. **`fixit_applicable_rate`**：依赖 SP3 的 AST patch fix-it（06 §1 SP3），
   阶段 0 不测量（无 fix-it 面）；阶段 1 起入指标。

## 8. 阶段与承接

| 阶段 | 时机 | 内容 | 判据 |
|---|---|---|---|
| 0（本协议） | S0′ 期并行（任务号 `GS3-0`） | 微基准 harness ＋ 17+17 任务集 ＋ stub 自证；真实模型 run 待所有者授权 API 口径后执行 | 无判决阈值；`hard_gate.unsafe_delta_ok` 例外（机器断言） |
| 1（消融） | SP3 落地后 | 三列对照（裸模型 / +结构化诊断 / +fix-it）＋ `model_scaling` 双档；`fixit_applicable_rate` 入表（0.5 → 00 §7.9 冻结值 0.6） | 消融差值方向性结论 |
| 2（四臂终局） | S4 | 系统基准集 + 维护任务 ≥ 50%；zero-shot / few-shot / constrained-decode / **equal-data-finetune**；阈值、显著性、停止规则先冻结 | `LS-03` 枪毙线绑 equal-data 臂 |

## Change Log

| 版本 | 日期 | 变更摘要 |
|---|---|---|
| 1.0.0 | 2026-11-28 | 首次冻结：四项裁定（D-GS3-1 温度 0＋模型版本钉入＋轮预算 3；D-GS3-2 Rust 臂阶段 0 建立；D-GS3-3 17 任务原样；D-GS3-4 全文件重写＋harness difflib 自算）；三臂判定器契约（ls-sem / checker-spike / rustc）；循环协议与 prompt 哈希入档；gold 孪生 3 项；缺口登记（删行修复/显著性/EL-1/fix-it）；阶段 0–2 承接表；任务号 GS3-0（工程先导，不入 06 里程碑表） |
| 1.0.1 | 2026-11-28 | 凭据读取增加 GS3_SOLVER_KEY_FILE 文件路径（与 GS3_SOLVER_KEY 二选一，避免key 出现在命令行/环境转储；key 永不入日志与产物不变）；具体端点与模型号不属于本协议内容，由 run 记录 environment.solver 字段承载（首跑配置：DeepSeek V4.1-Flash，调用标识 deepseek-flash，所有者选定） |

> AI生成
