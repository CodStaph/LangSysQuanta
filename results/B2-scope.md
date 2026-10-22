# B2 · region 名称检查 + `val` + 词法作用域（检查级）

> 状态：**B2-1 + B2-2 完成（2026-10-23）**。QEMU 固定点 `ced96a3c…61289`，`stage2 == stage3`。
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B2 条目、[`spec/bls.md`](../spec/bls.md)。
> 注意：B2 仍是分步的；本轮完成 **region 活跃名称检查、`val` 参数、Int 变量词法作用域、
> `val` 绑定不可变检查**。`ref`、Slice/Str/Array 的词法作用域、region 生命周期/逃逸仍待 B3/后续。

## 1. B2-1 交付

### region 活跃名称检查

- `emit_stmt_list` 的 `K_REGION` 分支有 enter/exit 两个 phase；
- 用 `rname[64]`（名称起始字节）、`rlen[64]`（名称长度）、`ctxi[RDEPTH=1287]` 维护活跃栈；
- 进入 region 时对**当前活跃**名称逐字节比较；重复则
  `region: duplicate active region name` + `return 4`；
- 不把 region 名称插入 name table，合法程序生成代码不变。

### `val` 参数模式

- `preflight` 不再统一拒绝 `val`/`ref`；
- 参数解析识别 `val name: T`，按普通按值参数处理；
- 只有 `val` 后跟标识符才当模式，因此参数名本身叫 `val` 仍合法；
- `ref` 仍报 `E-LS-UNSUPPORTED`。

## 2. B2-2 交付：Int 变量词法作用域 + `val` 不可变

### var 表 meta 布局

Int 变量表仍是 `post[9000]` 计数 + `9001 + i*4` 四元组，但第 4 个 int 现在是：

```text
bits 0..7    type（1 Int / 2 U8 / 3 Str / 4 Slice[U8] / 5 Slice[Int] / 100 generic T）
bit 8        val（不可变绑定）
bits 10..29  dpos（声明位置）
bits 30..49  send（作用域结束位置，字节偏移）
```

- `var_span(dpos, send, val)` 打包；`var_set_ty` 只改低 8 位；
- `var_find(post, nm, fn, pos)` 在当前 `pos` 可见的声明中选 **dpos 最大** 的一个，
  因此内层 `let` 正确遮蔽外层；
- `var_find_any` 保留旧「任意同名声明」查找，只用于复用已存在的栈槽；
- 赋值时如果 `var_find` 找不到可见声明：`assign: unknown variable`；
- 赋值目标是 `val` 绑定时：`assign: val binding is immutable`。

### 作用域结束位置

- `emit_stmt_list` 的 block frame 在 enter 时保存旧 `ctxi[CUR_SEND]`，并把
  `CUR_SEND` 设为该 block 的 `sast.end`；exit 时恢复；
- 叶子/`let` 用当前 `CUR_SEND` 作为 `send`；参数用 `send = n`（函数内可见）；
- 条件表达式在父 block 的 `CUR_SEND` 下解析，因此 then/else 里的 `let` 不会
  泄漏到条件或外层。

### 遮蔽与栈槽

- 若 `let` 的名字在当前位置已有**活跃**绑定，分配新栈槽，保证外层值不被覆盖；
- 若没有活跃绑定但存在同名陈旧声明，复用旧槽（尽量保持既有数据布局）；
- match 绑定按同样规则处理（活跃则新槽）；
- 这样 `let x = 1; { let x = 2; }` 退出 block 后外层 `x` 仍为 1。

## 3. 测试

| 测试 | 期望 |
|---|---|
| `stage1_val_param.ls` | 解释器 + 编译产物通过，退出码 7 |
| `stage1_scope_shadow.ls` | 内层 `let` 遮蔽外层，退出码 7 |
| `stage1_val_shadow.ls` | `let` 遮蔽 `val` 参数，赋值合法，退出码 3 |
| `reject/bls_region_dup.ls` | 重复活跃 region 名，编译失败 |
| `reject/bls_scope_escape.ls` | block 外使用局部 `let`，编译失败 |
| `reject/bls_val_assign.ls` | 给 `val` 参数赋值，失败并输出 `val binding is immutable` |
| `reject/bls_ref.ls` | 仍 `E-LS-UNSUPPORTED` |

QEMU 全量：

```text
PASS interpreted val parameter -> ELF
PASS interpreted lexical scope -> ELF
PASS B-LS lexical scope and val diagnostics
PASS B-LS duplicate region diagnostic
PASS compiled val parameter stage1 -> exit 7
PASS compiled stage1_scope_shadow stage1 -> exit 7
PASS compiled stage1_val_shadow stage1 -> exit 3
PASS fixed point: stage2 == stage3
stage2_self = stage3_self = ced96a3c…61289
QEMU-GUEST: RESULT=PASS
```

## 4. 行为/固定点

- 80 个既有输入（73 tests + 7 src）中，除 `names_stage` 自编译外全部
  `rc`/SHA-256/stderr/stdout 逐字节一致；
- `names_stage` 自编译：`147c1a94…82e54` (431329 B) → `3a5cc218…c452` (433865 B)；
- 新增测试：scope_shadow 1522 B、val_shadow 1391 B、val_param 1386 B；
- QEMU 固定点 `ced96a3c…61289`。

## 5. 边界

| 项 | 状态 |
|---|---|
| region 活跃重名检查 | ✅ |
| `val` 参数按值绑定 | ✅ |
| Int `let` 词法作用域/遮蔽/越界 | ✅ |
| `val` 绑定不可变（赋值检查） | ✅ |
| `ref` 参数 | ❌ 仍拒绝；需要引用/指针代码生成 |
| Slice/Str/Array 变量的词法作用域 | ❌ 这些表仍是函数级；后续统一 |
| match 绑定跨 arm 的精确作用域 | 🟡 绑定会按 span 加入 Int var 表，但 arm 边界未单独建模 |
| region 分配生命周期/逃逸/所有权 | ❌ 需要 Buffer/arena（B3） |
| `val`/`ref` 字段、mode 类型、`val[Self]` | ❌ |
| 新诊断的稳定码 | 🟡 `region: duplicate active region name` / `assign: val binding is immutable` / `assign: unknown variable` 仍是文本诊断 |

**下一步建议**：B3-1（arena/Buffer 布局与 `try_new` 失败路径），或先把 Slice/Str/Array
变量表统一到同一 scope 模型。`ref` 需要引用代码生成，建议在 B3 之后单开。
