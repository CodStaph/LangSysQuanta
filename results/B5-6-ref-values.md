# B5-6 · 引用类型值、引用返回与字段边界

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `4daa1cc6…7193`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`results/B5-5-ref-slice-write.md`](B5-5-ref-slice-write.md)。
> 范围：`ref[T]` 局部值（`let r: ref[T] = ...`）、`ref[T]` 返回类型与 return；
> **ref struct 字段仍显式拒绝**；不做生命周期/逃逸静态分析。

## 1. surface

```ls
fn idref(ref x: Int) -> ref[Int] { return x; }
fn sref(ref s: Str) -> ref[Str] { return s; }

fn main() -> Int {
    let a = 5;
    let r: ref[Int] = idref(a);   // ref 返回值绑定到 ref 局部
    r = 9;                        // 写穿 a
    let q: ref[Str] = s;          // 普通 Str 变量取 ref
    q = "xy";                     // 写穿 s
    ...
}
```

- `let r: ref[T] = 来源;`，T = `Int` / `Str` / `Slice[U8]` / `Slice[Int]` / `Buffer[Int]`；
  来源可以是：
  - 普通变量（取地址：Int/Buffer → 变量槽；Str → Str 槽；Slice → Slice 槽）；
  - ref 变量（复制指针）；
  - 返回 `ref[T]` 的函数调用；
- `fn f(...) -> ref[T] { return x; }`：`x` 必须是与返回类型一致的 ref 变量；
- ref 局部可读写/索引/Buffer 操作，行为与 ref 形参一致；
- **struct 中 `field: ref[T]` 仍拒绝**（`E-LS-UNSUPPORTED: ref struct fields ...`）。

## 2. 实现

### 2.1 类型解析

新增 `parse_ref_ty(src, st, n)`：

```text
ref [ Int | Str | Slice[U8] | Slice[Int] | Buffer[Int] ]
  → 11 / 12 / 13 / 14 / 15
```

用于 typed let 与函数返回类型。

### 2.2 ref 局部

typed let 的 `ref[` 分支：

1. 解析类型 `rt`；
2. RHS：
   - 普通变量：按 base 类型取地址（kind 74/81/82）；
   - ref 变量：kind 75（复制指针）；
   - 函数调用/表达式：`parse_expr`，要求表达式类型 == `rt`；
3. `mov [ref_slot], rax` 保存指针；
4. `var_add` 类型设为 11/12/13/14/15。

`push_var` 已支持这些类型，因此 ref 局部的读/写/索引/Buffer 操作直接复用 B5-1…B5-5。

### 2.3 ref 返回

- 返回类型解析新增 `ref[` 分支，`fret_ty` 设为 11..15；
- return 分支在 `fret_ty` 为 ref 时：
  - 只接受**单个 ref 变量**（ref 形参或 ref 局部）；
  - 类型必须与返回类型一致；
  - 生成 kind 75（取指针）后 `ret`；
  - region 内 return ref 仍拒绝；
- 调用点按普通返回类型处理（指针在 rax），可绑定到 `let r: ref[T] = f(...)`。

### 2.4 ref 字段

struct 字段解析在 Int/U8 之前检测 `ref`，直接报：

```text
E-LS-UNSUPPORTED: ref struct fields are not implemented in B-LS yet
```

字段需要把指针放进聚合布局并处理逃逸/生命周期，B5-6 不做。

## 3. 测试

新增：

- `ref_values.ls`（exit 7）：
  - `idref`/`sref`/`vref`/`bref` 返回 ref；
  - `let r: ref[Int] = idref(a)`，写回 caller；
  - `let r: ref[Int] = x`（ref 形参）局部；
  - `let q: ref[Str] = s`、`q = "xy"`；
  - `let rv: ref[Slice[U8]] = v`、`rv[i] = v`；
  - `let rb: ref[Buffer[Int]] = bref(b)`、`rb.push(3)`；
- reject：
  - `ref_field.ls`：struct ref 字段；
  - `ref_local_type.ls`：ref 局部来源类型不匹配；
  - `ref_return_type.ls`：ref 返回类型不匹配；
  - 保留既有 ref 负例。

`run-stage1.sh` 已加入 `ref_values` 正例（exit 7）、`ref_field` 的
`E-LS-UNSUPPORTED` 检查与新的 ref 负例。

## 4. 验收

- QEMU/TCG 全量 `run-stage1.sh`：
  `PASS compiled ref_values -> exit 7`、`PASS fixed point: stage2 == stage3`；
- 固定点 **`4daa1cc6…7193`**，`QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 **791305 B**、源码 **470301 B**；
- 128 个既有输入：除历史 B4 reject 的预期诊断文本外全部一致；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 5. 边界

| 项 | 状态 |
|---|---|
| `let r: ref[T] = 变量/ref/调用` | ✅ |
| `-> ref[T]` + return ref 变量 | ✅ |
| ref 局部读写/索引/Buffer 操作 | ✅ |
| ref struct 字段 | ❌（显式拒绝） |
| 生命周期/逃逸静态分析 | ❌ |
| 引用类型作为数组元素/泛型负载 | ❌ |
| `ref` 重新绑定（`r = other_ref`） | ❌（赋值被解释为写穿目标） |

**说明**：B-LS 的局部变量/数组存储是静态数据段，B5-6 的 ref 返回不会产生宿主级悬垂；
但这不是 L-Sys 的生命周期证明。真正的借用检查仍属于后续工作。

**下一步**：引用类型字段/数组元素、生命周期/逃逸静态检查；或 `mode`/cap/effect、
契约/非空 `comptime`、struct/`Error`、结构化诊断。
