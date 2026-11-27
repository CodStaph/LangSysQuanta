# S3-2 · stage1 模块拆分（物理拼接式）

> 状态：**实现完成，QEMU 全量验证通过（2026-11-27）**；
> commit：随 S3-1/S3-2 提交批次入库（证据命令与输出见 §4）。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §4.1（模块拆分目标）、§6.4；
> 前序：[`results/S3-1-desseed.md`](S3-1-desseed.md)（build.sh 改造同批落地）。
> 关键约束：①`names_stage` 顶层函数 **128/128 触顶**，拆分**零新增顶层函数**；
> ②EBNF v2.3 冻结不演进——**不引入 include/模块语法**，拼接在构建层完成；
> ③固定点指纹 `6158f95f…0f7d` 不得漂移（源字节不变 ⇒ 产物必然不变）。

## 1. 方式选择

| 方案 | 判定 |
|---|---|
| B-LS 加 `include`/模块语法 | **否**：动 EBNF 冻结面（`spec/bls.md` 在 freeze-manifest SCOPE），且 seed/stage1 双端实现成本高 |
| 构建层物理拼接（选定） | 模块文件为**编辑入口**，`names_stage.ls` 为**生成物**；零语言改动、零下游路径改动、字节等价可机器断言 |
| 重排/合并函数 | **否**：字节等价要求连续区间切割，函数顺序原样保留（B-LS 函数定义顺序本就无关：名字表前置扫描） |

## 2. 落地

| 文件 | 内容 |
|---|---|
| `bootstrap/src/modules/00-header-scan.ls` | 行 1–947：文件头注释 + 词法/预检/声明扫描/诊断位置（`skip`…`expect_char`，含 `diag_pos`） |
| `bootstrap/src/modules/10-emit-bytes.ls` | 行 948–999：字节发射基础（`emit1`/`emit4`/`put16`/`put32`/`put64`/`copy`） |
| `bootstrap/src/modules/20-symtab.ls` | 行 1000–1291：名字/变量/数组/切片/字符串表（`name_id`…`str_add`） |
| `bootstrap/src/modules/30-types.ls` | 行 1292–1685：Str/struct/enum/Option/类型解析与表（`utf8_count`…`gen_peek`、`parse_ty`） |
| `bootstrap/src/modules/40-generics.ls` | 行 1686–1818：泛型模板/实例表（`tmpl_*`/`inst_*`/`mk_inst`/`parse_user_desc`） |
| `bootstrap/src/modules/50-parse-utils.ls` | 行 1819–2439：优先级/post 装箱/索引/约束/ref 实参（`prec`…`make_ref_arg`） |
| `bootstrap/src/modules/60-parse-expr.ls` | 行 2440–3639：`parse_expr`（单函数 1200 行） |
| `bootstrap/src/modules/70-emit-expr.ls` | 行 3640–5285：`emit_expr_a`…`emit_expr_c` + `emit_expr`/跳转补丁/`emit_ret` |
| `bootstrap/src/modules/80-scan-stmts.ls` | 行 5286–5617：语句扫描（`scan_*` 家族 + `scan_stmts`） |
| `bootstrap/src/modules/85-emit-stmts.ls` | 行 5618–8786：语句发射（`emit_stmt_list`/`emit_stmt_span`/`emit_body`） |
| `bootstrap/src/modules/90-main.ls` | 行 8787–11819：`main`（ELF 组装/写出/runtime 块） |
| `bootstrap/src/assemble.sh` | 新增：`cat modules/*.ls > names_stage.ls`（数字前缀即拼接序）；模块演进后运行并同批提交生成物 |
| `bootstrap/src/names_stage.ls` | **保留原路径、转为生成物**：本轮重新生成后与拆分前逐字节相同（下游零改动） |

## 3. 防漂移机器断言

`bootstrap/build.sh` 开头（两个宿主分支共用）：

```bash
cat "$ROOT"/src/modules/*.ls > "$asm_tmp"
cmp -s "$asm_tmp" "$ROOT/src/names_stage.ls" || { ...; exit 4; }
```

编辑模块未重新 assemble、或直接手改生成物，构建立即失败（exit 4），
提示运行 `bootstrap/src/assemble.sh`——不依赖自觉。语法门
（`tests/syntax/run.py`）对 `src/*.ls` 非递归 glob：生成物照常受检，
模块片段不要求整程序可解析，故**语法门零改动**。

## 4. 验证

### 4.1 拆分等价（一次性断言）

`python .temp/split.py`（切割工具，一次性）：11 个模块行区间 1–11819 无缝覆盖，
`b"".join(chunks) == data` 字节级成立：

```text
source: 571573 bytes, 11819 lines
reassembly: byte-identical to source
sha256(source)     = 53c14bd90cd18eedca8c3f371edc201619e22ae0241ac46ad70ee5732efc066a
sha256(reassembled)= 53c14bd90cd18eedca8c3f371edc201619e22ae0241ac46ad70ee5732efc066a
```

`bootstrap/src/assemble.sh` 重新生成后与拆分前原文件 `cmp`：**逐字节一致**。

### 4.2 本地回归（Windows 宿主）

| 项 | 结果 |
|---|---|
| `bootstrap/build.sh`（Windows 分支，含拼接 cmp 断言） | PASS |
| `bootstrap/ci/run-interp.sh` | PASS |
| `bootstrap/ci/run-stage1.sh` 解释段 | PASS（同 S3-1 §4.2） |

### 4.3 QEMU 全量

与 S3-1 同轮 guest 全量（同一次 84 分钟运行）：固定点指纹**不变**——
`stage2 == stage3`，SHA-256 均为
`6158f95f620bb5daf56db70e58830779a1f6a19ca2ad4d04075550e73a380f7d`（R2.6-F 基线）；
拆分零行为变更由全量实证（源字节不变 ⇒ 编译器产物逐字节相同）。
另：新增的自宿主确定性断言 `PASS self-host determinism (stage1-names
reproduces stage2_self)` 与主路径断言同轮绿（见 `S3-1-desseed.md` §4.3）。

## 5. 结论与边界

- **结论**：`names_stage.ls` 的"单文件 11.8k 行"约束解除为 11 个 ≤19 万字节
  的可独立定位模块；编辑入口与生成物分离，防漂移由 build.sh 机器断言承担；
  固定点指纹不受影响。
- **边界 1**：拆分是**物理切割**，巨型函数（`parse_expr`/`emit_expr_c`/
  `emit_stmt_span`/`main` 等）未被内部分解——函数级重构属后续议题
  （受 128 顶层函数与 B-LS 表达力约束）。
- **边界 2**：模块内容不得含额外的头注释（字节等价要求）；模块划分语义
  仅由文件名表达。
- **边界 3**：模块顺序由数字前缀字典序决定（`cat modules/*.ls` 的展开序），
  新增模块必须带合法前缀，否则拼接序漂移会被 build.sh cmp 断言拦截。

> AI生成
