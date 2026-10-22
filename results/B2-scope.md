# B2-1 · region 名称检查 + `val` 参数模式（检查级）

> 状态：**B2-1 完成（2026-10-23）**。QEMU 固定点 `2d1417cc…4b074`，`stage2 == stage3`。
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B2 条目、[`spec/bls.md`](../spec/bls.md)。
> 注意：B2 是分步的；本轮只交付 **region 活跃名称检查** 与 **`val` 参数的按值绑定**，
> `ref`、变量词法作用域、region 生命周期/逃逸仍待 B2-2/B3。

## 1. 交付内容

### region 活跃名称检查

- `emit_stmt_list` 的 `K_REGION` 分支现在有 enter/exit 两个 phase；
- 用 `rname[64]` 存名称起始字节、`ck[64]` 存名称长度、`ctxi[RDEPTH]` 存嵌套深度；
- 进入 region 时，对**当前活跃** region 名称做逐字节比较；重复则：
  `region: duplicate active region name` + `return 4`；
- 退出时 `RDEPTH--`；
- 不把 region 名称插入 name table（避免改变既有程序的 name ID / 输出），因此
  合法程序的生成代码不变。

### `val` 参数模式

- `preflight` 不再统一拒绝 `val`/`ref`；
- 参数解析识别 `val name: T`，跳过 `val` 后按普通按值参数处理；
- `val` 后必须跟标识符才按模式处理，因此参数名本身叫 `val` 仍然合法
  （`names_stage.ls` 的 `push_post(..., val: Int)` 不受影响）；
- `ref` 仍报 `stage1: E-LS-UNSUPPORTED: ref parameters are not implemented in B-LS yet`。

## 2. 测试

| 测试 | 期望 |
|---|---|
| `bootstrap/bls/tests/stage1_val_param.ls` | 解释器 + 编译产物均通过，退出码 7 |
| `bootstrap/bls/tests/reject/bls_region_dup.ls` | 编译失败，输出 `duplicate active region name` |
| `bootstrap/bls/tests/reject/bls_ref.ls` | 仍失败，输出 `E-LS-UNSUPPORTED`（ref 未实现） |
| `stage1_region_empty/let/body` | 仍通过；合法 region 生成代码不变 |

QEMU 全量：

```text
PASS interpreted val parameter -> ELF
PASS B-LS duplicate region diagnostic
PASS compiled val parameter stage1 -> exit 7
PASS fixed point: stage2 == stage3
stage2_self = stage3_self = 2d1417cc…4b074
QEMU-GUEST: RESULT=PASS
```

## 3. 行为/固定点

- 80 个既有输入（73 tests + 7 src）中，除 `names_stage` 自编译外全部
  `rc`/SHA-256/stderr/stdout 逐字节一致；
- `names_stage` 自编译：`06c25bac…9604` (430588 B) → `147c1a94…82e54` (431329 B)；
- 新增 `stage1_val_param.ls` 产出 1386 B ELF；
- QEMU 固定点 `2d1417cc…4b074`。

## 4. 边界（B2-2/B3）

| 项 | 状态 |
|---|---|
| region 活跃重名检查 | ✅ 本轮 |
| `val` 参数按值绑定 | ✅ 本轮（语法 + 按值） |
| `val` 不可变性检查 | ❌ 未做；需要变量级 mode 标记 + 词法作用域 |
| `ref` 参数 | ❌ 仍拒绝；需要引用/指针代码生成 |
| `let` 词法作用域/遮蔽/越界使用 | ❌ 变量表仍是函数级（`var_find` 不检查 scope） |
| region 分配生命周期/逃逸/所有权 | ❌ 需要 Buffer/arena（B3） |
| `val`/`ref` 字段、mode 类型、`val[Self]` | ❌ 未做 |
| 新诊断的稳定码 | 🟡 当前是 `region: duplicate active region name`；后续可提升为专用 REGION-DUP 诊断码 |

**下一步建议**：B2-2 先做「`let` 词法作用域 + `val` 不可变检查」（给 var 表加 scope/mode，
`var_find` 按当前 scope 查找），再做 B3。不要在没有作用域的情况下单独加 `val` 不可变位，
否则遮蔽会误报。
