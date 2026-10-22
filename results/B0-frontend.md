# B0.2 · B-LS 前端解耦（函数级声明表 + 检查/emit 分离）

> 状态：**B0 的第二增量完成**（声明侧表 + 三遍前端），`emit` 仍单遍走源码（B0 剩余债务）。
> 日期：2026-10-22
> 上位：[`MEMORY.md`](../MEMORY.md) 的 B0 条目（B-LS 接入策略）、[`bootstrap/src/README.md`](../bootstrap/src/README.md)、
> [`spec/bls.md`](../spec/bls.md)、[`spec/ub.md`](../spec/ub.md)（诊断码登记）。

## 目标

B0 要求「至少增加函数级 AST/类型侧表，把『解析/检查』与『直接 emit』分开；**先保持固定点不变**」。
本增量在 `bootstrap/src/names_stage.ls` 中把原来「一个 `prescan_fns` 边扫边写 `post`」拆成三遍：

| pass | 作用 | 是否产生代码 |
|---|---|---|
| `scan_funcs` | 一次词法扫描，建**函数声明表**（签名 span、参数个数、返回码、**body span**、参数 span） | 否 |
| `check_decls` | 表上的声明检查：`E-LS-DUP` / `E-LS-MAIN`（两处）/ 函数上限；并发布 arity 到 `post[30000+nid]` | 否 |
| `check_calls` | 表上的调用检查：遍历每个 body span，对**已声明函数**的调用核对实参个数（`E-LS-ARITY`） | 否 |

`emit_expr`/`emit_*` 与单遍 parser 一行未改；它们仍按源码走，但**不再拥有签名表的唯一副本**，
调用点 arity 失败也由前端提前报出（原来只在 emit 阶段报）。

## 声明表布局（`fdecl`，`Slice[Int]`，1024 槽）

```text
fd[0] = count
base = 1 + k * 8:
  +0 name_start   +1 name_len   +2 nparams   +3 ret_code
  +4 body_start   +5 body_end   +6 params_start  +7 params_end
```

`ret_code` 与调用点既有编码一致（1 = `Int`，2 = `U8`，3 = `Str`，9 = 其它/未知）。
`body_start`/`body_end` 是**匹配花括号**的 span（扫描时跳过字符串、行注释、块注释），
这就是后续 B2（词法作用域）可以直接使用的函数边界表；`params_start/end` 留给 B4 的参数类型表。

## 保持固定点不变的证据

**逐字节回归**（79 个输入：`bootstrap/bls/tests/*.ls` + `bootstrap/src/*.ls`，用 seed 解释器跑
修改前/后的 `names_stage.ls`，记录 `rc` + 输出 SHA-256 + stderr）：

```text
diff baseline new:
  只有 names_stage 自身不同（编译器源码变了 ⇒ 自编译产物必然变）
  其余 78 个输入的 rc / SHA-256 / stderr 完全一致
  其中 6 个输入本来就是 pre-existing reject（io / match / payload / slice_params / slices / unicode）
```

**负例行为**（`E-LS-ARITY`）：修改前输出 `E-LS-ARITY` 后还会继续到
`slice: bad expr`；现在由 `check_calls` 在前端直接报 `E-LS-ARITY` 并 `return 4`（单行）。
`bootstrap/ci/run-stage1.sh` 只 `grep -q 'E-LS-ARITY'`，因此该断言仍通过（QEMU 日志
`PASS B-LS call arity diagnostic`）。

**完整 QEMU CI**（`bash bootstrap/ci/run-qemu.sh`，QEMU TCG + 真 Linux 内核）：

```text
PASS B-LS duplicate function diagnostic
PASS B-LS main signature diagnostic
PASS B-LS main return diagnostic
PASS B-LS call arity diagnostic
...
eb70f747b7f4a9154d7eba3ebf7f26586b6781f3d8e6640db80403d3b2ada999  bootstrap/build/stage2_self
eb70f747b7f4a9154d7eba3ebf7f26586b6781f3d8e6640db80403d3b2ada999  bootstrap/build/stage3_self
PASS fixed point: stage2 == stage3
QEMU-GUEST: RESULT=PASS
```

固定点哈希由 `440e2188…ce29` 变为 **`eb70f747…a999`**：编译器源码变了，`stage2`/`stage3`
随之改变，但 **`stage2 == stage3` 仍成立**——这正是「先保持固定点不变」的含义
（被编译程序的产物不变；编译器自身的自编译产物随源码更新）。

## 与 B0 原计划的差距（剩余债务）

| 项 | 状态 |
|---|---|
| 函数级声明表（name/params/ret/body span） | ✅ 本增量 |
| 声明检查与 emit 分离（dup/main/limit/arity） | ✅ 本增量（arity 前移） |
| 语句/表达式 AST（`emit` 消费 AST 而非源码 token） | ❌ 仍是单遍直接 emit，是 B0 剩余的主要债务 |
| `region`/`Buffer`/`val`/`ref`/`eff`/`requires`/`ensures`/`comptime` 的 AST 字段 | ❌ `preflight` 仍统一拒绝（`E-LS-UNSUPPORTED`），属 B1/B2/B3 |
| 参数类型表（供泛型实参/约束） | 🟡 `params_start/end` 已留槽；类型解析仍由 parser 现算 |

## 复现

```bash
# 1) 逐字节回归（Windows/MinGW 也可）
for f in bootstrap/bls/tests/*.ls bootstrap/src/*.ls; do
  ./bootstrap/seed/seed.exe --run bootstrap/src/names_stage.ls "$f" /tmp/out
  sha256sum /tmp/out
done
# 修改前后对比：只有 names_stage 的产物不同

# 2) 语义回归
bash bootstrap/ci/run-interp.sh

# 3) 完整固定点（QEMU；首次会下载 ~250 MiB）
QEMU_TIMEOUT=2400 bash bootstrap/ci/run-qemu.sh
```

## 变更文件

- `bootstrap/src/names_stage.ls`：`prescan_fns` → `scan_funcs` + `check_decls` + `check_calls`
  （新增 `fd_find` 表查找）；`main` 的 `fsig` 数组换成 `fdecl`，pipeline 改为三遍；
  各 pass 注释写明「B0.2」。
- `bootstrap/src/README.md`：状态表加前端 pass 行、固定点哈希更新。
- `spec/freeze-manifest.md`：固定点记录更新（实现文件本身不在冻结列表内，无需重冻结；
  `freeze-hash --check` 仍绿）。
- `MEMORY.md`：B0 条目、固定点哈希、时间线。
