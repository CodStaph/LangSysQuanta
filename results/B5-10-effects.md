# B5-10 · effect 子句、`Cap[...]` 令牌与 `let val`

> 状态：**完成（2026-10-27）**。QEMU/TCG 全量固定点 `d5b409c4…40992`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/effects.md`](../spec/effects.md) §1–§2、[`spec/cap-context.md`](../spec/cap-context.md)、
> [`spec/modes.md`](../spec/modes.md) §2。
> 范围：`eff(...)` 子句的解析/推断/检查（`E-LS-EFFECT`）、`Cap[...]` 令牌参数
> （`E-LS-CAP`）、`let val` 冻结局部（写 → `val binding is immutable`）。

## 1. surface / 语义

```ls
fn pure_add(x: Int, y: Int) -> Int eff(pure) { return x + y; }

fn peek() -> Int eff(read) {           // read/write 是内部效果：可推断
    if arena_used() < 0 { return 1; }
    return 0;
}

fn alloc_buf(c: Cap[Alloc], n: Int) -> Int eff(alloc) {  // 边界效果：显式 + Cap
    let b: Buffer[Int] = Buffer.new[Int](n, heap);
    b.push(7);
    return b.len;
}

fn caller(c: Cap[Alloc], n: Int) -> Int eff(alloc) {     // 效果必须向上传播
    let d: Cap[Alloc] = 0;
    return alloc_buf(d, n);
}

