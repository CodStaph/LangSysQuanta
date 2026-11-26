# stage1 源码 · `val` 关键字碰撞缝隙（EBNF 对齐修复）

> 状态：**完成（2026-11-26）**。
> 起因：用户要求机器验证"所写代码符合语言语法规范"，用 `tools/ebnf-parse`（冻结 EBNF v2.3
> 的 Earley 识别器）检验 `bootstrap/src/*.ls` 时发现：**6/7 个自举源文件 FAIL**。
> 该缝隙与 R2.6 无关（原始 HEAD 同样 FAIL），属 stage1 语料与冻结文法的既有缝隙。

## 1. 缝隙本质

- 冻结 EBNF（`spec/langSysQuanta.ebnf` v2.3）把 **`val` 列为保留关键字**（不可变绑定修饰符，
  `param = [mut|ref|val] ident : ty`）。
- 但 6 个 B-LS 自举源文件把 `val` 用作**普通标识符**：
  - 参数名：`fn var_span(dpos: Int, send: Int, val: Int)`、`fn push_post(..., val: Int)`
  - 局部变量名：`let val = post[cst[9] * 2 + 1];`（emit_expr 系列大量使用）
- **seed 为何能接受**：seed 的 B-LS 前端用「`val` 后跟标识符才当修饰符」的宽松规则
  （`val: Int` 中 `val` 后是 `:`，被放行为普通参数名）——形成解释器可解析、
  冻结文法不接受的**词法层缝隙**。

## 2. 修复（词边界改名 `val` → `pval`）

- 脚本化词边界替换（`\bval\b` → `pval`），**跳过字符串字面量与 `//` 注释**——
  诊断文本 `"val binding is immutable"` / `"ref argument cannot be a val binding"` 有
  reject 测试 grep 依赖，必须保留；注释同理保留。
- `pval` 经查未与任何现有标识符冲突（0 处占用）。
- 实际改名 **220 处代码级标识符**：

| 文件 | 改名数 |
|---|---|
| `names_stage.ls` | 85 |
| `arith.ls` | 25 |
| `calc.ls` | 25 |
| `funcs.ls` | 26 |
| `slice_stage.ls` | 29 |
| `struct_stage.ls` | 30 |

- git diff：6 文件 208 行、插入=删除（纯标识符变化，无换行污染）。
- 剩余 `\bval\b` 12 处均在注释/诊断字符串内（核验过），代码级清零。
- `var_span`/`push_post` 调用点为位置传参，参数名改动不影响调用。

## 3. 验证

| 项 | 结果 |
|---|---|
| `python tools/ebnf-parse`（7 个 src） | **7/7 PASS**（修复前 6/7 FAIL） |
| `python tools/ebnf-parse`（115 个 bls/tests） | 115/115 PASS（修复前亦全 PASS，语料本就干净） |
| stage1 编译路径回归（31 项） | **0 失败** |
| 解释器路径回归（run-interp 核心 14 项，含 unicode=42/slice_params=177） | **0 失败** |
| 旧编译器源各自编译对应测试（arith/calc/funcs/slice_stage/struct_stage） | 全 rc=0 |
| 诊断字符串 | 未改动（reject 测试依赖完整） |

## 4. 遗留与约束

- **QEMU 自举固定点**：`names_stage.ls` 是自举源码，本次改名改变编译产物字节，
  `stage2 == stage3` 需重跑（与 R2.6-A 的待验项**合并为一次 QEMU 全量**）；收敛性不受影响
  （固定点验证的是同一源码两次编译一致，改名后仍收敛）。
- `names_stage.ls` 顶层函数 128/128 触顶不受影响（纯改名，无结构变化）。
- 修改前已按纪律为 6 个源文件建 `.swp` 备份（`bootstrap/src/*.ls.swp`），
  确认无误后经用户同意再清理。
- CI 覆盖面启示：`ebnf-parse` 目前只进 `tests/syntax`，不扫 `bootstrap/src`——
  建议后续把它加进 CI 对 `bootstrap/src/*.ls` 的例行扫描（本次发现的根因）。

> AI生成