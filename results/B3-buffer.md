# B3 · Buffer[Int] 运行态 + surface 语法 + try_new/Result

> 状态：**B3-2a + B3-2b + B3-3 + B3-4a + B3-4b 完成（2026-10-23）**。QEMU 固定点 `f3647d54…42ae`，`stage2 == stage3`。
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B3 条目、[`results/B3-arena.md`](B3-arena.md)。
> **范围**：`Buffer[Int]` 的运行态布局、surface 语法、`try_new`/`Result` 失败路径、
> `b[i]` 读取索引与 `release`/`drop` 的 LIFO 回收；region 所有权仍是后续工作。

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
- 仍是单态 `Int` 元素、无 region 所有权；release/drop 未做。

> 错误载荷用 **Int `-1`** 表示（与运行时失败码一致）。`AllocError` 命名类型尚未接入
> B-LS 类型系统，`ls-sem` 的 `Result[Buffer[T], AllocError]` 形状先以 Int 码承载。

## 2c. surface 语法（B3-4a：`b[i]` 读取索引）

```ls
let b: Buffer[Int] = Buffer.new[Int](4, heap);
b.push(11);
if b[0] != 11 { return 1; }
if b[99] != 0 - 1 { return 6; }   // 越界 -> -1
```

- `b[i]` 映射到 `buffer_get(handle, i)`（post kind 1(var)+index+60），表达式类型 `Int`；
- 索引表达式走 `parse_index`（常量、变量、四则/比较、括号、嵌套索引）；
- 越界返回 **`-1`**（与运行时 `buffer_get` 一致），不 trap；
- **只读**：`b[i] = v` 仍报
  `stage1: E-LS-UNSUPPORTED: Buffer[Int] index write is not implemented in B-LS yet`；
- 限制：`b[i]` 的索引表达式内暂不支持 `b.len`/`b.cap`（`parse_index` 不解析成员访问；
  先 `let n = b.len;` 再用 `b[n - 1]`）。

## 2d. surface 语法（B3-4b：`release` / `drop` + LIFO）

```ls
let b: Buffer[Int] = Buffer.new[Int](4, heap);
b.push(11);
if b.release() != 0 { return 2; }     // 0 = 已回收；-1 = 不是 arena 栈顶
if arena_used() != 0 { return 3; }

let d: Buffer[Int] = Buffer.new[Int](2, heap);
drop d;                               // 语句形式，状态丢弃
```

- `b.release()` → `buffer_release(handle)`（post kind 1(var)+62），返回 `0`/`-1`；
- **只做 LIFO**：仅当 `base + handle + 24 + cap*8 == current`（该分配正好是 arena 栈顶）时
  把 `current` 回退到 `base + handle`；否则返回 `-1` 且 **不改 arena**；
- `drop b;` 是同一操作的语句形式（状态丢弃），仅接受 `Buffer[Int]`，其他类型报
  `E-LS-UNSUPPORTED`；drop 后该变量被标记为 Int，后续 Buffer 操作在编译期失败
  （尚无结构化的 use-after-drop 诊断）；
