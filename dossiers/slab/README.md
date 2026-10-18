# 档案 C · slab + 侵入式链表 + refcount/RCU + C 驱动移植

> 权威描述：工程实践评审 §4.2（内部文档，未随仓库发布）。
> 对应决策：Q2（模块 cap）、Q6（C 类型映射）；ADR-18、D32；`H-LS-30`。

## 目标

证明自引用/侵入式结构、引用计数、RCU、C 驱动移植的 unsafe 面积可控，且错误路径不泄漏：

- slab 安全 API 内部 ≤ 3 个 unsafe 原语；
- 侵入式链表 fuzz 无 UAF；
- `defer` 保证错误路径零泄漏；
- C 驱动移植 ≤ 5 个 unsafe 原语（6–8 条件通过）。

## 文件

| 文件 | 内容 |
|---|---|
| `accept.ls` | `#[cap(Unsafe)]` slab、List、Ref、Rcu、I2C 驱动 |
| `reject.ls` | 双重释放、未链接 push、`Mmio` 复制、缺 `defer`、`#[bounds(off)]` 无契约 |

## 验收清单

| # | 检查 | 判据 | 结果 | 证据 |
|---|---|---|---|---|
| C-1 | slab 安全 API | `init/alloc/free` 对调用者安全；unsafe 原语 ≤ 3 | 未评审 | — |
| C-2 | 无隐藏分配 | `alloc/free` 无 `Alloc` 效果、O(1) | 未评审 | — |
| C-3 | 双重释放 | `free` 两次被拒（`E-LS-DROP` 或契约） | 未评审 | — |
| C-4 | 越界/对齐 | `contains`/`is_aligned` 负例被拒 | 未评审 | — |
| C-5 | 侵入式链表 | fuzz 10^6 随机 push/remove 无 UAF | 未评审 | — |
| C-6 | refcount | 下溢/溢出被拒；RCU 宽限期测试通过 | 未评审 | — |
| C-7 | C 驱动移植 | 编译 + QEMU 跑通；`unsafe` ≤ 5；`defer` 无泄漏 | 未评审 | — |
| C-8 | 错误路径 | 每个 `?` 提前返回后资源计数归零 | 未评审 | — |
| C-9 | 中断延迟 | ISR 无 `Alloc`/`Block`；最坏路径 ≤ 预算 | 未评审 | — |
| C-10 | C 互操作 | `#[no_mangle]` 回调、C 类型映射、errno 映射 | 未评审 | — |

## unsafe 原语预算

| 原语 | 用途 | 是否计入 |
|---|---|---:|
| `build_free_list` | 初始化 free list | 1 |
| `ptr_read` | `(*head).next` | 1 |
| `ptr_write` | `(*f).next` | 1 |
| `container_of` | 侵入式链表取宿主 | 1（可选） |
| `assume_init` | 设备缓冲 | 1（可选） |

slab 本身 ≤ 3；C 驱动移植总量 ≤ 5（6–8 条件通过，>8 失败）。

## 失败后果

- C-5 出 UAF 或 C-7 unsafe > 8：安全子集表达力不足 ⇒ `LS-25`，回 S0′；
- C-8 泄漏：`defer`/泄漏检查不成立，`resource.md` 不得冻结；
- C-9 超限：ISR 预算不可承诺，kernel 场景降级。
