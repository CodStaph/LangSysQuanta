# B3 · Buffer[Int] 运行态 + surface 语法 + try_new/Result

> 状态：**B3-2a/2b/3/4a/4b/4c + B3-5a/5b/5c 完成（2026-10-23）**。QEMU 固定点 `9808e322…b666`，`stage2 == stage3`。
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B3 条目、[`results/B3-arena.md`](B3-arena.md)。
> **范围**：`Buffer[Int]` 的运行态布局（owner 字段）、surface 语法、`try_new`/`Result`、
> `b[i]`、`release`/`drop` 的 LIFO 回收与 **region 所有权**（region 退出自动回收）。

## 1. 运行时布局

`Buffer.new[Int](cap, rgn)` 在 arena 中分配：

```text
header（32 B，布局 v2）:
  +0  data_off（相对 arena base）
  +8  len
  +16 cap
  +24 owner（所属 region 的运行时序号；0 = 根作用域）
data: cap * 8 B（Int 元素）
```

- Buffer 变量在 Int 槽中存 **header 相对 arena base 的偏移**（handle）。
- `data_off = handle + 32`；分配大小 = `32 + cap*8`。
- `owner` 由分配点（`emit_expr_c` 的 kind 56/61）从 runtime region 栈读取：
  `depth == 0` 时为 0，否则为 `seq[depth-1]`（每次 region 进入生成新序号）。
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
- **写入**：`b[i] = v;` 映射到 `buffer_set`（B3-5a，见 2f 节）；
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
- **owner 必须匹配**：`header.owner == 当前 region 序号`（根作用域为 0），否则返回 `-1`；
- **只做 LIFO**：仅当 `base + handle + 32 + cap*8 == current`（该分配正好是 arena 栈顶）时
  把 `current` 回退到 `base + handle`；否则返回 `-1` 且 **不改 arena**；
- `drop b;` 是同一操作的语句形式（状态丢弃），仅接受 `Buffer[Int]`，其他类型报
  `E-LS-UNSUPPORTED`；drop 后该变量被标记为 Int，后续 Buffer 操作在编译期失败
  （尚无结构化的 use-after-drop 诊断）；
- 回收不擦除 header/data，空间立即可以再次分配（`try_new`/`Buffer.new` 复用它）；
- 边界：不做通用 `free`、不处理非栈顶回收/碎片；跨变量/条件的释放顺序由调用方保证。

## 2e. region 所有权（B3-4c）

```ls
region R {
    let b: Buffer[Int] = Buffer.new[Int](4, R);
    b.push(11);
    if b.len != 1 { return 2; }    // B3-5c：-> Int 函数会在返回前 unwind region 帧
}
if arena_used() != 0 { return 4; } // region 退出时自动回收
```

- `region` 现在是**运行时帧**：进入时把 `current` 记入 `mark[depth]` 并生成新 `seq[depth]`、
  `depth += 1`；退出时 `depth -= 1` 并把 `current` 回退到 `mark[depth]`（自动释放该 region 的
  全部分配，嵌套 region 天然 LIFO）。
- 运行时状态（`post[17013..17016]`）：`depth`、`next`、`mark[64]`、`seq[64]`（共 1040 B）；
  只在源码出现 `region`/`Buffer`/`buffer_*` 时才在 data 段分配，其他程序的字节输出不变。
- `owner` 检查使**跨 region 释放**失败：根作用域的 Buffer 在 region 内 `release`/`drop` 返回
  `-1`；region 内分配在 region 退出后也无法再释放（句柄已随词法作用域失效）。
- 逃逸防护（编译期，`E-LS-UNSUPPORTED`）：
  - `Buffer[Int]` 变量赋值（`outer = inner;`）——句柄复制可能把 region 内分配带出去；
  - `return` 出现在 region 内且函数返回类型不是 `Int`（B3-5c：`-> Int` 会在返回前
    按编译期深度 unroll `depth--; current = mark[depth]`，见 2f 节）；
  - `break`/`continue` 跳出 region 块——同样会跳过退出。
  因此 region 的进入/退出（以及 `-> Int` 的提前返回）在运行时总是配对的。
- 边界：`Buffer.new/try_new` 的 region 参数仍只解析、不参与运行时（owner 由词法嵌套决定，
  不校验名字）；`arena_reset()` 不感知 region（在 region 内调用会让退出回跳到旧 mark，
  属未定义用法）；跨块 `break`/`continue` 仍拒绝；函数递归本就受 B-LS 全局槽限制，不支持。

