# B7 · 用户 trait / impl + struct 值比较派生（B-LS/stage1）

> **状态**：**完成（2026-10-31）**。
> 范围：R2.3「泛型剩余项——用户 `trait`/`impl`」：用户 `trait` 声明与
> `impl Trait for Ty` 注册表、struct 值六比较运算符经 impl 方法的**静态分派**
> （callee 侧拷贝 ABI）、自定义 trait 作为泛型 bound（`[A: MyTrait]`）。
> 验收依据：`bootstrap/ci/run-stage1.sh`（Windows 本机全绿，含新增 B7 断言段：
> 2 个 interpreted accept + 5 个 reject 诊断）；QEMU/TCG 全量 §5：
> `PASS compiled stage1_trait_eq_ord -> exit 9`、
> `PASS compiled stage1_trait_bound -> exit 7`，固定点 `stage2 == stage3`，
> SHA-256 **`0b217692550f3e1a60c07a7163dd91a21e22f4a00c917215098f8140209fe584`**，
> `QEMU-GUEST: RESULT=PASS`（需 `QEMU_TIMEOUT=7200`，全程约 77 分钟）；
> `names_stage` 自编译产物 887072 B（源码 536773 B）。

## 1. 表面语法（B-LS 子集）

```text
trait Show { fn render; }                      // 声明只登记（≤16）；块内签名不是函数
impl Eq for Point { fn eq(a: ref Point, b: ref Point) -> Int { ... } }
impl Ord for Point { fn lt(a: ref Point, b: ref Point) -> Int { ... } }
fn mk[A: Copy](v: ref A, out: ref A) -> Int { ... }     // 内置 trait bound
fn report[A: Show](v: ref Int) -> Int { ... }           // 用户 trait bound
```

- 方法形参写法 `ref a: Point`（修饰符在名字前，`08 §trait_item` 与
  `spec/bls.md` §2.3 一致；`a: ref[Point]` 不是 B-LS 表面写法）。
- 方法进入**扁平命名空间**（不挂在类型下），因此 `eq`/`lt` 名与既有函数
  一样受 `E-LS-DUP` 复查；`(trait, type)` 对最多一个 impl（`E-LS-COHERENCE`）。

## 2. 注册表（`post`，双表）

| 表 | 计数槽 | 行布局 | 上限 |
|---|---|---|---|
| trait | `post[135690]` | `135694+ti*2` = `{src_off}`、`135695+ti*2` = `{src_len}` | 16 |
| impl | `post[135748]` | `135752+ri*4` = `{tc, ty, 方法名 name id, fd 索引}` | 12 |

- 内置 trait 码：`tc` = 1 Ord / 2 Eq / 3 Num / 4 Add / 5 Copy；用户 = **16+ti**
  （trait 名经 trait 行 `{src_off,src_len}` 与源字节比对解析，无第二名字表）。
- 类型码 `ty` = 2 Int / 8 U8 / 30+si struct（复用 B5-12 struct 类型码）。
- 组合校验：Eq/Ord/Copy 仅用户 struct；用户 trait 允 Int/U8/struct；Num/Add 拒。
- 拒绝面：内置名/表满（`E-LS-DUP: trait name is predefined`）、坏 impl 头
  （`impl target - Eq/Ord/Copy ...`）、`(tc,ty)` 重复
  （`E-LS-COHERENCE: duplicate impl`）、trait 块畸形
  （`E-LS-UNSUPPORTED: trait block is malformed`）。

## 3. 静态分派（调用约定）

- **调用侧**（`push_binop` 拦截 op 6..11 且 `t1==t2 ∈ 30..99`）：
  - 按 op 类查 impl 行（6/7 → tc=2 Eq；8..11 → tc=1 Ord）；无行 →
    `E-LS-NO-IMPL: struct comparison has no impl of Eq/Ord for this type`。
  - 两操作数各经 kind 89（`lea rax,[rip+sv槽偏移]`）压栈；kind 93 发射
    `pop rsi`（第二参）、`pop rdi`（第一参；op 9/10 加 `xchg rsi,rdi`）、
    `call rel32`（fn patch 用方法名 id，走 `fname[]`/`flabel[]` 既有解析）；
    op 7/9/11 尾随 `xor eax,1`；结果 `push rax`。
  - 派生规则：`==`→`eq`；`!=`→`eq`+取反；`<`→`lt(a,b)`；`<=`→¬`lt(b,a)`；
    `>`→`lt(b,a)`；`>=`→¬`lt(a,b)`；命中行填 `post[100000+mi]=op`。
- **callee 序言**（结构 ref 参数的拷贝 ABI）：`sv_add(ps, pid, ctxi[NF], off|(n<<31), pe-30)`
  在 `off` 起 `st_size` 字节；随后逐 8 字节 `mov rax,[reg+w3*8]`（reg0..3：
  `48 8b 47/46/42/41+disp8`）→ `mov [rip+off+w3*8],rax`（`48 89 05`，
  记数据重定位）。约束：reg>3 拒（参数须坐前 4 槽），`st_size` 非 8 的倍数拒
  （`E-LS-UNSUPPORTED: struct ref parameters need an 8-byte-aligned layout`）。
  方法体 `a.x` 复用既有 sv 字段通道（无新表达式路径）。

