# B3-1 · 运行时 arena 元数据与 bump 分配

> 状态：**B3-1 完成（2026-10-23）**。QEMU 固定点 `5abc542d…a8995`，`stage2 == stage3`。
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B3 条目、[`spec/bls.md`](../spec/bls.md)。
> 本轮只做 **arena 基础原语**；`Buffer[T]` 布局与 `try_new` 失败路径留到 B3-2/B3-3。

## 1. 交付内容

### 运行时 heap 布局（沿用 B-LS 现有 1 MiB bump 区）

| 槽 | 含义 |
|---|---|
| `post[17010]` | `base`：arena 起始地址 |
| `post[17011]` | `current`：当前 bump 指针 |
| `post[17012]` | `end`：`base + 1 MiB` |

`arena_reset()` 仍把 `current = base`（原有 kind 32 行为不变），`Str +` 的临时分配继续使用同一
`current/end`，因此 arena 原语与 `Str +` 共享预算。

### 新内置

| 内置 | 语义 |
|---|---|
| `arena_alloc(n: Int) -> Int` | 把 `n` 向上按 8 字节对齐；成功返回相对 `base` 的字节偏移，失败返回 `-1`；成功时 `current += n'` |
| `arena_used() -> Int` | `current - base` |
| `arena_budget() -> Int` | `end - base`（当前为 1 MiB） |
| `arena_reset()` | `current = base`（已有） |

实现位置：

- `builtin_code`：新增 9 = `arena_alloc`、10 = `arena_used`、11 = `arena_budget`；
- 表达式解析：`arena_alloc` 用 `parse_index` 取一个 Int 参数，分别 push post kind `48`；
  `arena_used`/`arena_budget` 无参，push kind `54/55`；
- `emit_expr_a`：kind 54/55 直接读 heap 槽相减；kind 48 执行
  `pop n → align8 → rcx=current → rdx=current+n → cmp end → 成功写 current 并 push 偏移；
  失败 push -1`。

### 关键修复

第一次实现时 `add rdx, rax` 被编码成 `48 01 D0`（`add rax, rdx`），导致
`current` 不前进、`arena_used()` 不增长；QEMU 返回 2。通过反汇编确认后改成
`48 01 C2`，`arena_alloc` 的 `current = current + n` 才正确。

## 2. 测试

`bootstrap/bls/tests/stage1_arena.ls`：

```ls
fn main() -> Int {
    let b = arena_budget();
    let u0 = arena_used();
    let p = arena_alloc(16);
    let u1 = arena_used();
    if p < 0 { return 1; }
    if u1 != u0 + 16 { return 2; }
    let q = arena_alloc(b);       // 预算不足
    if q >= 0 { return 3; }
    arena_reset();
    if arena_used() != 0 { return 4; }
    return 7;
}
```

覆盖：预算查询、初始 used、成功分配、失败返回 `-1`、reset 后 used 归零。
该测试只在 **stage1** 路径运行（`run-stage1.sh` 解释器 + Linux guest 编译执行），
不加入 seed 的 `run-interp`/`build.sh`（seed 不需要知道新内置）。

QEMU：

```text
PASS interpreted arena -> ELF
PASS compiled arena stage1 -> exit 7
PASS fixed point: stage2 == stage3
stage2_self = stage3_self = 5abc542d…a8995
QEMU-GUEST: RESULT=PASS
```

## 3. 行为/固定点

- 80 个既有输入（73 tests + 7 src）中，除 `names_stage` 自编译外全部
  `rc`/SHA-256/stderr/stdout 逐字节一致；
- `names_stage` 自编译：`3a5cc218…c452` 433865 B → `3766b8f0…d2d8` 444982 B；
- 新增 `stage1_arena.ls` 产出 1870 B ELF；
- QEMU 固定点 `5abc542d…a8995`。

## 4. 边界

| 项 | 状态 |
|---|---|
| arena base/current/end + used/budget/reset | ✅ |
| 8 字节对齐、预算失败 `-1` | ✅ |
| `Str +` 与 arena 共享预算 | ✅（沿用同一 current/end） |
| `Buffer[T]` 布局（len/cap/owner） | ❌ B3-2 |
| `Buffer.try_new` 返回 `Result` | ❌ B3-3 |
| 原始指针 load/store / 从 arena 构造 Slice | ❌ 需要新的内存原语 |
| 高水位统计、LIFO 回收、region 所有权 | ❌ 后续 |
| `arena_alloc` 返回的是偏移而非可直接解引用的指针 | 🟡 为后续 Buffer 预留 |

**下一步建议**：B3-2a/B3-2b 已完成（见 `results/B3-buffer.md`）；
下一步 B3-3 接 `try_new`/`Result`，再补 `b[i]`、region 所有权与 release/drop。