## 2f. B3-5：索引写入、`AllocError`、region 内 return

```ls
b[0] = 99;                                      // B3-5a：bounds 检查，越界忽略（-1）
let r: Result[Buffer[Int], AllocError] = ...;   // B3-5b：命名错误类型
fn f(n: Int) -> Int { region R { ... return x; } } // B3-5c：返回前 unwind region 帧
```

- **B3-5a `b[i] = v`**：语句形式发射 `kind 1(var)+index+value+63`（`buffer_set`）；运行时
  `0 <= i < len` 时写入 `data_off + i*8` 并返回 `0`，否则返回 `-1` 且不写入（无符号比较，
  负索引同样失败）；值/索引必须是 `Int`/`U8`（否则 `buffer: index must be Int` /
  `buffer: value must be Int`）。仍不支持在表达式位置使用写入结果。
- **B3-5b `AllocError`**：`parse_ty` 新增类型码 **10**（`AllocError`，8 字节载荷），
  `Buffer.try_new` 的注解接受 `Result[Buffer[Int], Int]` 或 `Result[Buffer[Int], AllocError]`；
  错误码仍是运行时 `-1`（`AllocError` 目前没有构造器/命名常量，可用数值比较）。
- **B3-5c region 内 `return`**：函数返回类型为 `-> Int`（`fret_ty == 1`）时，`return` 在
  region 内会先按**编译期 region 深度** unroll `depth -= 1; current = mark[depth]`
  （最多 64 次），再 `ret`——既回收 region 分配，又保留调用方的 region 帧（跨函数嵌套正确）。
  返回类型可能携带 Buffer（`Option/Result[Buffer…]`、泛型等）时仍报
  `E-LS-UNSUPPORTED`，避免 unwind 后返回悬空句柄。

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
| `stage1_buffer_index.ls` | `b[i]` 读/写边界、第二块 Buffer 的 push/get、`match` 绑定内索引，退出码 7 |
| `stage1_buffer_release.ls` | `b.release()` 的栈顶/非栈顶、LIFO 回退、空间复用、`drop b;`，退出码 7 |
| `stage1_buffer_region.ls` | region 退出自动回收、嵌套/跨函数帧、跨 region 释放 `-1`、显式 release，退出码 7 |
| `stage1_region_return.ls` | region 内 `return` unwind 帧 + 释放分配（`-> Int`），退出码 7 |
| `reject/bls_buffer.ls` | 非 `Buffer.new` 初始化器，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_expr.ls` | `Buffer.new` 在 expression 位置，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_try.ls` | `try_new` 缺 `Result[Buffer[Int], Int|AllocError]` 注解，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_index_value.ls` | `b[i] = <Str>`，`buffer: value must be Int` |
| `reject/bls_buffer_drop_int.ls` | `drop` 非 Buffer 变量，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_region_escape.ls` | Buffer 句柄赋值（逃逸），`E-LS-UNSUPPORTED` |
| `reject/bls_region_return.ls` | region 内 `return` 且返回类型携带 Buffer，`E-LS-UNSUPPORTED` |
| `reject/bls_region_break.ls` | `break` 跳出 region 块，`E-LS-UNSUPPORTED` |
| `reject/bls_buffer_ret/field/array.ls` | 仍 `E-LS-UNSUPPORTED` |

QEMU：

```text
PASS interpreted buffer -> ELF
PASS interpreted buffer surface -> ELF
PASS interpreted buffer try_new -> ELF
PASS interpreted buffer index -> ELF
PASS interpreted buffer release -> ELF
PASS interpreted buffer region -> ELF
PASS interpreted region return -> ELF
PASS compiled buffer stage1 -> exit 7
PASS compiled buffer surface stage1 -> exit 7
PASS compiled buffer try_new stage1 -> exit 7
PASS compiled buffer index stage1 -> exit 7
PASS compiled buffer release stage1 -> exit 7
PASS compiled buffer region stage1 -> exit 7
PASS compiled region return stage1 -> exit 7
PASS fixed point: stage2 == stage3
stage2_self = stage3_self = 9808e322…b666
QEMU-GUEST: RESULT=PASS
```

## 6. 行为/固定点

- 109 个既有输入（82 个 `bls/tests` + 27 个 `bls/tests/reject`）与 B3-4c 编译器：**106 个
  `rc`/stdout/stderr/输出 SHA-256 完全一致**；只有 3 个预期内的变化，全部来自新语法本身：
  `stage1_buffer_index.ls`（新写入）、`stage1_buffer_try.ls`（改用 `AllocError`，旧编译器
  不接受）、`reject/bls_buffer_try.ls`（诊断文本扩展）。B3-4a 的 `buffer_push` ModRM 修正
  与 B3-4c 的 header v2/region 帧仍是此前单独记录的历史项；
