# B5-7 · ref struct 字段与 ref 数组元素

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `441ca62c…6e80`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2、[`results/B5-6-ref-values.md`](B5-6-ref-values.md)。
> 范围：`struct` 的 `ref[Int/Str/Slice/Buffer]` 字段、`let r: ref[Int] = arr[i]`；
> 不做引用类型作为数组元素/泛型负载、生命周期/逃逸静态分析。

## 1. surface / 语义

```ls
struct Holder { r: ref[Int], n: Int }
struct HStr   { s: ref[Str] }

let h: Holder;
let a = 5;
h.r = idref(a);          // ref 字段存指针
let q: ref[Int] = h.r;   // 读出指针（ref 值）
q = 9;                   // 写穿 a

let ai: Array[Int, 3] = Array.zeroed();
ai[1] = 5;
let re: ref[Int] = ai[1]; // 数组元素取址
re = 13;                  // 写穿 ai[1]
```

- struct 字段类型支持 `ref[Int/Str/Slice[U8]/Slice[Int]/Buffer[Int]]`，字段占 **8 字节**指针；
- 字段赋值来源：
  - ref 变量（含 ref 形参/局部）→ 直接存指针；
  - 同 base 类型的普通变量 → 取地址后存指针（Int/Buffer 变量槽、Str 槽、Slice 槽）；
  - 返回 ref 的函数调用 → 存返回指针；
- `s.f` 读出的是 **ref 值**（指针），必须先绑定到 ref 局部/ref 返回/ref 实参再解引用；
  直接 `s.f + 1` 等运算被拒绝：
  `E-LS-UNSUPPORTED: ref value must be bound to a ref local before use`；
- `let r: ref[Int] = arr[i]` 只接受 **Array[Int]**；Array[U8] 取 ref 仍拒绝；
- 字段/数组元素都没有生命周期或逃逸静态检查。

## 2. 实现

### 2.1 struct 字段

- struct 字段解析识别 `ref[...]`：`parse_ref_ty` → elem = 11..15；
- 字段大小：elem >= 11 按 **8 字节**（`st_size` 与 `foff` 同步）；
- 字段读取：elem >= 11 时生成 `kind 12`（读 qword）并 `set_ty(elem)`，
  得到 ref 类型值；
- 字段写入（elem >= 11）：
  - 表达式路径（ref 调用）要求类型 == elem；
  - 变量路径：ref 变量 → kind75；普通变量 → kind74/81/82；
  - 存入字段槽（qword）。

### 2.2 ref 数组元素

- typed let 的 ref 分支检测 `name[` 且 `arr_find` 命中 `Array[Int]`：
  - `parse_index` 解析下标；
  - 新 post kind **86**：`pop rcx; lea rax,[array]; lea rax,[rax+rcx*8]; push rax`；
  - 保存指针到 ref 局部；
- Array[U8] 取 ref 拒绝（`let: ref array element must be Int`）。

### 2.3 附带修复

typed let 的 `Option`/`Result`/`Str`/`Slice` 分支以前只比较首字母，导致
`SHolder`/`RStrHolder` 这类用户类型被误判为 `Slice`/`Result`。现在这些分支要求
**完整关键字 + `kw_end`**，其它首字母相同的类型名走 struct 回退路径。

## 3. 测试

新增：

- `ref_fields.ls`（exit 7）：
  - `Holder.r`（ref Int）：ref 调用写入、ref 局部读出、写穿、普通变量取址写入；
  - `HStr.s`（ref Str）：`.len`/写入；
  - `HVec.v`（ref Slice）：索引写入；
  - `HBuf.b`（ref Buffer）：`push`；
  - `Array[Int]` 元素 ref 读写；
- reject：
  - `ref_field_mismatch.ls`：ref Str 字段赋 Int；
  - `ref_array_u8.ls`：Array[U8] 取 ref；
  - `ref_field_direct.ls`：直接 `h.x + 1`；
  - 删除已成立的 `reject/ref_field.ls`。

`run-stage1.sh` 已加入 `ref_fields` 正例（exit 7）与上述负例。

## 4. 验收

- QEMU/TCG 全量 `run-stage1.sh`：
  `PASS compiled ref_fields -> exit 7`、`PASS fixed point: stage2 == stage3`；
- 固定点 **`441ca62c…6e80`**，`QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 **800361 B**、源码 **475507 B**；
- 128 个既有输入：除历史 B4 reject 的预期诊断文本外全部一致；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 5. 边界

| 项 | 状态 |
|---|---|
| struct `ref[T]` 字段 | ✅ |
| 字段读为 ref 值（需绑定后解引用） | ✅ |
| `let r: ref[Int] = Array[Int][i]` | ✅ |
| Array[U8] / Slice 元素取 ref | ❌ |
| 引用作为数组元素/泛型负载 | ❌ |
| 生命周期/逃逸静态分析 | ❌ |
| 直接对 ref 字段做算术/比较 | ❌（显式拒绝） |

**说明**：ref 字段可以把指针存进 struct，因此按 L-Sys 语义属于潜在逃逸路径；
B5-7 没有生命周期检查，只保证 B-LS 内部的静态数据布局安全。真正的借用/逃逸检查
仍需后续设计。

**下一步**：生命周期/逃逸静态检查、ref 作为数组元素/泛型负载；或 `mode`/cap/effect、
契约/非空 `comptime`、struct/`Error`、结构化诊断。
