# B3-2a · Buffer[Int] 运行时布局与操作

> 状态：**B3-2a 完成（2026-10-23）**。QEMU 固定点 `fa2f87ee…b102`，`stage2 == stage3`。
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B3 条目、[`results/B3-arena.md`](B3-arena.md)。
> **范围**：本轮只做 `Buffer[Int]` 的**运行时布局与内置操作**；
> 源码级 `Buffer[Int]` 类型 / `Buffer.new` / `.len` / `.push` 语法是 **B3-2b**，
> `try_new`/`Result` 失败路径是 **B3-3**。

## 1. 运行时布局

`buffer_new(cap)` 在 arena 中分配：

```text
header（24 B）:
  +0  data_off（相对 arena base）
  +8  len
  +16 cap
data: cap * 8 B（Int 元素）
```

- 返回值是 **header 相对 arena base 的偏移**（handle）；失败 `-1`。
- `data_off = handle + 24`。
- `buffer_push` 在 `len == cap` 时返回 `-1`，不写入。
- `buffer_get` 越界返回 `-1`。
- 所有地址都由 `arena base + handle/data_off` 计算，不暴露原始指针。

## 2. 内置

| 内置 | 语义 |
|---|---|
| `buffer_new(cap: Int) -> Int` | 分配 header+data，返回 handle 或 `-1` |
| `buffer_len(h: Int) -> Int` | 读取 header.len |
| `buffer_cap(h: Int) -> Int` | 读取 header.cap |
| `buffer_push(h: Int, v: Int) -> Int` | 成功返回新 len，满时 `-1` |
| `buffer_get(h: Int, i: Int) -> Int` | 返回元素，越界 `-1` |

实现：

- `builtin_code` 12–16；
- 表达式解析：`buffer_new/len/cap` 一个 Int 参数，`buffer_push/get` 两个 Int 参数；
- post kind 56–60，`emit_expr_a` 生成 header 初始化、push/store、get/load。
- `buffer_new` 调用一个 **按需发射** 的 arena 分配 helper：
  - 只有源码真的调用 `buffer_new` 时才在函数之后发射该 helper；
  - 调用点先写占位 rel32，helper 发射后统一回填；
  - 因此不使用 buffer 的既有程序生成代码逐字节不变。

## 3. 数据布局/容量调整

- `post` 扩到 **205000** ints：
  - `fd[140000..141023]`
  - `sast[141024..202951]`（61928 ints，容量 ~10200 条记录）
  - `ctxi[202952..204999]`
- Int 变量表从 `9000` 移到 **`50000`**（容量 4096 项），避免新增编译器代码后
  var 表增长与 `str/name/builtin` 表碰撞。
- `out` 缩到 **786432** B（仍大于当前 stage2 ~470 KB），并增加
  `stage1: output too large` 检查。
- buffer 调用点记录在 `ctxi[202952 + 1399]` / `+1400...`，不再占用 `post[17014]`
  附近的元数据区。

## 4. 测试

`bootstrap/bls/tests/stage1_buffer.ls`：

```ls
fn main() -> Int {
    let b = buffer_new(4);
    if b < 0 { return 1; }
    if buffer_len(b) != 0 { return 2; }
    if buffer_cap(b) != 4 { return 3; }
    if buffer_push(b, 11) != 1 { return 4; }
    if buffer_push(b, 22) != 2 { return 5; }
    if buffer_get(b, 0) != 11 { return 6; }
    if buffer_get(b, 1) != 22 { return 7; }
    if buffer_len(b) != 2 { return 8; }
    if buffer_push(b, 33) != 3 { return 9; }
    if buffer_push(b, 44) != 4 { return 10; }
    if buffer_push(b, 55) >= 0 { return 11; }
    if buffer_get(b, 4) >= 0 { return 12; }
    return 7;
}
```

覆盖：分配、len/cap、push 成功、get 读回、满时 `-1`、越界 `-1`。
只走 stage1 路径（seed 不需要知道 buffer 内置）。

QEMU：

```text
PASS interpreted arena -> ELF
PASS interpreted buffer -> ELF
PASS compiled arena stage1 -> exit 7
PASS compiled buffer stage1 -> exit 7
PASS fixed point: stage2 == stage3
stage2_self = stage3_self = fa2f87ee…b102
QEMU-GUEST: RESULT=PASS
```

## 5. 行为/固定点

- 80 个既有输入：除 `names_stage` 自编译外全部 `rc`/SHA-256/stderr/stdout 一致；
- `names_stage` 自编译：`3766b8f0…d2d8` 444982 B → `5e9deae…100` 470349 B；
- 新增 `stage1_buffer.ls` 产出 2876 B ELF；
- QEMU 固定点 `fa2f87ee…b102`。

## 6. 边界

| 项 | 状态 |
|---|---|
| `Buffer[Int]` 运行时布局（header+arena data） | ✅ |
| `buffer_new/len/cap/push/get` 内置 | ✅ |
| 源码级 `Buffer[Int]` 类型 / `Buffer.new` / `.len` / `.push` | ❌ B3-2b |
| `Buffer.try_new` + `Result` 失败路径 | ❌ B3-3 |
| region 参数、所有权、release/drop、LIFO 回收 | ❌ 后续 |
| 从 arena 构造 `Slice` / 原始指针 load/store | ❌ 后续 |
| 高水位统计、预算报告 | ❌ 后续 |

**下一步建议**：B3-2b 把 surface 语法映射到本轮内置
（`let b: Buffer[Int] = Buffer.new[Int](cap, heap); b.push(v); b.len; b.cap`），
再接 B3-3 的 `try_new`/`Result`。
