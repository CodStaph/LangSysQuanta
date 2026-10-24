# B5-2 · `ref` 扩展到 Str/Slice、转发与视图

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `cb6a7dba…b43f`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`results/B5-1-ref.md`](B5-1-ref.md)。
> 范围：`ref Int`（沿用 B5-1）、`ref Str`、`ref Slice[U8]`、`ref Slice[Int]` 的**调用期视图**；
> `ref` 转发；不做 `ref Buffer`、引用类型值/字段、Str/Slice ref 的写入或索引。

## 1. surface / 语义

```ls
fn slen(ref s: Str) -> Int { return s.len; }
fn fwd(ref s: Str) -> Int { return slen(s); }       // ref 转发
fn vlen(ref s: Slice[U8]) -> Int { return s.len; }
fn ilen(ref s: Slice[Int]) -> Int { return s.len; }

fn inc(ref x: Int) -> Int { x = x + 1; return x; }
```

- `ref x: Int`：可读可写（B5-1）；
- `ref s: Str` / `ref s: Slice[T]`：**只读视图**；
  - 读取得到正常的 `Str`/`Slice` 值，可用于 `.len`、作为函数实参、`write`、
    `str_try_concat`/`concat_into` 等接受 Str/Slice 的位置；
  - 不支持通过 ref 写入 Str/Slice，也不支持 `ref_slice[i]` 索引（B5-2 边界）；
- `ref` 转发：`ref` 形参可以作为另一个 `ref` 形参的实参，
  直接传递其指针（不再取地址/不再二次借用）；
- 实参仍必须是单个可变变量，或同类型的 ref 形参。

## 2. 实现

### 2.1 类型/变量编码

| 变量类型码 | 含义 | 表达式 post kind |
|---|---|---|
| 11 | `Ref Int` | `1` + `76`（读值） |
| 12 | `Ref Str` | `77`（base/byte_len/char_len） |
| 13 | `Ref Slice[U8]` | `78`（base/len） |
| 14 | `Ref Slice[Int]` | `78`（base/len） |

新增 post kind：

| kind | 语义 |
|---|---|
| 75 | 读 ref 变量的指针（转发） |
| 77 | 读 `Ref Str` 的 3 个槽（指针 + 0/8/16） |
| 78 | 读 `Ref Slice` 的 2 个槽（指针 + 0/8） |
| 79 / 80 | `Ref Str` / `Ref Slice` 的 `.len`（+16 / +8） |
| 81 | 取普通 `Str` 槽的地址（ref 实参） |
| 82 | 取普通 `Slice` 槽的地址（ref 实参） |

### 2.2 调用点

`scan_refmask` 现在除了 ref 位，还记录每个参数的 ref 类型码
（`post[130600+fi*8+pc]`：11/12/13/14）。调用点按源码名 span 找到函数下标后，
把期望类型放进 `post[130700]`，由 `make_ref_arg` 处理：

- 普通 `Int` 变量 → `kind 74`（取址）；
- 普通 `Str` → `kind 81`（取 Str 槽地址）；
- 普通 `Slice[U8/Int]` → `kind 82`（取 Slice 槽地址）；
- `Ref Str` → `kind 75`（直接传指针）；
- `Ref Slice` → `kind 75`；
- `Ref Int` → `kind 1` + `76` 组合转成 `kind 75`（去掉解引用）；
- 同一调用内重复借用同一变量仍拒绝；
- 类型不匹配（如 `Str` ref 传 Int）拒绝。

### 2.3 callee

- `ref x: Int` / `ref s: Str` / `ref s: Slice[T]` 的形参都只占 **1 个参数槽**，
  存指针；
- `fpelem` 仍记录原类型（0/2/1/8），`fval=2` 表示 ref；
- 形参变量类型按 11/12/13/14 设置；
- `push_var` 统一生成对应的值读取 IR（Int 解引用；Str/Slice 读指针 + 槽）。

### 2.4 容量修复

B5 代码使 stage1 自编译的语句 AST 超过旧守卫（15000 节点）。布局调整为：

```text
sast:  post[141024..241023]   (100000 ints, 守卫 16400)
ctxi:  post[241024..243135]   (2112 ints)
patch: post[248000..360000)   (56000 relocations)
post:  360000 ints
```

自编译输出 761739 B，源码 452659 B；仍在 `out` 900000 / code 786432 内。

## 3. 测试

新增：

- `ref_int.ls`：B5-1 读写 + **ref 转发**（`outer(ref)` → `inner(ref)`）；
- `ref_str_slice.ls`（exit 7）：
  - `slen(ref Str)`、`fwd(ref Str)` → `slen(s)`；
  - `vlen(ref Slice[U8])`、`ilen(ref Slice[Int])`；
- reject：
  - `ref_buffer.ls`：`ref Buffer[Int]`（不支持）；
  - `ref_mismatch.ls`：`ref Str` 传 Int；
  - `ref_assign_str.ls`：通过 ref 写 Str；
  - 保留 `ref_alias`/`ref_val`/`ref_literal`/`ref_generic`。

`run-stage1.sh` 已加入 `ref_int`/`ref_str_slice` 正例与上述负例；
`ref_buffer`/`ref_generic` 走 `E-LS-UNSUPPORTED` 检查。

## 4. 验收

- QEMU/TCG 全量 `run-stage1.sh`：
  `PASS compiled ref_int -> exit 7`、`PASS compiled ref_str_slice -> exit 7`、
  `PASS fixed point: stage2 == stage3`；
- 固定点 **`cb6a7dba…b43f`**，`QEMU-GUEST: RESULT=PASS`；
- 128 个既有输入：除历史 B4 reject 的预期诊断文本外全部一致；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 5. 边界

| 项 | 状态 |
|---|---|
| `ref Int` 读写 | ✅ |
| `ref Str` 读（`.len`/传参/转发） | ✅ |
| `ref Slice[U8]` / `ref Slice[Int]` 读（`.len`/传参/转发） | ✅ |
| 通过 ref 写 Str/Slice | ❌ |
| `ref_slice[i]` 索引 | ❌ |
| `ref Buffer[Int]` | ❌ |
| 引用类型值/字段/返回 | ❌（ref 只存在于形参） |
| 生命周期/逃逸分析 | 不需要：借用只在调用期间；无保存路径 |
| 跨语句别名 | 由“引用不可保存”间接排除；同一调用重复借用仍拒绝 |

**下一步（B5-3）**：`ref Buffer`、Str/Slice ref 写入与索引、真正的引用类型值与
借用/生命周期/逃逸检查；之后再 `mode`/cap/effect。
