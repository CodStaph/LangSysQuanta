# B5-12 · struct 作为泛型负载与内置 `Error`

> 状态：**完成（2026-10-29）**。QEMU/TCG 全量固定点 `3cefd1c6…cb23`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`00 §5.6/§6.2`](../00-LangSysQuanta-设计初稿.md)（`Error` 为紧凑 Copy enum）、
> [`results/B5-11-contracts-comptime.md`](B5-11-contracts-comptime.md)。
> 范围：struct 值作为 `Option[T]` / `Result[T, E]` 的负载（构造 + `match` 解包），
> 内置 `Error` enum（`Error.Full` / `NotFound` / `InvalidCap` / `OutOfMemory`）。

## 1. surface / 语义

```ls
struct Code { n: Int }
struct Point { x: Int, y: Int }

fn mk_code(v: Int) -> Option[Code] {
    let c: Code;
    c.n = v;
    return Option.Some(c);          // struct 负载：按字段打包
}

fn mk_point(a: Int, b: Int) -> Result[Point, Error] {
    let p: Point;
    p.x = a;
    p.y = b;
    if a < 0 { return Result.Err(Error.InvalidCap); }
    return Result.Ok(p);
}

match r {
    Result.Ok(v) => { return v.x * 10 + v.y; },   // 解包为 struct 绑定
    Result.Err(e) => { return 100 + e; }          // e: Error（紧凑 tag）
}
```

### 1.1 struct 负载

| 项 | 规则 |
|---|---|
| 类型码 | `30 + si`（`si` = struct 表下标，**`si < 70`**，即类型码 30..99） |
| 前置条件 | struct 的 `st_size` 必须是 8 的倍数（全 `Int`/`ref[...]` 字段），否则 `parse_ty` 拒绝 |
| 构造 `Some(p)` / `Ok(p)` | payload 展开为**每字段一项** `push_post(12, field_off)`，最后把 payload 类型重标为 struct 类型 |
| 负载宽度 | `st_size / 8` 槽（`kind 27` 的复制循环按此宽度）；`st[12]` 的数据块 = `8 + st_size` |
| `match` 绑定 | `Ok(v)` 里 `v` 通过 `sv_add` 变成 **struct 变量**，payload 逐槽复制到它的字段槽 |
| `Option.None` | 无 payload（宽度 0），无需特殊处理 |
| struct 参与运算 | ❌ `E-LS-UNSUPPORTED: struct value must be used through its fields`（也覆盖直接 `return p;` 之类走 binop 的路径） |
| `?` 传播 struct 负载 | ❌ 未实现（用 `match` 解包） |
| struct 作为函数参数/返回值 | ❌ 未实现（`-> Result[Point, Error]` 里的 struct 是**负载**，不是直接返回 struct） |
| struct 里嵌套 struct 字段 | ❌（现有字段类型只支持 Int/U8/ref） |
| U8 字段的 struct 负载 | ❌（对齐不足，`parse_ty` 拒绝：`let: bad Option type`） |

### 1.2 内置 `Error`

`Error` 是 L-Sys 的**紧凑 Copy 错误枚举**（`00 §5.6`：`enum` + 立即数、无分配），
B-LS 用 **类型码 20**（8 字节 tag）实现：

| 变体 | tag |
|---|---|
| `Error.Full` | 1 |
| `Error.NotFound` | 2 |
| `Error.InvalidCap` | 3 |
| `Error.OutOfMemory` | 4 |

- 出现在 `parse_ty`（`Result[T, Error]` 注解）与常量表达式（`parse_expr`/`parse_index` 的
  `Error.Variant`，两条路径都支持，因为 ctor payload 走 `parse_index`）；
- 未知变体 → `error: unknown Error variant`；
- `Error` 是 Int 语义（比较/算术可用），`Result[T, Error]` 的 `Err` payload 1 槽；
- 跨模块 `From` 注册、错误域、格式化（`00 §5.6` 的 `#[error_domain]`）未实现。

## 2. 实现

