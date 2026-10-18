# Q2/Q6/Q7 · 第一版实现记录

日期：2026-10-18
工具：`tools/ls-sem`（Rust，零依赖）
状态：**数据模型/矩阵级实现完成；parser/构建/ABI 冻结套件未做**

## Q2 · 模块 cap（`cap_context.rs`）

已实现：

- `Capability`：`Unsafe`/`Alloc`/`Dma`/`Ffi`/`Spawn`/`Irq`/`Mmio{lo,hi}`；
- `Module`：`caps`、`forbid_unsafe`、`Knobs{bounds_off,overflow_wrapping,fp_fast}`；
- `ModuleTree`：
  - `require_cap` 只看本模块（不继承父 cap）；
  - `forbids_unsafe` 向下继承；
  - `allows_unsafe` 需本模块 `Unsafe` 且祖先无 forbid；
  - `validate`：forbid 冲突、Mmio 空范围、子模块 knob 放宽；
- CLI `ls-sem caps`：负例 demo；
- 测试：`q2_child_does_not_inherit_cap`、`q2_forbid_is_downward_closed`、
  `q2_child_knob_cannot_loosen`、`q2_mmio_range_is_contained`。

未做：源码 module 属性 → `ModuleTree` 的 parser、manifest 最小授权。

## Q6 · C ABI（`abi.rs`）

已实现：

- `CType`（`char`/`long`/`size_t`/`pointer`/`long double`/`varargs` 等）；
- `LSysType` + `size_align`；
- `map_scalar`：target-specific `char` signedness、`long` 宽度；
- `check_signature`：位域/无 repr enum 拒绝；
- CLI `ls-sem abi <triple> <ctype>`；
- 测试：`q6_char_and_long_are_target_specific`、`q6_rejects_long_double_and_bitfields`。

未做：struct/union/enum 布局、`ls abi-check`、ABI 冻结套件。

## Q7 · target 矩阵（`target.rs`）

已实现：

- 三目标：`x86_64-unknown-linux-gnu`、`thumbv7em-none-eabihf`、`riscv32imac-unknown-none-elf`；
- `DataModel`（pointer/long/size_t/char_signed）、`FloatAbi`、`Atomics`、`Endian`；
- `by_triple`、`validate_config`（未知/超能力拒绝）；
- CLI `ls-sem targets`；
- 测试：`q7_matrix_rejects_unknown_and_overcommit`。

未做：构建、链接、QEMU/HIL、可复现指纹。

## 验证

```text
cargo test --manifest-path tools/ls-sem/Cargo.toml
13 tests passed

ls-sem selftest   PASS (core, q2, q6, q7)
ls-sem targets    3 targets
ls-sem caps       2 expected diagnostics
```

> 这些实现是 S1 的第一块可执行基础，不是 Q2/Q6/Q7 的最终关闭；
> 关闭条件仍是 §未做 + ABI 套件/构建矩阵。