- 回收不擦除 header/data，空间立即可以再次分配（`try_new`/`Buffer.new` 复用它）；
- 边界：不做通用 `free`、不处理非栈顶回收/碎片；跨变量/条件的释放顺序由调用方保证。

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
| `stage1_buffer_index.ls` | `b[i]` 读写边界、第二块 Buffer 的 push/get、`match` 绑定内索引，退出码 7 |
| `stage1_buffer_release.ls` | `b.release()` 的栈顶/非栈顶、LIFO 回退、空间复用、`drop b;`，退出码 7 |
| `reject/bls_buffer.ls` | 非 `Buffer.new` 初始化器，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_expr.ls` | `Buffer.new` 在 expression 位置，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_try.ls` | `try_new` 缺 `Result[Buffer[Int], Int]` 注解，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_index_write.ls` | `b[i] = v` 索引写入，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_drop_int.ls` | `drop` 非 Buffer 变量，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_ret/field/array.ls` | 仍 `E-LS-UNSUPPORTED` |

QEMU：

```text
PASS interpreted buffer -> ELF
PASS interpreted buffer surface -> ELF
PASS interpreted buffer try_new -> ELF
PASS interpreted buffer index -> ELF
PASS interpreted buffer release -> ELF
PASS compiled buffer stage1 -> exit 7
PASS compiled buffer surface stage1 -> exit 7
PASS compiled buffer try_new stage1 -> exit 7
PASS compiled buffer index stage1 -> exit 7
PASS compiled buffer release stage1 -> exit 7
PASS fixed point: stage2 == stage3
stage2_self = stage3_self = f3647d54…42ae
QEMU-GUEST: RESULT=PASS
```

## 6. 行为/固定点

- 107 个既有输入（81 个 `bls/tests` + 26 个 `bls/tests/reject`）与 B3-4a 编译器
  `rc`/stdout/stderr/输出 SHA-256 **全部一致**（release/drop 只增加新语法，既有程序码不变）；
  B3-4a 相对 B3-3 的 `buffer_push` ModRM 修正在此之前已单独记录（3 个 push 程序的字节变化）；
- **B3-4a 附带修正（B3-2a 遗留 bug）**：kind 59 的 `mov rsi,[rax+8]` / `mov rdi,[rax+16]` /
  `mov [rax+8],rsi` 的 ModRM 误写成 `71/79`（实际是 `[rcx+…]`），即 push 把 **arena base**
  当成 header。此前所有 push 测试的第一个 Buffer 恰好 handle = 0（base+0 = header），所以未暴露；
  B3-4a 的“第二块 Buffer 上 push”用例暴露后改为 `70/78/70`（`[rax+…]`）。语义：push 现在对
  **任意 handle** 都读写自己的 header；handle=0 的程序字节也会变（同一指令，不同 ModRM）；
- `names_stage` 自编译：`aee50d8b…6b54` **494884 B** → `f3647d54…42ae` **503179 B**；
- 新增 `stage1_buffer_index.ls` 728 B、`reject/bls_buffer_index_write.ls` 179 B、
  `stage1_buffer_release.ls` 1393 B、`reject/bls_buffer_drop_int.ls` 119 B；
- QEMU 固定点 `f3647d54…42ae`。

## 7. 边界

| 项 | 状态 |
|---|---|
| `Buffer[Int]` 运行时布局 + 内置 | ✅ B3-2a |
| `let b: Buffer[Int] = Buffer.new[Int](cap, rgn)` | ✅ B3-2b |
| `.len` / `.cap` / `.push(v)` | ✅ B3-2b |
| `Buffer.try_new` + `Result` 失败路径 | ✅ B3-3（错误码 Int `-1`） |
| `b[i]` 读取索引 | ✅ B3-4a（越界 `-1`；索引内不支持 `.len`） |
| `b[i] = v` 写入索引 | ❌ `E-LS-UNSUPPORTED`，后续补 |
| `b.release()` / `drop b;`（LIFO） | ✅ B3-4b（非栈顶 `-1`、不改 arena） |
| 通用 free / 非栈顶回收 / 碎片 | ❌ 只有 LIFO |
| use-after-release 静态检查 | ❌ `drop` 后按 Int 处理，诊断未结构化 |
| `AllocError` 命名错误类型 | ❌ 以 Int `-1` 承载 |
| 多次赋值/同一 call site 的 Result 块 | ❌ 静态块（与既有 Option/Result 构造器一致） |
| region 参数/所有权/逃逸 | ❌ 后续 |
| `release`/`drop`/LIFO 回收 | ❌ 后续 |
| 高水位/预算报告 | ❌ 后续 |

**下一步建议**：B3-4c region 所有权——Buffer header 加 `owner`（布局 v2，24→32 B），
`region R { ... }` 变成运行时帧（进入记 `current`、退出回退并检查逃逸），把 `release`
扩展为按 region 的自动回收；之后再考虑 `b[i] = v`、`AllocError` 命名类型（B4 类型表扩展）
与把 `Str +` 的 trap 换成可处理错误（R4.3）。
