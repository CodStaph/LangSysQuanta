# spec/modes.md · 模式与区域（草稿）

> **状态**：`草稿`（Q1 部分冻结；A-2/A-5 待后续阶段）。
> **上位**：设计初稿 §4、工程实践评审 §4.0（内部文档，未随仓库发布）、
> [`results/A-views.md`](../results/A-views.md)。
> **权威**：与 00 冲突时以 00 为准；本文件只细化可执行规则。
> **范围**：region 格、mode 格、R1–R8、视图与 Cursor、约束推断、`recover`。
> **不在本文件**：cap 上下文、效果系统、UB/provenance（分别在 `cap-context.md`/`effects.md`/`ub.md`）。

---

## 1. 区域格

```text
local(s) ⊑ region(R) ⊑ thread ⊑ heap(H) ⊑ static
```

- ρ 只出现在**推断类型**与诊断中，源码不写生命周期参数（LS-P10）；
- `local(s)`：函数/块作用域；
- `region(R)`：`region R { }` 引入的分配区域；
- `thread`：线程局部；
- `heap(H)`：全局堆（`Alloc[Heap]` 产生）；
- `static`：编译期初始化、不可释放（`static`，见 00 §4.10）。

**逃逸规则**：`ref @ ρ` 不可存入 ρ' ⊐ ρ 的位置；`box @ ρ` 不可 move 出 ρ；
`iso` 只能位于 `heap`（可跨域转移）。

## 2. mode 格

| 源码类型 | 核心 mode | 语义 | 可跨域 | 可别名 | 可写 |
|---|---|:--:|:--:|:--:|:--:|
| `box[T]` | `uniq` | 唯一拥有（堆/区域） | 否 | 否 | 是 |
| `iso[T]` | `uniq` | 唯一拥有 + 可转移 | 是 | 否 | 是 |
| `val[T]` | `frozen` | 冻结/只读 | 是 | 是 | 否 |
| `ref[T]` | `mut` | 独占临时借用 | 否 | 受检 | 是 |
| `shared[T]` | `atom` | 共享（锁；原子用 `shared[Atomic[T]]`） | 是 | 是 | 受同步保护 |
| `rawptr[T]` | `raw` | 裸指针（仅 `unsafe`） | 不保证 | 是 | 是 |

**容器（不是 mode）**：`cell[T]`（单域内部可变、`Local`）、`Slice[T]`（只能以 `val`/`ref` 出现）。

## 3. 检查规则 R1–R8

| # | 规则 | 诊断 |
|---|---|---|
| R1 | `uniq` 无别名；`move` 后源失效 | `E-LS-MOVE` |
| R2 | `uniq` 可在作用域 s 内借出 `ref`，s 结束归还（reborrow） | `E-LS-ALIAS` |
| R3 | `uniq --freeze--> frozen` 单向；`recover {}` 内消费全部别名方可回 `uniq` | `E-LS-UNIQ` |
| R4 | `ref @ ρ` 不可存入 ρ' ⊐ ρ 的位置（逃逸） | `E-LS-REGION-ESCAPE` |
| R5 | 写 place 要求**其区域内**无 `frozen`/`ref` 别名（区域级，非全局） | `E-LS-ALIAS` |
| R6 | `atom` 只能跨域共享，且带 `Atomic/Order` 或锁 rank | `E-LS-RACE` |
| R7 | `raw` 仅在 `unsafe` 且作用域内存在 `Cap[Unsafe]` 值（或模块 `#[cap]`）时可用 | `E-LS-UNSAFE`/`E-LS-CAP` |
| R8 | 跨域（`Thread`/`Irq`/`Dma`）移动只允许 `iso`/`atom` | `E-LS-RACE` |

### 3.1 R5 的代价（必须保留）

`val` 的生命期等于所属区域；区域结束前不得再对该 place 取可变借用。
fix-it 只能建议：缩小作用域 / `cell` / 复制；**不得**建议 `unsafe`（LS-P17）。

## 4. 视图与 Cursor（Q1 已冻结）

> 证据：[`results/A-views.md`](../results/A-views.md)，checker `173d1b6`。

### 4.1 规则

1. **`val` 字段可返回**：含 `val` 字段的结构体是区域参数化的；ρ 由源推断，源码不写。
2. **`ref` 字段不可返回**：只能在借用作用域内存活；返回即 `E-LS-REGION-ESCAPE`。
3. **Cursor 模式**：`struct Cursor { src: val[Slice[T]], pos: USize }`，可返回、可 `ref` 可变。
4. `recover` 仅限**单函数 + 同域**；跨模块/跨域禁止（`E-LS-UNIQ`）。
5. 需要可变视图：`ref[Slice]` + 作用域内 API；跨函数传 owner，不传 `ref`。

### 4.2 正例

```ls
struct Packet { header: Header, payload: val[Slice[U8]] }
fn parse(src: val[Slice[U8]]) -> Result[Packet, Error] { ... }

struct Cursor { src: val[Slice[U8]], pos: USize }
fn cursor(src: val[Slice[U8]]) -> Cursor { ... }
```

### 4.3 负例

```ls
struct BadCursor { src: ref[Slice[U8]] }
fn bad(src: ref[Slice[U8]]) -> BadCursor { BadCursor { src } }   // E-LS-REGION-ESCAPE

fn bad_store(p: Packet) { static S: Packet = p; }                // E-LS-STATIC

fn bad_recover(p: val[Packet]) -> Packet {
    let q = p;
    recover { p }                                                // E-LS-UNIQ (q 未消费)
}
```

## 5. 约束推断

1. **约束生成**：`borrow`/`alloc`/`freeze`/`recover`/`spawn`/`store` 产生 `ρ1 ⊑ ρ2`；
2. **求解**：区域格上并查集 + 最小上界；函数级完成，不做全程序不动点（ADR-8）；
3. **失败**：输出最小不可满足核（2–3 条约束）+ fix-it；
4. **fix-it 顺序**：缩小作用域 → 复制 → 改 `uniq` → 提升 region → `recover`；
5. **禁止**：fix-it 生成 `unsafe`/新 cap/`Ffi`。

## 6. `recover` 的线性检查

- `recover { e }` 的别名集合 = 块内所有 `val` 标识符；
- 块外同一函数内、在 `recover` 之前创建的别名必须被消费（在块内出现）；
- 未消费 ⇒ `E-LS-UNIQ`；
- 跨模块/跨域无法追踪 ⇒ 直接拒绝；
- 若未来引入 `#[recover]` 注册表，必须另立 ADR。

## 7. 未决 / 待验证

| # | 项 | 阻塞 | 计划 |
|---|---|---|---|
| M-1 | 源区域结束后使用 `Packet` 的检查（A-5） | 需要作用域/区域分析 | S1 |
| M-2 | `parse` 无 `memcpy` 的 IR/汇编验证（A-2） | 需要后端 | S0′ |
| M-3 | `cell` 与 `val` 的别名规则边界 | 库 API 表达力 | W3 |
| M-4 | `recover` 是否需要跨函数逃生舱 | 零拷贝归还 | S4 |

## 8. 语料

- `dossiers/views/accept.ls` / `reject.ls`（当前）；
- `tests/conformance/accept|reject`（S-1 期间 ≥20 条负例）。

## 9. 冻结条件

- R1–R8 每条有正/负例；
- §4 视图规则被 checker 接受（A-1/A-3/A-6/A-7）；
- 最小不可满足核有 1 个可复现样例；
- A-5 的作用域规则有明确归属（本文件或 S1 的 region 分析）。
