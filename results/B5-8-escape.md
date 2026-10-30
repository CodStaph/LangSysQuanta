# B5-8 · `ref` 的生命周期与逃逸静态检查

> 状态：**完成（2026-10-26）**。QEMU/TCG 全量固定点 `037a1694…1166`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2（R4）、[`spec/diagnostics.md`](../spec/diagnostics.md)
> （`E-LS-REGION-ESCAPE`，Enforced）、[`results/B5-7-ref-fields.md`](B5-7-ref-fields.md)。
> 范围：`ref` 值的**来源寿命**跟踪 + 两条逃逸拒绝（返回局部、存进更长寿命的字段）。
> 不做区域推断/并查集、不做 `val`/`box` 所有权、不做泛型 ref 负载。

## 1. 语义

B5-1…B5-7 的 `ref` 一直只是"调用期借用 + 指针"，没有任何寿命检查，
所以 `return` 局部地址、把局部地址存进外层 `struct` 字段都能通过。
B5-8 给每个 `ref` 值附一个**来源寿命**，把 R4 落成三条局部可判定的规则：

| # | 规则 | 诊断 |
|---|---|---|
| R4-1 | `-> ref[T]` 的 `return x`：`x` 必须派生自 `ref` 形参（reborrow） | `E-LS-REGION-ESCAPE: cannot return a reference to a local variable` |
| R4-2 | `h.f = <ref>`：被存 `ref` 的寿命必须覆盖 `h` 的作用域 | `E-LS-REGION-ESCAPE: reference to a local escapes into a longer-lived field` |
| R4-3 | 其余流动（ref 局部、ref 实参、解引用）都在同一或更短作用域内，放行 | — |

寿命按"来源作用域结束位置（`send`）"比较，与 B2 的 Int 词法作用域用同一套
`dpos/send` 元数据；`origin` 区分"来自 `ref` 形参"（寿命无限）
与"本地变量槽地址"（寿命 = 该槽的 `send`）：

| origin | 含义 | 可 `return` | 可存外层字段 |
|---|---|---|---|
| 0 | `ref` 形参（或其转发）的 reborrow | ✅ | ✅ |
| 1 | 本地变量/数组元素/Str-Slice 槽的地址 | ❌ | 仅当 `send(ref) >= send(target)` |

```ls
struct Holder { r: ref[Int] }
fn idref(ref x: Int) -> ref[Int] { return x; }

fn main() -> Int {
    let h: Holder;
    let a = 5;
    h.r = idref(a);        // ✅ 同块：send(a) == send(h)
    let q: ref[Int] = h.r; // ✅ 字段读：寿命 = send(h)
    q = 9;

    if 1 == 1 {
        let b = 7;
        h.r = b;           // ❌ E-LS-REGION-ESCAPE（b 死在内层块）
    }
    return 7;
}

fn bad() -> ref[Int] {
    let c = 5;
    let r: ref[Int] = c;
    return r;              // ❌ E-LS-REGION-ESCAPE
}
```

## 2. 实现

### 2.1 寿命编码

- `post[136000 + vi]`（`vi` = 变量表下标，容量 4000）= `(send << 1) | origin`；
  **0 表示未知**，读作 origin 1 / send 0（最保守）——记录缺失只可能导致拒绝，
  不会导致误放行；
- `post[135802]` 是"当前调用返回的 `ref` 的寿命"通道（`parse_expr` 进入调用参数
  时置 0，`make_ref_arg` 逐个 `join`）；
- `join` 的合并律：`origin = o1 | o2`；`send = min(origin==1 ? send : ∞)`，
  `∞ = 1048575`（大于源码上限 655360）；
- struct 变量表 `post[6403 + i*4]` 改为 `off | (send << 31)`（`off` 仍是 31 位，
  读取处统一 `& 2147483647`），因为 `sv_add` 的 6 参数槽上限不允许再加一个参数。

### 2.2 写入点

| 位置 | 记录 |
|---|---|
| `ref` 形参（`emit_body`） | origin 0，send = `n`（函数体外） |
| `let r: ref[T] = 普通变量` | origin 1，send = 该变量 meta 的 `send` |
| `let r: ref[T] = ref 变量` | 复制源寿命（reborrow 保持 origin） |
| `let r: ref[T] = Str/Slice 变量` | origin 1，send = 当前块 `CUR_SEND`（**下界**，sound） |
| `let r: ref[Int] = arr[i]` | origin 1，send = 当前块 `CUR_SEND`（下界） |
| `let r: ref[T] = f(...)` | = `post[135802]`（实参寿命 `join`） |
| `let r: ref[T] = h.f`（表达式路径） | origin 1，send = `sv_send(h)` |
| `ref` 实参（`make_ref_arg`） | `join` 到 `post[135802]`：普通变量用 meta `send`，Str/Slice 槽用 `CUR_SEND`（下界），ref 变量用其记录 |

### 2.3 检查点

