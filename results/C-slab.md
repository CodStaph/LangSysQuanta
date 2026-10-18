# C · slab / 侵入式链表 / refcount / C 驱动（dossiers/slab）

状态：**条件通过（checker-spike 7/7；C-5/C-6/C-7 未做）**
负责人：—
复核：—
commit：—
命令：`cargo run --quiet --manifest-path tools/checker-spike/Cargo.toml -- dossiers/slab`
证据：`dossiers/slab/reject.ls` expected=7 actual=7；`accept.ls` diagnostics=0，unsafe=4

| # | 检查 | 结果 | 证据 |
|---|---|---|---|
| C-1 | slab 安全 API；unsafe ≤ 3 | 部分 | 检查器 unsafe=4；预算复核待 S1 |
| C-2 | 无隐藏分配 / O(1) | 未评审 | — |
| C-3 | 双重释放被拒 | **通过（spike）** | `double_free` → `E-LS-PROV` |
| C-4 | 越界/对齐负例被拒 | 部分 | `unchecked_index` → `E-LS-DIAL`；无专用 bounds/align 用例 |
| C-5 | fuzz 10^6 无 UAF | 未评审 | S1 |
| C-6 | refcount/RCU 测试 | 未评审 | S1 |
| C-7 | C 移植 ≤ 5 unsafe | 未评审 | S1 |
| C-8 | `defer` 无泄漏 | 部分 | `accept.ls` 有 `defer dma.wait()`；无泄漏检查器 |
| C-9 | ISR 预算 | 未评审 | S1 |
| C-10 | C 互操作 | 未评审 | S1 |

## 检查器触发路径（2026-10-18）

`dossiers/slab/reject.ls` 7/7：

| 触发 | 期望码 | 检查器规则 |
|---|---|---|
| `double_free` | `E-LS-PROV` | 同函数重复 `free` + 同实参 |
| `double_link` | `E-LS-PROV` | 同函数重复 `push` + 同实参 |
| `copy_mmio` | `E-LS-MOVE` | `Mmio` 参数在 `(a, a)` 中复制 |
| `forget_dma` | `E-LS-LEAK` | `DmaToken` 经 `let _ = d;` 丢弃 |
| `unchecked_index` | `E-LS-DIAL` | `#[bounds(off)]` 无 `requires/ensures` |
| `BadHolder` | `E-LS-REGION-ESCAPE` | struct 字段含 `Alloc[Region]` |
| `COUNTER` | `E-LS-STATIC` | `static mut` |
| `no_cap` | `E-LS-CAPCTX` | 无模块 cap / 显式 `Cap[Unsafe]` 的 unsafe 块 |

> 上述是**可证伪的 spike 规则**，不是最终检查器；C-1/C-4/C-8 仍只到部分证据。

## 结论

- unsafe 原语清单：`build_free_list` / `ptr_read` / `ptr_write`（+ 可选 `container_of` / `assume_init`）；
- 总数：accept.ls 检查器计数 4，需 S1 复核是否把可选原语计入；
- 是否需要 `LS-25`：暂不需要（无 UAF 证据，仅检查器覆盖不足）；
- 后续动作：C-5/C-6/C-7 进 S1；checker-spike 不再扩展，规则迁入 `ls-sem`。