## 4. 泛型 bound（`[A: MyTrait]` / `[A: Copy]`）

- `bound_code`（4 参含 post）与 `bound_ok`（单趟实现）：`req >= 16` 扫 impl 行
  `(req, at)`；`req == 5`（Copy）全过；两处在 `scan_generic_list` 与
  `scan_sigs`（where）同步接入。
- Trait 上限 16 / impl 上限 12 → bound 解析次受表容量约束（超限在声明期拒绝）。

## 5. 容量 / QA / QEMU

### 5.1 容量

| 项 | R3.6 基线 | B7 后 |
|---|---|---|
| sast 自编译计数 | 17076 | ≈ 17531（+1 `return`；守卫 17600） |
| `sast` 区 |`post[141024..245023]`（104000） | `post[141024..247135]`（106112 ints） |
| `ctxi` 基址 | 245024 | 247136（CUR_SEND、call patch 簿记同步） |
| 重定位表基址 | 248000 | 249248 |
| `scan_funcs` 参数 | 4（两 Slice+两 Slice+Int = 7 槽超 ABI） | 3（5 槽；`fd` 体内 `slice_at(post,140000,1024)` 派生） |

- 名字表（~759 名）words 已伸到 ~17520：本轮把编译器 scratch 从 `post[17008]`
  迁到 `post[135700]`——原地址写穿条目 #503（`emit_jmp` 双重 intern）。
  **落在 [16002, ~17520) 的固定小偏移今后必须先审计**。
- 测试：`stage1_trait_eq_ord`（六算符全派生，exit 9）、`stage1_trait_bound`
  （trait bound 双面，exit 7）；reject 5 件：`bls_no_impl`/`bls_dup_impl`/
  `bls_impl_target`/`bls_trait_clash`/`bls_struct_param`。

### 5.2 关键 bug（QEMU 才暴露，修法记录）

首轮 QEMU 在 compiled 段挂：`stage1_trait_eq_ord` 期望 exit 9 实际不符
（解释断言只查 `test -s`，从未验证产物行为）。反汇编产物
（`ndisasm -b 64 -o 0x400000`）发现 call 现场被**双重消费**：
`… pop rsi; pop rdi; call eq; push rax;` 之后又出现
`pop rcx; pop rax; cmp rax,rcx; setz`——第二次比较发生在**空栈**上。
根因：`push_binop` 的 B7 拦截成功分支（push kind 93 后）**缺 `return 0;`**，
控制流 fall-through 到末尾 `else push_post(2, op)`，IR 栈重复追加普通比较项。
修复＝拦截成功后提前 return（见 `names_stage.ls` push_binop 注释）；
修复后六个调用现场（`call eq/lt + xchg/xor`）单次消费，反汇编静态校验
与手工模拟（p=(3,4)、q=(3,5) 六比较全过）exit 9，第二轮 QEMU 全绿。

### 5.3 QEMU

- 第一轮：`run-stage1 FAILED at line 725`（`stage1_trait_eq_ord` compiled 退出码错）
  → 定位为 §5.2 的 fell-through bug，修复；
- 第二轮：`QEMU-GUEST: RESULT=PASS`；`PASS compiled stage1_trait_eq_ord -> exit 9`；
  `PASS compiled stage1_trait_bound -> exit 7`；
  `PASS fixed point: stage2 == stage3`（SHA-256 见顶部状态块）；
- 既有 79+ 输入逐字节回归、自编译双跑字节级确定性均在两轮前后验证。

## 6. 边界（不足清单）

1. 分派只有**静态**：无 vtable/字典传递，泛型函数内的 `==` 仍要求参数解析到
   具体 struct（`gen_*` 内比较仍拒）；`.eq`/`.lt` 不能显式调用（只能经运算符）。
2. 用户 trait 方法体签名不参与检查（`fn render;` 只是占位）；trait 不支持
   默认实现、 consts、关联类型、super-trait、孤儿规则；`(tc,ty)` 无跨模块合并。
3. `E-LS-NO-IMPL` 为单行朴素格式（诊断码 + 消息），未升 R3.6 两行结构；
   位置/fix-it 留待下一诊断批次（CI grep 兼容不受影响）。
4. 比较 impl 方法只按 `{tc,ty}` 的**首个注册**实例取行；`Eq` 实现 `lt` 语义
   （或反之）不被检出（无契约检查）。
5. trait bound 的 `bound_ok` 扫全 impl 行（≤12）O(n)；表满即在声明期拒绝，
   错误码与「内置名 clash」共用 `E-LS-DUP` 文本前缀。

> AI生成
