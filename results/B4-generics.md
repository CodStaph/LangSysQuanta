# B4 · 多类型参数泛型与约束

> 状态：**完成（2026-10-25）**。QEMU/TCG 固定点 `57d6c38a…bf22`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`results/B0.3c-ast.md`](B0.3c-ast.md)、[`results/R4.7-handle-quota.md`](R4.7-handle-quota.md)。
> 范围：**两个类型参数**的泛型函数/enum、`A: Bound` 内联约束与 `where` 约束、
> 调用点类型统一与约束转发；不做泛型 struct、>2 参数、trait/关联类型。

## 1. surface

```ls
enum Either[A, B] { Left(A), Right(B), Neither }

fn first[A, B](a: A, b: B) -> A { return a; }
fn larger[T: Ord](a: T, b: T) -> T { if a > b { return a; } return b; }
fn min_where[A](a: A, b: A) -> A where A: Ord { ... }
```

- 参数列表 `[A, B]`：最多 **2** 个；名字任意；一个函数/enum 内不得重名。
- 约束可写成 `A: Ord`（内联）或 `where A: Ord, B: Eq`；
- 支持的约束：`Ord`（比较）、`Eq`（相等）、`Num`（`+ - * / %` 与比较）、
  `Add`（`+`，允许 `Str`）；
- 约束只接受这四种；其他名字 → `E-LS-UNSUPPORTED`；
- generic enum 上的约束暂不支持（实例不携带约束检查）。

## 2. 编译期实现

### 2.1 签名预扫描（`scan_sigs`）

在 `scan_funcs` 之后、`check_decls` 之前新增一遍 `scan_sigs`，对**泛型函数**记录：

```text
post[132000 + fi*8 + i]  = 第 i 个参数的类型（1 Int/2 U8/3 Str/4 Slice[U8]/
                           5 Slice[Int]/9 Buffer/100+gi 泛型参数）
post[133024 + fi*8 + gi] = 约束码（0 无，1 Ord，2 Eq，3 Num，4 Add）
post[134048 + fi*8 + gi] = 泛型参数名 id
post[135072 + fi*4 + 0]  = 泛型参数个数（0..2）
post[135072 + fi*4 + 1]  = 返回的泛型参数码（100/101，或 0）
post[135072 + fi*4 + 2]  = 返回的具体类型（parse_ty 码，或 0）
post[135584 + fi]        = 函数名 id（仅泛型函数）
post[135900]             = 当前声明的泛型参数个数（临时）
post[135901 + i]         = 当前声明的泛型参数名 id（临时）
post[135899]             = 当前函数下标（约束检查用）
```

这样**先声明后调用/先调用后声明**都可以；`post[120000+nid]` 也提前写入泛型标记，
使 forward call 在 emit 之前就能正确装箱。

### 2.2 解析

- `parse_ty` 增加当前泛型表：标识符命中 `post[135901+i]` 时返回 `100+i`；
  其余仍按 Int/U8/Str/Slice/Buffer 解析；
- `gen_peek` 做“看一眼再回退”，供参数/返回类型解析使用；
- 函数/enum 的 `[A, B]` 由 `scan_generic_list` 统一解析并填表；
- `where` 子句在 `scan_sigs` 中记录、在 `emit_body` 中跳过（bounds 已记录）。

### 2.3 调用点统一

`parse_expr` 为每次调用记录每个实参的类型（`ctypes`，按调用深度/参数位置索引）：

1. 按声明参数顺序，把 `100+i` 与实参类型做统一：同一 `i` 必须得到同一具体类型；
   具体参数（Int/Str/Slice）必须匹配（Int/U8 互通）；
2. 检查每个泛型参数的约束：`Ord/Eq` 接受 Int/U8/Str/Slice；
   `Num` 只接受 Int/U8；`Add` 接受 Int/U8/Str；
3. 若实参类型本身是**当前函数的泛型参数**（`100+i`），则检查当前函数对该参数的约束
   是否覆盖被调用函数的约束（`Ord ⊇ Eq`、`Num ⊇ Eq/Ord/Add`、`Add ⊇ Eq`），
   即约束转发；
4. 返回类型：返回 `100+i` 时取统一后的实际类型；返回具体类型时用 `scan_sigs` 记录的类型。

