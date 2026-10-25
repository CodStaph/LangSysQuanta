# B5-5 · `ref Slice` 赋值与索引写入

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `ed085bde…6eb8`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`results/B5-4-ref-write.md`](B5-4-ref-write.md)。
> 范围：`ref Slice[U8/Int]` 的 **描述符赋值**（`s = t`）与 **索引写入**（`s[i] = v`）；
> 不做引用类型值/字段/返回、生命周期/逃逸分析、`ref Buffer` 赋值。

## 1. surface / 语义

```ls
fn retarget(ref s: Slice[U8], t: Slice[U8]) -> Int {
    s = t;                 // 写穿 caller 的 Slice (base,len)
    return s.len;
}
fn set0(ref s: Slice[U8], v: Int) -> Int {
    s[1] = v;              // 写穿 caller 指向的数组元素
    return s[1];
}
```

- `ref s: Slice[U8]` / `ref s: Slice[Int]` 的赋值要求 RHS 为同元素类型的 Slice；
- 索引写入 `s[i] = v`：
  - 索引必须是 `Int`/`U8`；
  - 值必须是 `Int`/`U8`（不检查范围，与普通 Slice 索引语义一致）；
  - U8 写 `byte`，Int 写 8 字节；
- caller 的 Slice 描述符 / 底层 Array 内容随之改变；
- 仍拒绝：引用类型值/字段/返回、生命周期/逃逸分析、`ref Buffer` 赋值、`ref Str[i] = v`。

## 2. 实现

### 2.1 描述符赋值

赋值分支对 `vty == 13/14`：

1. 解析 RHS（`parse_expr`），要求类型 4（U8）或 5（Int）；
2. `emit_expr` 的 Slice 约定：**base 在栈上、len 在 rax**；
3. 写穿：
   ```
   rdi = [ref_slot]
   [rdi+8] = rax (len)
   pop rax (base)
   [rdi] = rax
   ```
4. 类型不匹配报 `ref assign: value must be Slice[U8]/Slice[Int]`。

### 2.2 索引写入

语句级 `name[i] = v` 分支在解析 index/value 后：

- 若目标变量类型是 13/14：
  - `rdx = [ref_slot]`（指向 Slice 存储）；
  - `rdx = [rdx]`（base）；
  - U8：`add rcx,rdx; mov [rcx],al`；
  - Int：`mov [rdx+rcx*8],rax`；
  - 值类型检查为 Int/U8；
  - 直接 `continue`，不进入普通 Array/Slice 的 `arr_find/sl_find` 路径。
- 普通 Array/Slice 路径不变。

## 3. 测试

新增：

- `ref_slice_write.ls`（exit 7）：
  - `retarget(ref s, t)` 写描述符，caller `len` 由 4→2；
  - `set0(ref s, 200)` 写 U8 元素，caller 底层 Array 可见；
  - `iset(ref Slice[Int], 1234)` 写 Int 元素；
- reject：
  - `ref_slice_write_type.ls`：Int 赋给 ref Slice；
  - 删除已成立的 `reject/ref_slice_write.ls`；
  - 保留 `ref_str_write_type`/`ref_mismatch`/`ref_alias`/`ref_val`/`ref_literal`/`ref_buffer_mismatch`/`ref_generic`。

`run-stage1.sh` 已加入 `ref_slice_write` 正例（exit 7）与新的负例。

## 4. 验收

- QEMU/TCG 全量 `run-stage1.sh`：
  `PASS compiled ref_slice_write -> exit 7`、`PASS fixed point: stage2 == stage3`；
- 固定点 **`ed085bde…6eb8`**，`QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 **776924 B**、源码 **461586 B**；
- 128 个既有输入：除历史 B4 reject 的预期诊断文本外全部一致；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 5. 边界

| 项 | 状态 |
|---|---|
| `ref Slice` 描述符赋值 | ✅ |
| `ref Slice[i] = v`（U8/Int） | ✅ |
| `ref Slice[i]` 读取 | ✅（B5-3） |
| `ref Str[i] = v` | ❌ |
| 引用类型值/字段/返回 | ❌ |
| 生命周期/逃逸分析 | ❌ |
| `ref Buffer` 赋值 | ❌ |

**下一步**：引用类型值/字段/返回与生命周期/逃逸检查；或 `mode`/cap/effect、
契约/非空 `comptime`、struct/`Error`、结构化诊断。