| 位置 | 改动 |
|---|---|
| `parse_ty` | `Error` → 20；末尾新增"用户 struct 名"分支 → `30 + si`（`st_find` + `st_size % 8 == 0` + `si < 70`） |
| `parse_index` | 标识符分支新增两个分支：`Error.Variant`（常量）与"期望类型是 struct（`st[10] & 255` 在 30..99）且名字是 struct 变量"→ 每字段 `push_post(12, off)` 后 `set_ty(st[10])` |
| ctor（`Option/Result`） | payload 数据块分配：`(gty & 255) >= 30` 时用 `8 + st_size(post, (gty&255) - 30)`（两处：带注解 + 推断） |
| `kind 27` emit | `if ty >= 30 { w = st_size(post, ty - 30) / 8 }`（payload 复制宽度） |
| `match`（绑定声明） | `bty >= 30` → `sv_add(... boff | (CUR_SEND << 31), bty - 30)`（struct 变量，非 var 表） |
| `match`（绑定 emit） | `bty >= 30` → 逐槽 `mov rax,[rax+8+k*8]; mov [boff+k*8],rax` |
| `push_binop` | 新增 struct 值检查：`(t&255) >= 30 && t < 100` → `E-LS-UNSUPPORTED` |

### 2.1 踩坑

- **类型码区间与泛型码冲突**：最初用 `t >= 30 && t < 300` 判定 struct，把
  `Option[Int]`（`6 | 256` = 262）与**泛型参数 T（100）**都算了进去 → 既有测试
  `stage1_str_budget` 报 "struct value must be used through its fields"。
  修正为 `(t & 255) >= 30 && t < 100`，并把 struct 索引上限压到 70（`30+si < 100`）。
- **`sv_off` 在 B5-9 已被内联删除**：新代码若调用它会 `unknown function`；
  统一写成 `(post[6403 + svi*4] & 2147483647)`。
- **`sv_add` 是 5 参数**（`post, nm, fnidx, packed, sidx`，packed 含 `send`），
  多传一个参数会 `argument count mismatch`。
- `Error.Variant` 必须同时支持 `parse_expr` 与 `parse_index` 两条路径（ctor payload 走
  `parse_index`），否则 `Result.Err(Error.Full)` 报 `slice: bad expr`。
- B-LS 的 `match` arm 仍只接受 `{ return <expr>; }`，测试不能写 `{ if ... }`。

## 3. 测试

新增 accept `struct_payload.ls`（exit 7）：

- `Option[Code]`（单字段 struct）构造 + `match` 解包 + 字段读；
- `Result[Point, Error]`（两字段 struct）构造 + 解包 + 字段算术；
- `Error.InvalidCap` / `Error.NotFound` 作为 `Err` payload，`100 + e` 得到 103/102；
- `Option.None` 路径；
- 直接使用 `Error.Full`（tag 1）。

新增 reject：

| 文件 | 诊断 |
|---|---|
| `struct_payload_u8.ls`（`Option[Mixed]`，`Mixed { a: Int, b: U8 }`） | `let: bad Option type`（对齐不足） |
| `struct_payload_expr.ls`（`p + 1`） | `slice: bad expr`（struct 值不能直接参与运算） |
| `error_unknown.ls`（`Error.Bogus`） | `error: unknown Error variant` |

`run-stage1.sh`：`struct_payload` 进入两处正例列表（`t_expect=7`），
新增 `PASS B5-12 struct payload / Error diagnostics` 循环。

## 4. 兼容性

旧（B5-11）/新编译器各编译全部输入：**仅 2 个预期差异**
（`struct_payload` 新正例 + `error_unknown` 新诊断），
另外两个 reject 与旧编译器结果**完全一致**（旧编译器本来也拒绝它们），
其余 rc / stdout / stderr / ELF 字节一致。

## 5. 验收

- `bash bootstrap/ci/run-stage1.sh`（本地解释器段）全绿，含
  `PASS B5-12 struct payload / Error diagnostics`、`PASS interpreted stage1 determinism`；
- QEMU/TCG 全量：`PASS compiled struct_payload -> exit 7`、
  `PASS fixed point: stage2 == stage3`、`QEMU-GUEST: RESULT=PASS`，新固定点 **`3cefd1c6…cb23`**；
- `names_stage` 自编译 **853261 B**、源码 **511933 B**；
- `tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 6. 边界

| 项 | 状态 |
|---|---|
| `Option[Struct]` / `Result[Struct, _]` 构造 + `match` | ✅ |
| 内置 `Error` 四个变体 | ✅ |
| `?` 传播 struct 负载 | ❌ |
| struct 作为函数参数/返回值 | ❌ |
| struct 字段为 U8 / 嵌套 struct / 引用其他 struct | ❌ |
| `Error` 的 `From` 注册、错误域（`#[error_domain]`）、格式化 | ❌ |
| `Error` 自定义变体/用户 enum 作为负载 | ❌（用户 enum 负载仍只支持标量） |

**下一步**：struct 参数/返回值与 `?` 传播、`Error` 错误域与 `From`、
用户 enum 的 struct 负载、`iso`/`box` 所有权与 move、结构化诊断。