- `return <ref 变量>`（`emit_stmt_span`）：`post[136000 + rvi]` 为 0 或 origin 1 ⇒ 拒绝；
- `h.f = <ref>`（`emit_stmt_span` 的 `elem >= 11` 字段写）：origin 1 且
  `send(ref) < sv_send(h)` ⇒ 拒绝；表达式路径取 `post[135802]`，变量路径按来源计算。

### 2.4 可靠性（soundness 论证草稿）

1. 所有记录到的 `send` 都是来源真实 `send` 的**下界**（Str/Slice/数组槽用 `CUR_SEND`，
   它 ≤ 源变量的真实 `send`），因此 `send(ref) >= send(h)` 的放行不会误判；
2. 未知记录按最保守值处理，任何漏记只会收紧检查；
3. 调用返回的 `ref` 寿命取其 `ref` 实参的 `join`；无 `ref` 实参的 `-> ref` 函数
   自身只能返回形参，否则其函数体已被 R4-1 拒绝；
4. 因此被放行的 `ref` 在其所有使用点（同块或更内层块）都指向仍然有效的槽。

## 3. 测试

新增 accept `ref_escape_ok.ls`（exit 7）：

- `ref` 形参经 ref 局部返回（`same`）、形参 reborrow 存本地 struct（`keep`）；
- 同块 `let b` → 字段写 → 字段读 → 写穿；
- 调用返回值存同块字段（`h.r = idref(b)`）；
- `Array[Int]` 元素 ref 同块读写；
- 内层块内的短寿命 ref（ref 局部 + 字段路径）只在块内使用。

新增 reject（均须 `E-LS-REGION-ESCAPE`）：

| 文件 | 触发的规则 | 路径 |
|---|---|---|
| `ref_escape_return.ls` | R4-1 | ref 局部指向局部槽后 `return` |
| `ref_escape_field.ls` | R4-2 | 内层块局部地址 → 外层 struct 字段（普通变量路径） |
| `ref_escape_call.ls` | R4-2 | `h.r = idref(内层局部)`（调用返回寿命传播） |
| `ref_escape_field_local.ls` | R4-2 | 内层 ref 局部 → 外层 struct 字段（ref 变量路径） |

`run-stage1.sh` 已加入 `ref_escape_ok`（解释器 + compiled 两处正例与 `t_expect=7`）、
以及 `E-LS-REGION-ESCAPE` 诊断循环。

## 4. 兼容性

- 既有 132 个输入（含 reject）用旧/新 `names_stage.ls` 各编译一次：
  **只有 4 个新增 reject 结果不同**，其余 rc / stdout / stderr / ELF 字节完全一致；
- 生成的 ELF 字节不变（寿命跟踪只在编译期表中，不发射代码）；
- 编译器自身新增 1 个函数（`rl_join`），函数总数 124 → 125（seed 上限 128）；
- `names_stage` 自编译输出 803193 B、源码 480078 B；寿命表容量 4000 与变量表上限对齐
  （三处写入都带 `vi < 4000` 守卫）。

## 5. 验收

- `bash bootstrap/build.sh`：stage1 系列全部生成；
- `bash bootstrap/ci/run-stage1.sh`（Windows/MSYS）：解释器段全绿，
  含 `PASS B5-8 lifetime/escape diagnostics`、`PASS interpreted ...` 与
  `PASS interpreted stage1 self-compile -> stage2 ELF`、确定性检查；
- QEMU/TCG 全量：`PASS compiled ref_escape_ok -> exit 7`、
  `PASS fixed point: stage2 == stage3`，固定点 **`037a1694…1166`**，
  `QEMU-GUEST: RESULT=PASS`；
- `bootstrap/bls/tests/ref_*` 正例（8 个）与 reject（17 个）全部按预期。

## 6. 边界

| 项 | 状态 |
|---|---|
| `return` 局部 ref | ❌ 拒绝（`E-LS-REGION-ESCAPE`） |
| 局部 ref 存进更长寿命字段 | ❌ 拒绝（`E-LS-REGION-ESCAPE`） |
| `ref` 形参 reborrow 返回/存字段 | ✅ 放行 |
| 同块 / 内层块内的局部 ref | ✅ 放行 |
| 调用返回 ref 的寿命传播 | ✅（取 `ref` 实参的最保守值） |
| 区域推断 / 并查集 / 跨过程不动点 | ❌ 未做（本检查是局部可判定的块级近似） |
| `val`/`box`/`iso` 所有权与 `mode`/cap/effect | ❌ 未做 |
| 引用作为数组元素/泛型负载 | ❌ 未做（语法层仍拒绝） |
| `ref` 字段读出后 `send` 精度 | 取 `sv_send(h)`（保守） |

**说明**：B-LS 的变量都在静态数据段，悬垂指针在运行时不会立刻崩溃，所以这条检查
目前是**语义层**的（保证 L-Sys 侧 R4 的正确性），不是运行时防护。
真正的区域推断（`spec/semantics.md` §2 静态语义里的 `T1a`）仍是后续工作。

**下一步**：`mode`/cap/effect、契约/非空 `comptime`、struct/`Error`、结构化诊断；
或 ref 作为数组元素/泛型负载。
