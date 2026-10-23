# B3 · Buffer[Int] 运行态 + surface 语法 + try_new/Result

> 状态：**B3-2a + B3-2b + B3-3 完成（2026-10-23）**。QEMU 固定点 `52cced38…688e`，`stage2 == stage3`。
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B3 条目、[`results/B3-arena.md`](B3-arena.md)。
> **范围**：`Buffer[Int]` 的运行态布局、最小 surface 语法，以及 `Buffer.try_new` 的
> `Result` 失败路径；`b[i]`、release/drop、region 所有权仍是后续工作。

## 1. 运行时布局

`Buffer.new[Int](cap, rgn)` 在 arena 中分配：

```text
header（24 B）:
  +0  data_off（相对 arena base）
  +8  len
  +16 cap
data: cap * 8 B（Int 元素）
```

- Buffer 变量在 Int 槽中存 **header 相对 arena base 的偏移**（handle）。
- `data_off = handle + 24`。
- `buffer_push` 在 `len == cap` 时返回 `-1`，不写入。
- `buffer_get` 越界返回 `-1`。
- 所有地址都由 `arena base + handle/data_off` 计算，不暴露原始指针。

## 2. surface 语法（B3-2b）

```ls
let b: Buffer[Int] = Buffer.new[Int](4, heap);
if b.len != 0 { return 1; }
if b.cap != 4 { return 2; }
b.push(11);
b.push(22);
```

- `Buffer[Int]` 只支持 `Int` 元素；
- 只支持 `let b: Buffer[Int] = Buffer.new[Int](cap, rgn);` 形式；
  `rgn` 目前只解析、不参与运行时（region 所有权留后续）；
- `b.len` / `b.cap` 分别映射到运行时 `buffer_len` / `buffer_cap`；
- `b.push(v)` 映射到运行时 `buffer_push`（满时运行时返回 `-1`，surface 暂不检查）；
- **限制**：`Buffer.new` 只能在 `Buffer[Int]` 的 typed let 初始化器中出现；
  其他地方（表达式语句、参数/返回/字段/数组元素）仍报 `E-LS-UNSUPPORTED`。
- 尚未实现 `b[i]` 索引、release/drop、region 逃逸/所有权。

## 2b. surface 语法（B3-3：`Buffer.try_new`）

```ls
let r: Result[Buffer[Int], Int] = Buffer.try_new[Int](4, heap);
match r {
    Result.Ok(b) => { return b.len + b.cap + b.push(11); },
    Result.Err(e) => { return e + 1; },
}
```

- `Buffer.try_new[Int](cap, rgn)` 复用 `Buffer.new` 的 arena helper（同一 header+data 布局），
  但把 `-1` 失败变成 `Result`：成功 `Result.Ok(handle)`，失败 `Result.Err(-1)`；
- **类型要求**：初始化器必须位于 `let r: Result[Buffer[Int], Int] = ...` 中
  （`st[9]` 注解为 kind 7、`t1 = 9`、`t2 = 1`）；否则报
  `stage1: E-LS-UNSUPPORTED: Buffer.try_new needs a Result[Buffer[Int], Int] annotation`；
- 失败时 **不推进 arena**（helper 在写入 `current` 前返回 `-1`），`arena_used()` 不变；
- `Result.Ok(b)` 的绑定记住 `Buffer[Int]`（var type 9），所以 arm 内 `b.len/.cap/.push` 可用；
- 仍是单态 `Int` 元素、无 region 所有权；`b[i]`、release/drop 未做。

> 错误载荷用 **Int `-1`** 表示（与运行时失败码一致）。`AllocError` 命名类型尚未接入
> B-LS 类型系统，`ls-sem` 的 `Result[Buffer[T], AllocError]` 形状先以 Int 码承载。

## 3. 运行时内置

| 内置 | 语义 |
|---|---|
| `buffer_new(cap)` | 分配 header+data，返回 handle 或 `-1` |
| `buffer_len(h)` / `buffer_cap(h)` | 读取 header |
| `buffer_push(h, v)` | 成功返回新 len，满时 `-1` |
| `buffer_get(h, i)` | 返回元素，越界 `-1` |

实现：