运行期仍使用已有的**统一装箱 + typecode 分派**：每个泛型值是一个 box 指针，函数体按
box 头 typecode 执行 `+`/比较等。两处必要的 ABI 修正：

- 泛型转发（`max_forward[T: Ord]` 调 `larger(a,b)`）时参数已经是 box，
  `box_last_arg` 不再二次装箱；
- 泛型函数返回泛型参数时，只有调用点需要**具体类型**才用 kind 140 解箱；
  在另一个泛型函数内部转发时保持 box（kind 160），避免“解箱后再当 box 用”。

### 2.4 约束与函数体

`push_binop` 在泛型参数上做 `A: Bound` 检查：

| 约束 | 允许的运算 |
|---|---|
| `Ord` | `== != < <= > >=` |
| `Eq` | `== !=` |
| `Num` | `+ - * / %` 与比较（及逻辑/位运算） |
| `Add` | `+` 与比较 |

不满足时在声明处报 `E-LS-UNSUPPORTED: generic bound does not permit this operation`。
无约束的泛型函数保持原有行为（运行时 typecode 分派）。

## 3. 踩坑：6 个参数槽上限

B-LS 只有 **6 个参数槽**（每个 `Slice` 占 2 槽）。第一版实现里：

- `parse_ty(src, st, n, post)` = 7 槽；
- `scan_generic_list(src, st, n, post, fi)` = 8 槽。

`seed --run` 解释执行时看不出问题，但 seed 编译出的 stage2 一启动就 SIGSEGV
（参数槽越界破坏栈/数据）。修复：去掉多余的 `n`（统一用 `st[1]`）和 `fi`
（用 `post[135899]`），两者都降到 **6 槽**；`scan_sigs`/`gen_peek` 也为 6 槽。
这是本轮最重要的 ABI 约束回归。

## 4. 测试

新增：

- `gen_multi.ls`（exit 7）：`first[A,B] -> A`、`second[A,B] -> B`、`Either[A,B]`
  的 `Left/Right/Neither`、`T: Ord`、`max_forward[T: Ord]` 约束转发、
  `T: Add`（Int/Str）、`T: Num`；
- `gen_multi_where.ls`（exit 7）：`where A: Ord` / `where A: Eq`；
- reject：
  - `gen_multi_mismatch.ls`：同一 `A` 的实参类型不一致；
  - `gen_multi_bound_call.ls`：`T: Add` 用 Slice 调用；
  - `gen_multi_bound.ls`：`T: Eq` 函数体内使用 `<`；
  - `gen_bound_unknown.ls`：未知约束名；
  - `gen_enum_bound.ls`：generic enum 上的约束；
  - `bls_generic_multi.ls`/`bls_enum_multi.ls` 改为 **3 个参数**（仍不支持）。

`run-stage1.sh` 的正/负例列表已加入上述测试；`gen_multi`/`gen_multi_where`
的 guest 期望退出码为 7。

## 5. 验收

- 128 个既有输入：除两个 reject 的**预期诊断文本**（改成 3 参数）外，
  rc/stdout/stderr 全部一致；
- 新增 B4 正例/负例在 seed 解释器、编译后的 stage1、stage2 上均通过；
- QEMU/TCG 全量 `run-stage1.sh`：`PASS fixed point: stage2 == stage3`，
  固定点 **`57d6c38a…bf22`**，`QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 737069 B；源码 437307 B。

## 6. 边界

| 项 | 状态 |
|---|---|
| 泛型参数个数 | 最多 **2** |
| 泛型函数/enum | ✅ |
| 泛型 struct | ❌（仍 `E-LS-UNSUPPORTED`） |
| 约束 | `Ord/Eq/Num/Add`；不支持 trait/关联类型 |
| enum 参数约束 | ❌ |
| 显式 turbofish `f[Int,Str](...)` | ❌（当前靠实参推断） |
| 无实参的泛型推断 | ❌（无法推断时编译失败） |
| 泛型 enum 变体多载荷 | ❌（每个变体最多一个载荷） |
| 运行期 | 统一装箱 + typecode 分派；转发不再二次装箱 |

**下一步**：`ref`/完整所有权/生命周期；`mode`/cap/effect；契约/非空 `comptime`；
struct 负载/`Error`；结构化诊断/fix-it；表达式两阶段 IR（B0.3d）。
