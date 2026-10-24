# B5-1 · `ref` 参数（Int 临时借用）

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `0ecbacaf…40a6`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md) §5、[`spec/bls.md`](../spec/bls.md)、
> [`spec/modes.md`](../spec/modes.md) §2（`ref[T]` 为独占临时借用）。
> 范围：**`ref x: Int` 形参 + 调用点按变量取址 + callee 内读写解引用**；
> 不做完整引用类型、生命周期分析、`val`/`ref` 字段、跨函数转发。

## 1. surface

```ls
fn bump(ref x: Int) -> Int {
    x = x + 1;      // 写入 caller 的变量
    return x;       // 读取
}

fn main() -> Int {
    let a = 3;
    let b = bump(a);  // 实参必须是可变 Int 变量
    ...
}
```

- 只支持 `ref x: Int`（B5-1 的边界）；
- 实参必须是**单个可变 Int 变量**：变量、未 shadow 的普通 `let`/参数；
  - 字面量/表达式/数组元素/结构字段/`val` 绑定 → 编译错误；
  - 同一个调用里两个 `ref` 形参不能指向同一变量；
- `ref` 形参在 callee 内可读写；读出的表达式类型是 `Int`；
- `ref` 形参不能出现在泛型函数中；
- 不提供 `ref` 类型值本身：`ref` 只存在于形参，读取得到值拷贝，
  因而无法把借用保存到变量、返回或跨调用转发（B5-1 的简化安全边界）。

## 2. 实现

### 2.1 编译期

- `scan_refmask(src, fd, post)`：在 `check_decls` 之前扫描每个函数的参数列表，
  记录哪些位置以 `ref` 开头（`post[130000+fi]` 的位掩码）。
- `check_decls` 修复了一个旧问题：以前 `nsts[0]/nsts[1]` 未设置，所有函数名都按空名
  取 `name_id`，导致 `post[30000+nid]` 的 arity 表实际只对 id 0 有效；现在设置
  `nsts[0]=ns/nsts[1]=nl`，arity/refmask 按真实名字 id 记录。
- `parse_expr` 在调用点按**源码名 span** 查函数表得到 refmask（`cref[32]`），
  不依赖 name id，因此 forward call 也可用。
- 调用点对 ref 实参做：
  1. 要求该实参的 IR 恰好是一个变量读取（`post` 只有 `kind 1`）；
  2. 变量 meta 类型必须是 Int（1）且不是 `val`；
  3. 扫描同一调用里已有的 `kind 74` 实参，拒绝同一变量重复借用；
  4. 把该 IR 改成 `kind 74`（取变量槽地址）。
- callee 的 `ref x: Int` 存为变量类型 **11**（`Ref Int`，指针）；
  `push_var` 对类型 11 生成 `kind 76`（解引用）；赋值语句对类型 11 生成
  `rcx = [slot]; [rcx] = rax`，不写形参变量槽。
- 新增 post kind：
  - `74`：`lea rax,[rip+var_slot]; push rax`（取址）
  - `76`：`pop rax; mov rax,[rax]; push rax`（解引用）

### 2.2 运行期

- 调用约定不变：ref 实参占 **1 个参数槽**，传的是 caller 变量槽的地址；
- callee 的形参槽保存该地址；读写都通过它，因此 caller 可见；
- 指针只在调用期间有效；callee 无法返回/保存 `ref` 值，故不会悬垂。

### 2.3 约束/限制（编译期拒绝）

| 情形 | 诊断 |
|---|---|
| `ref x: T` 且 T != Int | `E-LS-UNSUPPORTED: ref parameters are only implemented for Int` |
| 泛型函数中的 ref | `E-LS-UNSUPPORTED: ref parameters in generic functions ...` |
| 实参不是变量 | `ref argument must be a mutable Int variable` |
| 实参是 `val` 绑定 | `ref argument cannot be a val binding` |
| 同一变量借给两个 ref 形参 | `ref arguments alias the same variable` |
| ref → ref 转发 | `ref argument must be a mutable Int variable`（当前未实现指针值） |

## 3. 测试

新增：

- `ref_int.ls`（exit 7）：`ref` 读、写、两个 ref 形参、写回 caller、连续调用；
- reject：
  - `ref_alias.ls`：`two(x, x)`；
  - `ref_val.ls`：`val` 参数被 ref 借用；
  - `ref_literal.ls`：`use_ref(1)`；
  - `ref_str.ls`：`ref s: Str`；
  - `ref_generic.ls`：泛型函数里的 ref；
  - `ref_forward.ls`：ref → ref 转发。

删除已成立的 `reject/bls_ref.ls`；`run-stage1.sh` 加入 `ref_int` 正例、
`ref_str`/`ref_generic` 的 `E-LS-UNSUPPORTED` 检查，以及 B5 引用诊断循环。

回归：128 个既有输入除两个 B4 reject 的预期诊断文本（历史遗留）外，
rc/stdout/stderr 全部一致；`ref_int` 在 seed 解释器、编译后 stage1、stage2 上均通过。

## 4. 验收

- QEMU/TCG 全量 `run-stage1.sh`：`PASS compiled ref_int -> exit 7`，
  `PASS fixed point: stage2 == stage3`，固定点 **`0ecbacaf…40a6`**，
  `QEMU-GUEST: RESULT=PASS`；
- `names_stage` 自编译 **746232 B**；源码 **444043 B**；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 5. 边界

| 项 | 状态 |
|---|---|
| `ref x: Int` 形参 | ✅ |
| 读写穿透 | ✅ |
| 多 ref 形参（不同变量） | ✅ |
| `ref` to `U8`/`Str`/`Slice`/`Buffer` | ❌ |
| ref → ref 转发 | ❌ |
| `ref` 变量/字段/返回值 | ❌（B5-1 不暴露引用类型值） |
| 生命周期/逃逸分析 | 不需要：借用只在调用期间存在；无保存路径 |
| 别名检查 | 仅同一调用内的重复变量；跨语句别名由“引用不可保存”间接排除 |
| 泛型函数中的 ref | ❌ |

**下一步（B5-2）**：`ref` 扩展到 `Str`/`Slice`/`Buffer`，引入真正的引用类型与
借用/生命周期检查；再处理 `val`/`ref` 字段、`ref` 转发与 region 逃逸。