- `builtin_code` 12–16；
- post kind 56–60，`emit_expr_a` 生成 header 初始化、push/store、get/load；
- surface 的 `.len/.cap/.push` 复用这些 post kind；
- `buffer_new` 调用一个 **按需发射** 的 arena helper：
  - 只有源码真的调用 `buffer_new` 时才在函数之后发射；
  - 调用点先写占位 rel32，helper 后统一回填；
  - 因此不使用 Buffer 的既有程序生成代码逐字节不变。

## 4. 数据布局/容量

- `post` **211100**：`fd[140000..141023]` / `sast[141024..209023]`（68000 ints，容量 ~11290，
  守卫 11200）/ `ctxi[209024..211071]`。
- Int 变量表从 `9000` 移到 **`50000`**（容量 4096），避免新增编译器代码后与
  `str/name/builtin` 表碰撞。
- 源码上限 327680；`membuf[1441792]`：
  source `[0,327680)`、code `[327680,1376256)`、data `[1376256,1441792)`。
- `out` 753664 B，并检查 `filetotal > 753664`。
- buffer 调用点记录在 `ctxi[209024 + 1399]` / `+1400...`，不占用 `post[17014]` 附近；
  `Buffer.new` 与 `Buffer.try_new` 共用这份 rel32 回填表。

## 5. 测试

| 测试 | 期望 |
|---|---|
| `stage1_buffer.ls` | 运行时内置 new/len/cap/push/get，退出码 7 |
| `stage1_buffer_surface.ls` | `Buffer[Int]` + `Buffer.new` + `.len/.cap/.push`，退出码 7 |
| `stage1_buffer_try.ls` | `Buffer.try_new` 成功/失败 + `Err(-1)` + arena 不变，退出码 7 |
| `reject/bls_buffer.ls` | 非 `Buffer.new` 初始化器，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_expr.ls` | `Buffer.new` 在 expression 位置，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_try.ls` | `try_new` 缺 `Result[Buffer[Int], Int]` 注解，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_ret/field/array.ls` | 仍 `E-LS-UNSUPPORTED` |

QEMU：

```text
PASS interpreted buffer -> ELF
PASS interpreted buffer surface -> ELF
PASS interpreted buffer try_new -> ELF
PASS compiled buffer stage1 -> exit 7
PASS compiled buffer surface stage1 -> exit 7
PASS compiled buffer try_new stage1 -> exit 7
PASS fixed point: stage2 == stage3
stage2_self = stage3_self = 52cced38…688e
QEMU-GUEST: RESULT=PASS
```

## 6. 行为/固定点

- 103 个既有输入（79 个 `bls/tests` + 24 个 `bls/tests/reject`）：
  `rc`/stdout/stderr/输出 SHA-256 与 B3-2b 编译器**全部一致**
  （唯一差异是新增负例 `reject/bls_buffer_try.ls` 的诊断文本）；
- `names_stage` 自编译：`dcd670cc…46d8` **481018 B** → `52cced38…688e` **493433 B**；
- 新增 `stage1_buffer_try.ls` 842 B、`reject/bls_buffer_try.ls` 156 B；
- QEMU 固定点 `52cced38…688e`。

## 7. 边界

| 项 | 状态 |
|---|---|
| `Buffer[Int]` 运行时布局 + 内置 | ✅ B3-2a |
| `let b: Buffer[Int] = Buffer.new[Int](cap, rgn)` | ✅ B3-2b |
| `.len` / `.cap` / `.push(v)` | ✅ B3-2b |
| `Buffer.try_new` + `Result` 失败路径 | ✅ B3-3（错误码 Int `-1`） |
| `b[i]` 索引 | ❌ 可复用 `buffer_get`，后续补 |
| `AllocError` 命名错误类型 | ❌ 以 Int `-1` 承载 |
| 多次赋值/同一 call site 的 Result 块 | ❌ 静态块（与既有 Option/Result 构造器一致） |
| region 参数/所有权/逃逸 | ❌ 后续 |
| `release`/`drop`/LIFO 回收 | ❌ 后续 |
| 高水位/预算报告 | ❌ 后续 |

**下一步建议**：补 `b[i]`（映射 `buffer_get`）、release/drop 与 region 所有权；
再考虑把 `Buffer.try_new` 的错误载荷从 Int 码升级为 `AllocError` 命名类型
（需要 B4 类型表扩展）。
