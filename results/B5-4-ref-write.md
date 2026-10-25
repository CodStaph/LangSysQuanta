# B5-4 · `ref Str` 写入与 `ref Str[i]`

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `6b4df3ca…f321`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`results/B5-3-ref-buffer.md`](B5-3-ref-buffer.md)。
> 范围：`ref Str` 赋值（字面量/Str 表达式）与 `ref Str[i]` 字节读取；
> 不做 `ref Slice` 写入、引用类型值/字段/返回、生命周期/逃逸分析。

## 1. surface / 语义

```ls
fn set(ref s: Str) -> Int {
    s = "xyz";           // 字面量写穿 caller 的 Str 三槽
    return s.len;
}
fn copy(ref s: Str, t: Str) -> Int {
    s = t;               // Str 表达式写穿
    return s.len;
}
fn byte_at(ref s: Str, i: Int) -> Int { return s[i]; }  // U8
```

- `ref s: Str` 的赋值支持：
  - 字符串字面量（编译期写入 `ds` 并生成 base/len/chars 三值）；
  - 任意 `Str` 表达式（变量/参数/函数返回值）；
  - 目标必须是 caller 的 Str 变量（形参指针指向其 3 个槽）；
- `ref Str[i]` 读取第 i 个 **UTF-8 字节**，返回 `U8`（越界不检查，与 Slice 索引一致）；
- 仍拒绝：通过 ref 写 Slice、`ref Slice` 赋值、引用类型值/字段/返回、
  `ref Buffer` 赋值、生命周期/逃逸分析。

## 2. 实现

### 2.1 `ref Str` 赋值

赋值分支现在先解析目标变量（`vi`/`vty`），再按类型处理 RHS：

- `vty == 12`（Ref Str）：
  - 字面量：`parse_str_lit` → data offset/len/chars；生成 `push base; push len; rax=chars`；
  - 表达式：`parse_expr` + `emit_expr`（要求类型 3），`emit_expr` 的约定是
    **chars 在 rax，base/len 在栈上**；
  - 统一写穿：
    ```
    rdi = [ref_slot]
    [rdi+16] = rax (chars)
    pop rax (len); [rdi+8] = rax
    pop rax (base); [rdi] = rax
    ```
- `vty == 11`（Ref Int）沿用 B5-1 的指针写入；
- `vty == 13/14`（Ref Slice）仍报 `E-LS-UNSUPPORTED`；
- `vty == 15`（Ref Buffer）仍报 `E-LS-UNSUPPORTED`；
- 普通变量保持原“写变量槽”路径。

### 2.2 `ref Str[i]`

新增 post kind **85**：

```text
pop rcx                 ; index
rdx = [ref_slot]        ; pointer to Str box
rdx = [rdx]             ; base
rcx += rdx
movzx eax, byte [rcx]
push rax
```

`[` 分支先检查变量类型：12 → kind 85（U8）；13/14 → kind 83/84（B5-3）；
否则走普通 Array/Slice 路径。

## 3. 测试

新增：

- `ref_str_write.ls`（exit 7）：
  - `set(ref s)` 字面量写入，caller `s.len == 3`；
  - `copy(ref s, t)` 从 Str 参数写入，caller `s` 变为 `t`；
  - `byte_at(ref s, i)` 读取 UTF-8 字节（`"hell"` → 104/101）；
- reject：
  - `ref_slice_write.ls`：`ref Slice` 赋值仍拒绝；
  - `ref_str_write_type.ls`：ref Str 赋 Int；
  - 删除已成立的 `reject/ref_assign_str.ls`；
  - 保留 `ref_alias`/`ref_val`/`ref_literal`/`ref_mismatch`/`ref_buffer_mismatch`/`ref_generic`。

`run-stage1.sh` 已加入 `ref_str_write` 正例（exit 7）与上述负例。

## 4. 验收

- QEMU/TCG 全量 `run-stage1.sh`：
  `PASS compiled ref_str_write -> exit 7`、`PASS fixed point: stage2 == stage3`；
- 固定点 **`6b4df3ca…f321`**，`QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 773362 B、源码 459545 B；
- 128 个既有输入：除历史 B4 reject 的预期诊断文本外全部一致；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 5. 边界

| 项 | 状态 |
|---|---|
| `ref Str` 赋值（字面量/Str 表达式） | ✅ |
| `ref Str[i]` 字节读取 | ✅ |
| `ref Slice` 赋值 | ❌ |
| 通过 ref 写 Slice 内容 | ❌ |
| 引用类型值/字段/返回 | ❌ |
| 生命周期/逃逸分析 | ❌（借用只在调用期；无保存路径） |
| `ref Buffer` 赋值 | ❌ |

**下一步**：`ref Slice` 写入/引用类型值/生命周期/逃逸；或 `mode`/cap/effect、
契约/非空 `comptime`、struct/`Error`、结构化诊断。