fn frozen_local() -> Int {
    let val k = 5;        // 冻结局部（只读、可别名）
    return k + 1;
}
```

### 1.1 效果词汇与位

| 位 | 名（`eff(...)`） | 类别（`spec/effects.md` §1.1） |
|---|---|---|
| 1 | `read` | 内部（可推断） |
| 2 | `write` / `atomic` | 内部 |
| 4 | `alloc` | **边界** |
| 8 | `io` | 内部 |
| 16 | `panic` | **边界** |
| 32 | `spawn` | **边界** |
| 64 | `unsafe` / `ffi` / `hw` / `dma` / `irq` | **边界** |
| 128 | `pure` | 空集（声明的特殊值） |

`eff(pure)` 等价于"没有任何边界效果"。名字比较**首字母大小写不敏感**（`eff(Alloc)` 与
`eff(alloc)` 等价），其余字母必须一致。

### 1.2 规则

| # | 规则 | 诊断 |
|---|---|---|
| E1 | 声明了 `eff(...)` 的函数，体内产生的**边界效果**必须 ⊆ 声明 | `E-LS-EFFECT: function body has an effect not declared in its eff(...) clause` |
| E2 | 调用声明了 `eff(...)` 的 callee 时，caller 的声明必须覆盖其**边界效果**（caller 未声明 ⇒ 拒绝，强制传播） | `E-LS-EFFECT: call requires an effect the caller does not declare` |
| E3 | 声明 `alloc` / `unsafe` 需要对应的 `Cap[Alloc]` / `Cap[Unsafe]` 形参 | `E-LS-CAP: eff(...) alloc/io/unsafe needs a matching Cap[...] parameter` |
| E4 | 未知效果名 / 未知能力名 | `eff: unknown effect` / `cap: unknown capability` |
| E5 | `main` 是程序入口（拥有全部能力），不受 E1–E3 约束 | — |
| E6 | `let val x = ...` 绑定冻结局部；再赋值 / 传 `ref` 形参被拒 | `assign: val binding is immutable` / `ref argument cannot be a val binding` |

内部效果（`read`/`write`/`io`）**不要求显式声明**，但仍会累加进"当前函数产出集"
用于 E1 的检查（因此 `eff(pure)` 的函数不能 `Buffer.new`）。

### 1.3 内置效果映射

| 内置 / surface | 产出 |
|---|---|
| `read_file`、`write_file`、`argc`、`arg_len`、`arg_byte`、`write(...)` | `io`(8) |
| `Buffer.new`、`Buffer.try_new`、`arena_alloc`、`str_try_concat`、`concat_into`、`append_into`、`arena_coalesce`、`arena_compact` | `alloc`(4) |
| `buffer_push`、`b[i] = v`、`b.release()`、`drop b` | `write`(2) |
| `buffer_len/cap/get`、`b[i]`、`b.len/cap`、`arena_used/budget/stat`、`region_used/limit`、`arena_mark/rewind/free` | `read`(1) |

## 2. 实现

### 2.1 表布局（`post`）

| 区 | 用途 |
|---|---|
| `post[131700 + fi]` | 声明效果掩码；bit30 = "有 `eff(...)` 子句" |
| `post[131830 + fi]` | `Cap[...]` 形参掩码 |
| `post[131960]` | 当前函数**产出**效果（进入函数清零，内置/存储点累加） |
| `post[17008]` | 当前编译的函数是否为 `main`（入口豁免） |

### 2.2 解析

- 新增 `eff_bit(src, start, len)`：效果/能力名 → 位（首字母归一化，其余精确）；
- `emit_body` 的 `eff` 分支（原 `E-LS-UNSUPPORTED`）改为解析 `eff(a, b, ...)` 并写
  `post[131700 + ctxi[NF]] = mask | 1073741824`；`eff(pure)` 只置 bit30；
- 形参类型新增 `Cap[T]`：解析后写 `post[131830 + NF] |= bit`，形参按 Int（8 字节占位）；
- `let c: Cap[Alloc] = 0;` 局部令牌：只接受初始化器 `0`，生成 `xor rax,rax` + 存槽；
- `let val x = ...`：`let` 分支检测 `val` 前缀并置 `vimm=1`，Int 绑定的
  `var_span(..., vimm)` 打开 meta 的 val 位（B2 的赋值/借用检查自动生效）。

### 2.3 检查点

- 调用点（`parse_expr` 的 `)` 分支）：`cref[cdepth-1]` 给出 callee 下标 → 比较
  边界效果，并把 callee 的效果并入 `post[131960]`；caller 是 `main` 时跳过；
- 函数出口（`emit_body` 末尾）：`dcl != 0 && !is_main` 时比较产出与声明，再做 Cap 检查。

### 2.4 踩坑

- 清零时机：最初把 `ps[131700+NF]/[131830+NF]/[131960] = 0` 放在 `st[4] = ctxi[NF]`
  （签名之后），把刚解析的 `eff` 掩码抹掉了 → 所有声明都变成"未声明"。正确位置是
  **函数名解析之后、签名解析之前**。
- `emit_body` 的参数名是 `ps`（不是 `post`）：出口检查里误写 `post[17009]` 触发
  seed 的 `unknown array`（`post` 在该函数作用域不存在）。**`emit_stmt_span` 用 `ps`，
  `parse_expr`/`emit_stmt_list` 用 `post`**，改动前先确认作用域。
- `main` 豁免最初用"函数下标"比较（`ctxi[NF] != post[17009]`），第 0 个函数与未初始化的
  0 相撞导致豁免误开；改为显式布尔 `post[17008]`（进入函数时清零）。

## 3. 测试

新增 accept `effects.ls`（exit 7）：`eff(pure)` 纯算术、`eff(read)` 只读内置、
`eff(alloc)`+`Cap[Alloc]` 的 Buffer 分配/读写、效果经调用传播、`let val` 冻结局部
（含 `let val m = k * 2` 读取冻结值）。

新增 reject（6 个）：

| 文件 | 触发 | 诊断 |
|---|---|---|
| `eff_missing.ls` | `eff(pure)` 内 `Buffer.new` | `E-LS-EFFECT`（body） |
| `eff_call.ls` | `eff(pure)` 调用 `eff(alloc)` 的 callee | `E-LS-EFFECT`（call） |
| `cap_missing.ls` | `eff(alloc)` 但没有 `Cap[Alloc]` 形参 | `E-LS-CAP` |
| `eff_unknown.ls` | `eff(bogus)` | `eff: unknown effect` |
| `cap_unknown.ls` | `c: Cap[Bogus]` | `cap: unknown capability` |
| `val_write.ls` | `let val k = 5; k = 6;` | `val binding is immutable` |

删除已成立的 `reject/bls_eff.ls`（B1 的"未实现"负例），`run-stage1.sh` 的 unsupported
列表同步移除；新增 `PASS B5-10 effect/cap/mode diagnostics` 循环与 `effects` 正例
（解释器 + compiled 两处，`t_expect=7`）。

## 4. 兼容性

旧（B5-9）/新编译器各编译全部输入：**仅 7 个预期差异**（1 个新正例 + 6 个新负例诊断），
其余 rc / stdout / stderr / ELF 字节一致。

## 5. 验收

- `bash bootstrap/ci/run-stage1.sh`（本地解释器段）全绿，含
  `PASS B5-10 effect/cap/mode diagnostics`、`PASS interpreted stage1 determinism`；
- QEMU/TCG 全量：`PASS compiled effects -> exit 7`、`PASS fixed point: stage2 == stage3`、
  `QEMU-GUEST: RESULT=PASS`，固定点 **`d5b409c4…40992`**；
- `names_stage` 自编译输出 825907 B、源码 495297 B。

## 6. 边界

| 项 | 状态 |
|---|---|
| `eff(...)` 声明 / 内部效果推断 / 边界效果检查 | ✅ |
| 调用点效果传播（`E-LS-EFFECT`） | ✅ |
| `Cap[T]` 形参与局部令牌、`E-LS-CAP` | ✅（仅静态；运行期 8 字节占位） |
| `let val` 冻结局部 | ✅ |
| 模块级 `#[cap(...)]` / `#[boundary]` | ❌（B-LS 无模块属性） |
| `iso`/`box`/`freeze`/`recover` 的所有权与 move 语义 | ❌（留给后续；`val` 只做只读绑定） |
| `requires`/`ensures` 契约 | ❌（仍 `E-LS-UNSUPPORTED`） |
| `unsafe` 块 / `rawptr` / `Mmio` | ❌（无对应 surface） |
| 效果多态（泛型函数的 `eff` 参数化） | ❌ |

**下一步**：契约（`requires`/`ensures`）、`iso`/`box` 所有权与 move 检查、
`unsafe` 块与 `Cap[Unsafe]` 的 gate、结构化诊断。
