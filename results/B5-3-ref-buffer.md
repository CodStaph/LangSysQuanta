# B5-3 · `ref Buffer` 与 ref Slice 索引

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `f5c774e4…a774`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`results/B5-1-ref.md`](B5-1-ref.md)、
> [`results/B5-2-ref-views.md`](B5-2-ref-views.md)。
> 范围：`ref b: Buffer[Int]`（通过句柄读写）、`ref Slice` 索引；
> 不做 Str/Slice ref 写入、引用类型值/字段/生命周期分析。

## 1. surface / 语义

```ls
fn fill(ref b: Buffer[Int]) -> Int {
    b.push(1);
    b[0] = 7;
    return b.len + b[0] + b.cap;
}
fn at(ref s: Slice[U8]) -> Int { return s[1]; }
```

- `ref b: Buffer[Int]`：形参是指向 caller 的 **handle 槽** 的指针；
  callee 内 `b.len/.cap/.push/b[i]/b[i]=v/b.release()` 都通过该指针读取 handle，
  再执行现有 Buffer 运行时操作；
- `ref s: Slice[U8]` / `ref s: Slice[Int]`：在 B5-2 只读视图基础上增加 **索引读取**
  `s[i]`；
- `ref Str` 仍只读，不支持 `s[i]` / 写入；
- 不支持 `ref Buffer` 的 `drop b;`（drop 仍要求直接 Buffer 变量）；
- `b.release()` 通过 ref 调用会释放 handle 槽；caller 的 handle 值变为失效
  （后续使用得到 `-1`）。

## 2. 实现

### 2.1 类型/变量

| 类型码 | 含义 | 读取方式 |
|---|---|---|
| 11 | `Ref Int` | `1`+`76` |
| 12 | `Ref Str` | `77`（3 槽） |
| 13 | `Ref Slice[U8]` | `78`（2 槽） |
| 14 | `Ref Slice[Int]` | `78`（2 槽） |
| 15 | `Ref Buffer[Int]` | `1`+`76`（解引用 handle 槽） |

- `var_is_buffer` 把类型 15 视为 Buffer；
- 新增 `push_handle`：普通 Buffer 直接读 handle；`Ref Buffer` 先解引用指针再得到 handle；
  Buffer surface 的 `.len/.cap/.push/b[i]/b[i]=/release` 统一走它；
- `push_var` 对类型 15 生成 `1`+`76`（与 Int ref 同型），因此可作为 ref 实参转发。

### 2.2 调用点

`scan_refmask` 的 `ref_type_code` 增加 `Buffer[Int] -> 15`；`make_ref_arg`：

- 普通 Buffer 变量（kind 1、类型 9）→ `kind 74`（取 handle 槽地址），type 15；
- `Ref Buffer` 变量（kind 1+76、类型 15）→ `kind 75`（直接传指针），type 15；
- 类型不匹配（如 Str 传给 ref Buffer）继续拒绝。

### 2.3 callee

- 形参 `ref b: Buffer[Int]` 只占 1 个参数槽，保存 handle 槽地址；
- `fpelem=9`、`fval=2`，变量类型设为 15；
- Buffer 操作通过 `push_handle` 解引用，仍调用既有 `buffer_len/cap/push/get/set/release`。

### 2.4 ref Slice 索引

新增 post kind：

| kind | 语义 |
|---|---|
| 83 | `Ref Slice[U8][i]`：pop index，`rdx=[slot]`（指针），`rdx=[rdx]`（base），`movzx eax,[rdx+rcx]` |
| 84 | `Ref Slice[Int][i]`：同上，`mov rax,[rdx+rcx*8]` |

`[` 分支在普通 Array/Slice 查找之前先检查变量类型 13/14；
匹配时解析 index 后生成 kind 83/84，否则走原路径。

### 2.5 容量

源码已接近上限（456307 B / 458752），本轮没有再扩大布局；自编译输出 767983 B，
`out` 900000、code 786432 仍有余量。下一轮若继续加编译器代码，需先扩 source/code。

## 3. 测试

- `ref_buffer.ls`（exit 7）：`ref Buffer` 的 `push/b[i]=/len/[i]/cap`，写回 caller；
- `ref_slice_index.ls`（exit 7）：`ref Slice[U8][i]` 与 `ref Slice[Int][i]`；
- 负例：
  - `ref_buffer_mismatch.ls`：Str 传给 ref Buffer；
  - `ref_assign_str.ls`：写 ref Str；
  - 保留 `ref_alias`/`ref_val`/`ref_literal`/`ref_mismatch`/`ref_generic`；
- `ref_str_slice.ls` 继续覆盖 Str/Slice 只读视图与 `.len`。

`run-stage1.sh` 已加入 `ref_buffer`/`ref_slice_index` 正例（exit 7）与上述负例。

## 4. 验收

- QEMU/TCG 全量 `run-stage1.sh`：
  `PASS compiled ref_buffer -> exit 7`、`PASS compiled ref_slice_index -> exit 7`、
  `PASS fixed point: stage2 == stage3`；
- 固定点 **`f5c774e4…a774`**，`QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 767983 B、源码 456307 B；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 5. 边界

| 项 | 状态 |
|---|---|
| `ref Buffer[Int]` 读写（Buffer 操作） | ✅ |
| `ref Slice[U8]/[Int]` 索引读取 | ✅ |
| 通过 ref 写 Str/Slice | ❌ |
| `ref Str[i]` | ❌ |
| `drop` ref Buffer | ❌（仍只接受直接 Buffer 变量） |
| 引用类型值/字段/返回 | ❌ |
| 生命周期/逃逸分析 | ❌（借用只在调用期存在；无保存路径） |
| `ref Buffer.release()` | 允许，但 caller 的 handle 变为失效 |

**下一步**：Str/Slice ref 写入、引用类型值/字段/返回、生命周期/逃逸分析；
之后 `mode`/cap/effect、契约/非空 `comptime`、struct/`Error`、结构化诊断。
