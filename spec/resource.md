# spec/resource.md · `defer`、`#[must_release]` 与泄漏检查（草稿）

> **状态**：`草稿`。规则草案；checker-spike 仅有 `let _` 级 `E-LS-LEAK`，
> 完整 definite-release 分析待 S0′。
> **上位**：[`02 ADR-14`](../02-架构评审与ADR.md)（release/fault/错误合并）、
> [`00 §5.8`](../00-LangSysQuanta-设计初稿.md)（panic/错误/Drop）、
> [`00 §6.6`](../00-LangSysQuanta-设计初稿.md)（析构顺序）、
> [`effects.md`](effects.md)（`Unsafe` 终止）、[`modes.md`](modes.md)（R1–R8）。
> **范围**：`defer` 的作用域/顺序/错误路径，`#[must_release]`，线性资源泄漏。
> **不在本文件**：堆分配器实现、GC、panic unwind（v0 一律 abort）。

---

## 1. 线性资源

- `Cap[...]`、`DmaToken`、文件/锁 guard、带 `#[must_release]` 的类型是**线性**的：
  恰好消费一次；
- 线性值不能 `Copy`；`move` 后源失效（R1/E-LS-MOVE）；
- 隐式 `Drop` 只对普通拥有值；线性类型必须显式 `release`/`defer`/`move` 到消费者；
- `recover` 消费 `val/ref` 别名，不改变线性资源的消费次数（S9）。

---

## 2. `defer`

### 2.1 语法与执行

```ls
fn run(dev: ref[I2cDev]) -> Result[Unit, Error] eff(Io, Alloc) {
    let dma = dma_map(dev.rx_buffer())?;   // DmaToken
    defer dma.wait();                      // 作用域退出时消费 dma
    loop { read_sample(dev)?; }
}
```

规则：

1. `defer expr;` 在**声明点捕获**资源（按 move），表达式在**作用域退出时**求值一次；
2. 同一作用域的 `defer` 按**声明逆序**执行（LIFO）；
3. 作用域退出包括：正常结束、`return`、`break`/`continue`、`?` 提前返回；
4. `abort`/`panic` 在 v0 **不执行** `defer`（panic=abort，H-LS-19）；`unsafe` 中的 abort 同；
5. `defer` 先于同一作用域剩余局部值的隐式 Drop 执行；被 `defer` move 的资源不再隐式 Drop；
6. `defer` 表达式不得逃逸作用域；捕获的 `ref` 不能指向比 defer 更短寿命的局部；
7. `defer` 在循环体内声明时，每次迭代退出都执行一次；
8. `defer` 不得在 `comptime` 中使用（无副作用/无 IO）。

### 2.2 与 `?` / `return` / `break`

`?` 脱糖为 `match` + 提前 `return`；`return`/`break`/`continue` 都触发当前作用域的 defer 链。
因此“错误路径零泄漏”由 **defer 链 + 线性消费** 共同保证，而不是靠 `Drop`。

### 2.3 禁止

- `defer` 捕获 `Cap[...]` 后不消费（只读）⇒ `E-LS-LEAK`；
- `defer` 表达式内部再次 `defer` 同一资源 ⇒ 双重消费 `E-LS-MOVE`/`E-LS-LEAK`；
- `defer` 在 `#[naked]`/`asm` 上下文中无定义；
- `defer` 不得跨 `region` 边界捕获区域根（`E-LS-REGION-ESCAPE`）。

---

## 3. `#[must_release]`

```ls
#[must_release]
struct File { fd: I32 }

impl File {
    fn release(self) -> Result[Unit, Error] { ... }   // 消费 self
}
```

规则：

1. `#[must_release]` 类型必须由 `release(self)`/`defer`/`move` 到消费者处理；
2. 隐式 Drop 该类型 ⇒ `E-LS-LEAK`（kernel）或审计警告（agent，暂定）；
3. `release` 的返回值必须处理或显式 `ignore`（D19）；不得静默丢弃 `Result`；
4. `release` 后使用原变量 ⇒ `E-LS-MOVE`；
5. `#[must_release]` 与 `#[trusted]` 独立：前者是资源纪律，后者是信任闭包；
6. 类型跨 FFI 时，`release` 的所有权约定必须写进 C 头文件/ABI 注释（`E-LS-ABI`）。

---

## 4. 析构顺序

作用域退出时：

```text
1. 逆序执行 defer 链；
2. 逆序 Drop 剩余局部值（普通拥有值）；
3. 区域/帧释放（S11/S14 PopDrop）。
```

- `defer` 与 `Drop` 的相对顺序固定为 **defer 先**；defer 可以消费尚未 Drop 的局部；
- 同一作用域内多个 defer 逆序；嵌套作用域内层先于外层；
- 区域释放（`region R { ... }`）按 S11 逆序释放根位置，defer 在块退出前执行；
- 失败路径（`?`/`return`/`break`）与正常路径使用同一顺序。

---

## 5. 诊断

| 情形 | 诊断 |
|---|---|
| 线性值未被 release/defer/move | `E-LS-LEAK` |
| 同一线性值被 defer 两次 | `E-LS-MOVE` / `E-LS-LEAK` |
| `release` 返回值被静默丢弃 | `E-LS-LEAK` / `E-LS-DROP` |
| defer 捕获短寿命 `ref` | `E-LS-REGION-ESCAPE` |
| defer 在 comptime | `E-LS-COMPTIME` |
| 跨 FFI 的 release 约定缺失 | `E-LS-ABI` |

---

## 6. 检查器现状

checker-spike 已有：

- `E-LS-LEAK`：`let _ = x;` 且 `x` 是 `DmaToken`/`Cap[...]` 参数；
- `E-LS-DIAL`：`#[bounds(off)]` 无契约（与资源无关，但同属模块旋钮）。

未实现：

- defer 链的数据流/逆序执行检查；
- `#[must_release]` 的 definite-release；
- 错误路径的泄漏计数；
- `release` 返回值处理检查。

> 当前 `dossiers/slab/accept.ls` 的 `defer dma.wait()` 只有语法/人工证据，
> 不能声称“defer 泄漏检查已实现”。

---

## 7. 未决

| # | 项 | 归属 |
|---|---|---|
| R-1 | defer 捕获语义（move vs 借用）的完整形式化 | S0′ |
| R-2 | defer 与 panic/abort 的交互（v0 固定为不执行） | S3 |
| R-3 | `#[must_release]` 在 agent 的隐式 Drop 策略 | S1 |
| R-4 | defer 的编译期展开与代码大小成本 | S1 |
| R-5 | 与 RAII/Drop 的语义差（defer 是一次性表达式） | 已定 |
