# B5-11 · 契约（`requires`/`ensures`）与非空 `comptime`

> 状态：**完成（2026-10-28）**。QEMU/TCG 全量固定点 `2285bc9d…7cbe0`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/langSysQuanta.ebnf`](../spec/langSysQuanta.ebnf) §7（`contract`/`eff_clause`）、
> [`spec/effects.md`](../spec/effects.md) §1、[`spec/elaboration.md`](../spec/elaboration.md) E17、
> [`results/B5-10-effects.md`](B5-10-effects.md)。
> 范围：`requires`（入口断言）、`ensures`（每个 `return` 前断言，`result` 为返回值）、
> `comptime { <const-expr>; }` 编译期常量折叠与编译期断言。

## 1. surface / 语义

```ls
fn pos(x: Int) -> Int requires x > 0 {
    return x + 1;                    // 入口断言 x > 0
}

fn div_ok(a: Int, b: Int) -> Int requires b != 0 ensures result >= 0 {
    return a / b;                    // 返回前断言 (a/b) >= 0
}

fn bump(n: Int) -> Int ensures result > n {
    if n > 0 { return n + 1; }       // 每个 return 都检查
    return 1;
}

fn main() -> Int {
    comptime { }                     // 空块：接受
    comptime { 2 * 3 + 1 == 7; }     // 编译期折叠；结果为 0 即断言失败
    return 7;
}
```

### 1.1 契约

| 项 | 规则 |
|---|---|
| 语法 | `requires <expr>` / `ensures <expr>`，位于返回类型之后、函数体 `{` 之前（可与其他子句共存） |
| `requires` | 断言在**函数入口**（形参已就绪）；为假 → `exit(73)` |
| `ensures` | 断言在**每个 `return` 之前**；`result` 指代返回值；为假 → `exit(74)` |
| 求值 | 表达式按普通 B-LS 表达式解析；必须在当前函数作用域可解析 |
| 条件类型 | 视为 Int（0 = 假，非 0 = 真） |
| `&&`/`||` | 按非零判断（短路求值） |
| `=> expr`（EBNF 的可选形式） | ❌ 未实现（`ensures Ok(v) => ...` 留给后续） |
| `old(expr)` | ❌ 未实现 |
| ref 返回值 | `ensures` 只在非 ref 返回路径插入（ref 值不做条件求值） |

`exit(73)` = `requires` 违反、`exit(74)` = `ensures` 违反（测试用固定码）。

### 1.2 非空 comptime

| 形态 | 语义 |
|---|---|
| `comptime { }` | 空块，无代码（原有行为） |
| `comptime { <const-expr>; }` | 编译期折叠；结果**必须非 0**（否则 `E-LS-COMPTIME: comptime assertion failed`） |
| 常量表达式 | 字面量 + `+ - * / %`、比较 `== != < <= > >=`、`&& ||`、位运算 `| ^ & << >>`、一元 `-` |
| 非常量（变量/调用/索引/字符串） | `E-LS-COMPTIME: comptime block needs a constant expression` |
| 块内其他语句（`let` 等） | 仍 `E-LS-UNSUPPORTED: comptime blocks with non-empty bodies ...` |
| `comptime <expr>` 表达式形式 | ❌ 未实现（只做语句块形式） |
| fuel / 递归 | 无（表达式无递归，节点数受限于源码） |

## 2. 实现

### 2.1 契约

- 签名解析：`requires`/`ensures` 分支（原 `E-LS-UNSUPPORTED`）改为**扫描表达式 span**：
  从关键字之后到下一个子句关键字（`requires`/`ensures`/`eff`/`where`）或函数体 `{` 为止，
  跳过字符串字面量与 `//`/`/* */` 之外的普通字符；
- `post[135741]/[135742]` = requires span，`post[135743]/[135744]` = ensures span，
  `post[135745]` = "正在解析 ensures" 标志，`post[135746]` = `result` 数据槽；
  每函数入口（函数名解析后、签名前）清零；
- 有 `ensures` 时在 body 前分配 8 字节 `result` 槽；
- `requires`：body 前求值 + `test eax,eax; jne ok; mov eax,60; mov edi,73; syscall; ok:`；
- `ensures`：`return` 的值先 `push rax` + 存入 `result` 槽 → 求值 ensures →
  断言（`exit 74`）→ `pop rax` 恢复返回值；
- `result`：`parse_expr` 在标识符分支前拦截源码 `result`（且 `post[135745] != 0`），
  生成新 post kind **87**（`mov rax,[rip+slot]` + push）；
- 污染防护：求值契约表达式会改写 `st[0]/st[1]`，两处都保存/恢复（`st[1] = n`）。

### 2.2 comptime

- `emit_stmt_list` 的 `K_COMPTIME` 分支：空块沿用原逻辑；非空块取块内 span，
  用 `parse_index1` 生成 IR，再**在编译期用局部值栈折叠**（`cstk[32]`）：
  - `kind 0` = 字面量 → 压栈；
  - `kind 2` = 运算符（1..18 + 20 一元负）→ 弹栈计算；
  - 其他 kind（变量/索引/调用）→ 失败；
  - 除法/取模除数为 0 → 失败；
  - 栈最终必须恰好 1 项；结果为 0 → 编译期断言失败。

### 2.3 容量调整（重要）

B5-11 新增的代码把语句 AST 推到 `stmts: too many statements`（16400 上限）：

| 项 | 旧 | 新 |
|---|---|---|
| `sast` 区 | `post[141024..241023]`（100000 ints，16400 节点守卫） | `post[141024..245023]`（104000 ints，**17200** 节点守卫） |
| `ctxi` | `post[241024..243135]` | `post[245024..247135]` |
| 数据重定位表 | `post[248000..360000)` | 不变（`247136 < 248000`，余 864） |

### 2.4 踩坑

- 契约表达式求值会改写 `st[0]/st[1]`：只恢复 `st[0]` 导致**下一个函数的签名解析失败**
  （`slice: bad name`）；两处都必须恢复 `st[1] = n`。
- `emit_stmt_list` 的 `K_COMPTIME` 分支替换时误删了分支开头的 `if kind == K_COMPTIME {`
  与结尾的 `sp = sp - 1;`，需要逐行核对块结构（B-LS 的花括号不像 C 那样容错）。
- 折叠代码里 `%%` 是 Python 模板的转义残留，B-LS 的取模是单个 `%`。

## 3. 测试

新增 accept：

- `contracts.ls`（exit 7）：`requires x > 0`、`requires b != 0 ensures result >= 0`、
  两个 `return` 的 `ensures result > n`、4 个 comptime 常量断言（含空块）；
- `contract_requires.ls`（运行期 **exit 73**）：`pos(0)` 违反 requires；
- `contract_ensures.ls`（运行期 **exit 74**）：`ensures result > n` 但返回 `n`。

新增 reject：

| 文件 | 诊断 |
|---|---|
| `comptime_nonconst.ls`（`comptime { x + 1 == 4; }`） | `E-LS-COMPTIME: comptime block needs a constant expression` |
| `comptime_assert.ls`（`comptime { 2 + 2 == 5; }`） | `E-LS-COMPTIME: comptime assertion failed` |

删除已成立的 `reject/bls_requires.ls`、`reject/bls_ensures.ls`（B1 的"未实现"负例），
`run-stage1.sh` 的 unsupported 列表同步移除；新增 `PASS B5-11 contract/comptime diagnostics`
循环；`contracts`/`contract_requires`/`contract_ensures` 进入两处正例列表，
Linux 段的 `t_expect` 映射为 7/73/74（Windows 段只编译）。

## 4. 兼容性

旧（B5-10）/新编译器各编译全部输入：**仅 5 个预期差异**（3 个新正例 + 2 个新负例诊断），
其余 rc / stdout / stderr / ELF 字节一致。

## 5. 验收

- `bash bootstrap/ci/run-stage1.sh`（本地解释器段）全绿，含
  `PASS B5-11 contract/comptime diagnostics`、`PASS interpreted stage1 determinism`；
- QEMU/TCG 全量：`PASS compiled contracts -> exit 7`、
  `PASS compiled contract_requires -> exit 73`、`PASS compiled contract_ensures -> exit 74`、
  `PASS fixed point: stage2 == stage3`，新固定点 **`2285bc9d…7cbe0`**，`QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 **839134 B**、源码 **504610 B**；
- `tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 6. 边界

| 项 | 状态 |
|---|---|
| `requires` / `ensures`（无条件形式） | ✅ |
| `ensures` 中的 `result` | ✅（非 ref 返回） |
| comptime 常量折叠 + 编译期断言 | ✅（语句块形式） |
| `requires`/`ensures` 的 `=> expr` 形式、`old(expr)` | ❌ |
| 契约的静态证明（调用点验证 `requires`） | ❌（只做运行期断言） |
| `comptime <expr>` 表达式形式、`comptime fn` | ❌ |
| comptime fuel / `Eval`/`Rewrite` 效果 | ❌（常量折叠不消耗 fuel） |
| 契约错误消息/位置 | ❌（统一 `exit 73/74`，无结构化诊断） |

**下一步**：契约的 `=>` 形式与 `old`、调用点静态检查（把 `requires` 变成 caller 义务）、
`comptime` 表达式形式与 fuel、`iso`/`box` 所有权与 move、结构化诊断。
