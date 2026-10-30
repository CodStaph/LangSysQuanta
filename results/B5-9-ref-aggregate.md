# B5-9 · `ref` 作为数组元素与泛型负载

> 状态：**完成（2026-10-26）**。QEMU/TCG 全量固定点 `7df40751…a43f2`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`results/B5-8-escape.md`](B5-8-escape.md)。
> 范围：`Array[ref[T], N]` 元素读写、`Option[ref[T]]`/`Result[ref[T], E]` 载荷
> （构造 / `match` / `?`）；生命周检查覆盖新的存储点。

## 1. surface / 语义

```ls
struct Holder { r: ref[Int] }
fn idref(ref x: Int) -> ref[Int] { return x; }

fn main() -> Int {
    let a = 5;
    let ai: Array[ref[Int], 3] = Array.zeroed();
    ai[0] = idref(a);            // 存指针；逃逸检查同 ref 字段
    let p: ref[Int] = ai[0];     // 读元素 → ref 值（不解引用）
    p = 11;                      // 写穿 a

    let o: Option[ref[Int]] = Option.Some(idref(a));
    match o { Option.Some(v) => { return v; }, Option.None => { return 0; } }
    let r: Result[ref[Int], Int] = Result.Ok(idref(a));
    return 7;
}
```

- `Array[ref[Int|Str|Slice[U8]|Slice[Int]|Buffer[Int]], N]`：元素 8 字节指针，`Array.zeroed()` 初始化为 0；
- 元素读取：`let q: ref[T] = a[i]` —— 与 B5-7 的 `Array[Int]` 元素**取地址**区分：
  元素类型已是 `ref[T]` 时读**元素里存的指针**；`Array[Int]` 仍走取地址（`kind 86`）；
- 元素写入 `a[i] = <ref 值>`：值类型必须等于元素类型；来源必须是 ref 值
  （ref 变量 / 返回 ref 的调用），不做普通变量自动取址；
- `Option[ref[T]]` / `Result[ref[T], E]`：构造、`match` 绑定（绑定变量保留 ref 类型）、
  `let q: ref[T] = r?;`（`?` 解箱得到指针）；
- `Slice` of ref 元素仍拒绝（`E-LS-UNSUPPORTED`）；泛型**函数** `f[T]` 的 ref 实参仍不特殊化
  （`f(r)` 里的 `r` 仍按解引用后的值参与泛型，见 §6）。

## 2. 生命周期（与 B5-8 一致）

| 位置 | 记录 |
|---|---|
| `let q: ref[T] = a[i]`（Array[ref] 元素） | origin 1，send = 数组声明的 `send`（**上界**精确值，存于 arr 表第 3 字段） |
| `a[i] = <ref>` | 检查 `send(ref) >= send(array)`，否则 `E-LS-REGION-ESCAPE: reference to a local escapes into a longer-lived array` |
| `Option.Some(x)` 的 payload | payload 期望类型驱动 ref 值读取（`push_var_expect` 用 `st[10]`） |
| `match` 绑定 ref payload | 变量类型 = ref 类型；寿命未知（保守） |
| `r?` 解箱 ref | `post[135802] = 1`（保守，避免残留寿命误放行） |

## 3. 实现

### 3.1 数组表

`post[4096]` 计数，条目 `4097 + i*3 = { name, meta, send }`（B5-8 是 `i*2`）。
`send` 通过全局槽 `post[135810]` 传给 `add_arr`（保持 3 参数，避免 4 参数调用的
B-LS 限制），容量 341 项（实际 ~30 项）。

### 3.2 类型与解析

- `elem_ty(elem)`：`elem >= 11` 返回 elem 本身（ref 类型），否则 1/2；
- `Array[...]` 声明接受 `ref[T]` 元素（`parse_ref_ty`），每元素 8 字节；
- 索引读（post kind 10）对 `elem == 8 || elem >= 11` 走 8 字节装载；
- 索引写语句对 `elem >= 11` 写 qword 并做逃逸检查（`post[135802]` 携带来源寿命）；
- `parse_ty` 增加 `ref[T]`（11..15），使 `Option[ref[Int]]`/`Result[ref[Int], E]` 可注解；
- `push_var_expect`：当 `st[10]`（payload 期望类型）是 ref 且变量本身是同一 ref 类型时，
  读**指针**（kind 75）而不是解引用；ctor 里 `Result.Err` 用 `st[11]`（t2）作期望；