- **B3-4a 附带修正（B3-2a 遗留 bug）**：kind 59 的 `mov rsi,[rax+8]` / `mov rdi,[rax+16]` /
  `mov [rax+8],rsi` 的 ModRM 误写成 `71/79`（实际是 `[rcx+…]`），即 push 把 **arena base**
  当成 header。此前所有 push 测试的第一个 Buffer 恰好 handle = 0（base+0 = header），所以未暴露；
  B3-4a 的“第二块 Buffer 上 push”用例暴露后改为 `70/78/70`（`[rax+…]`）。语义：push 现在对
  **任意 handle** 都读写自己的 header；handle=0 的程序字节也会变（同一指令，不同 ModRM）；
- `names_stage` 自编译：`eec5cd82…42b1` **522312 B** → `9808e322…b666` **533184 B**；
- 新增 `stage1_region_return.ls` 483 B、`reject/bls_buffer_index_value.ls` 180 B；
  `reject/bls_region_return.ls` 改为携带 Buffer 的返回类型（277 B）；
- QEMU 固定点 `9808e322…b666`。

## 7. 边界

| 项 | 状态 |
|---|---|
| `Buffer[Int]` 运行时布局 + 内置 | ✅ B3-2a |
| `let b: Buffer[Int] = Buffer.new[Int](cap, rgn)` | ✅ B3-2b |
| `.len` / `.cap` / `.push(v)` | ✅ B3-2b |
| `Buffer.try_new` + `Result` 失败路径 | ✅ B3-3（错误码 Int `-1`） |
| `b[i]` 读取索引 | ✅ B3-4a（越界 `-1`；索引内不支持 `.len`） |
| `b[i] = v` 写入索引 | ✅ B3-5a（`0 <= i < len`，越界 `-1` 且不写；仅语句形式） |
| `b.release()` / `drop b;`（owner） | ✅ B3-4b/B3-4c + R4.6（栈顶回退；非栈顶进空闲表并可复用） |
| region 所有权（自动回收、嵌套/跨函数帧） | ✅ B3-4c |
| region 内 `return`（`-> Int`） | ✅ B3-5c（返回前 unroll unwind region 帧） |
| region 内 `return`（返回类型携带 Buffer） | ❌ `E-LS-UNSUPPORTED`（避免悬空句柄） |
| 跳出 region 的 `break`/`continue` | ❌ `E-LS-UNSUPPORTED`（无 unwinding） |
| `AllocError` 命名错误类型 | ✅ B3-5b（类型码 10；错误码仍是 `-1`，无构造器/常量） |
| `Buffer.new` 的 region 名字校验 | ❌ 只解析；owner 由词法嵌套决定 |
| 段回收 / 通用 free / 碎片合并 / 压缩 | ✅ R4.4/R4.6（`arena_mark`/`rewind`、任意顺序 `release`、空洞复用与合并）；R4.7 增加 Buffer 句柄表与 `arena_compact()` 移动压缩（Str/裸块 pinned），release 成功使 handle 失效（重复释放 `-1`）。见 [`results/R4.6-free.md`](R4.6-free.md)、[`results/R4.7-handle-quota.md`](R4.7-handle-quota.md) |
| use-after-release 静态检查 | ❌ `drop` 后按 Int 处理，诊断未结构化 |
| 多次赋值/同一 call site 的 Result 块 | ❌ 静态块（与既有 Option/Result 构造器一致） |
| `Str +` / `concat_into` 预算不足 | ✅ R4.3（`str_try_concat`/`Result`；见 [`results/R4.3-str-failure.md`](R4.3-str-failure.md)） |
| 高水位/预算报告 | ✅ R4.2（`arena_stat`；见 [`results/R4.2-r4.4-arena.md`](R4.2-r4.4-arena.md)） |

**下一步建议**：B3 主体已收口，**R4.3 已完成**（`Str +`/`concat_into` 预算不足改为
`Result`，见 [`results/R4.3-str-failure.md`](R4.3-str-failure.md)）。剩余可选项：
`Buffer.new` 的 region 名字校验、use-after-release 结构化诊断、同一 call site 的 Result 块动态化；
跨线的下一项是 **R4.2/R4.4**（真实 arena 预算/对齐统一、按 region 预算与回收），
之后进入 **B4** 多参数泛型/约束。