- `match` 绑定：`bty >= 11` 时 `var_set_ty` 保留 ref 类型；
- `?`：`ty_t1` 是 ref 时把 `post[135802]` 置保守值。

### 3.3 踩坑

- 第一次实现把 `let relem = ...` 留在**内层 if 块**里，而旧分支的 `if relem != 8`
  在**另一个块** —— B2 的块作用域使 `relem` 不可见，自编译报
  `ctl: bad if expr`（AST 阶段条件解析失败，`st[0]` 停在 `{`）。
  修法：把 `relem` 定义提到两个分支的公共外层，并把单行 `if ... { x = ...; }`
  展开成多行块。
- 调试手段（值得复用）：在 `emit_stmt_list` 的 `if st[3] != 0` 处按位输出
  `sast[noff+1]` / `cend` / `st[0]`，一次编译即可定位失败的 if 及其节点范围；
  以及在 `var_add`/`scan_stmts` 结束处按位输出计数，用于排除容量溢出。

## 4. 测试

新增 accept：

- `ref_array.ls`（exit 7）：`Array[ref[Int]]` 写入/读取/写穿、ref 局部入数组、
  `Array[ref[Str]]`/`Array[ref[Buffer[Int]]]`、与 ref 字段混用；
- `ref_payload.ls`（exit 7）：`Result[ref[Int], Int]` + `?`、`Option[ref[Int]]` + `?`、
  `Option.None`、`match` 绑定 write-through。

新增 reject：

| 文件 | 触发 | 诊断 |
|---|---|---|
| `ref_array_escape.ls` | 内层块局部 ref 写入外层数组 | `E-LS-REGION-ESCAPE`（longer-lived array） |
| `ref_array_slice.ls` | `slice(Array[ref[Int]], ...)` | `E-LS-UNSUPPORTED` |
| `ref_payload_type.ls` | `Option[ref[Int]] = Option.Some(5)` | `ctor: payload type mismatch` |

`run-stage1.sh`：正例两处列表加 `ref_array`/`ref_payload`（`t_expect=7`）、
escape 循环加 `ref_array_escape`、unsupported 列表加 `ref_array_slice`、
新增 `payload` 诊断循环。

## 5. 验收

- 旧（B5-8）/新编译器各编译全部输入：**仅 5 个预期差异**（2 个新正例、3 个新负例诊断），
  其余 rc/stdout/stderr/ELF 字节一致；
- `bash bootstrap/ci/run-stage1.sh`（本地解释器段）全绿，含
  `PASS B5-8/B5-9 lifetime/escape diagnostics`、`PASS B5-9 ref payload diagnostics`、
  `PASS interpreted stage1 determinism`；
- QEMU/TCG 全量：`PASS compiled ref_array -> exit 7`、`PASS compiled ref_payload -> exit 7`、
  `PASS fixed point: stage2 == stage3`，**`7df40751…a43f2`**；
- `names_stage` 自编译 808892 B、源码 485169 B。

## 6. 边界

| 项 | 状态 |
|---|---|
| `Array[ref[T], N]` 读写 | ✅ |
| `Option[ref[T]]` / `Result[ref[T], E]` 构造/match/`?` | ✅ |
| 数组元素写入的逃逸检查 | ✅ |
| `Slice` of ref 元素 | ❌（显式拒绝） |
| 泛型函数 `f[T]` 传 ref 实参 | ❌（实参仍按解引用后的值） |
| ref 载荷参与比较/算术 | ❌（`push_binop` 仍拒绝） |
| 载荷 `ref` 的寿命传播 | 保守（`match`/`?` 得到未知寿命） |
| `mode`/cap/effect、`val`/`box` 所有权 | ❌ 未做 |

**下一步**：泛型函数 ref 实参（需要显式 turbofish 或专用语法）、`Slice[ref]`、
`mode`/cap/effect、契约、struct/`Error`、结构化诊断。
