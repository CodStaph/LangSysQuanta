# spec/image.md · 镜像格式、验签与加载协议

> **状态**：`草稿`（§0 不变量与 §7 加载流程已冻结；§2–§5 的字段级布局为本文件新增，待评审冻结）
> **上位**：[`00 §6.12`](../00-LangSysQuanta-设计初稿.md)（镜像/加载/cap 授予）、
> [`02 ADR-16`](../02-架构评审与ADR.md)（加载器密钥：Ed25519 + 双层 + 防回滚）、`02 §4.3`（完整协议）。
> **相关**：`H-LS-12`（稳定 ABI）、`H-LS-22`、`H-LS-26`（密钥托管是运维边界）、
> 风险 `LS-19`（`image.md` 无法验签/复现 ⇒ **S2 不得启动**）。
> **定位**：加载器属于 TCB（`00 §8.0` L4/L5）。本文件是 S2 的准入条件，第三方应能据此实现。

## 0. 不变量（不可协商）

| # | 不变量 | 违反后果 |
|---|---|---|
| I-1 | **cap 表在签名区内**，无例外 | `LC-SIGN` |
| I-2 | `Mmio` 范围除 cap 表外还必须通过**平台签名清单** | `LC-MMIO`；防止应用自授任意物理地址 |
| I-3 | 生产加载器**拒绝 dev 镜像**（`flags.bit0`） | `LC-DEV` |
| I-4 | `version` 单调；`version < version_floor` 一律拒绝 | `LC-ROLLBACK` |
| I-5 | 签名区**不含时间戳**（`SOURCE_DATE_EPOCH`） | 破坏可复现 |
| I-6 | 加载器内置 **≤ 2 个 root 公钥**，不做在线吊销 | `LC-CERT` |

## 1. 布局

```text
+--------------------------------------------------------------+ 0
| header (128 B, 小端)                                          |
+--------------------------------------------------------------+
| segment table (seg_count x 32 B)                              |
+--------------------------------------------------------------+
| payload: segments (text | rodata | data | bss | stack | vectors) |
+--------------------------------------------------------------+
| cap table (cap_count x 32 B)          <- 签名区（I-1）        |
+--------------------------------------------------------------+
| cert_len (4 B) | cert chain | signature (64 B)                |
+--------------------------------------------------------------+
```

**签名区** = `header` + `segment table` + `cap table` + `build_fingerprint`
（与 ADR-16 第 3 条一致）。证书链与签名字段本身不在签名区内。

## 2. Header（128 字节）

| off | size | 字段 | 取值 / 语义 |
|---|---|---|---|
| 0 | 4 | `magic` | `0x4C53494D`（ASCII `LSIM`） |
| 4 | 2 | `header_ver` | 头部版本，v0 = `1` |
| 6 | 2 | `header_len` | 固定 `128` |
| 8 | 8 | `version` | 单调版本号（防回滚，见 §6） |
| 16 | 1 | `alg` | `1` = Ed25519（保留以便升级） |
| 17 | 1 | `profile` | `1` = agent，`2` = kernel |
| 18 | 2 | `abi` | ABI 版本；不匹配 ⇒ `LC-ABI` |
| 20 | 4 | `edition` | edition id；不匹配 ⇒ `LC-ABI` |
| 24 | 8 | `entry` | 入口虚地址（必须在某个 `text` 段内） |
| 32 | 8 | `stack_bound` | 静态栈上界（字节，`03 §4.1` 同源） |
| 40 | 2 | `seg_count` | 段表项数 |
| 42 | 2 | `cap_count` | cap 表项数 |
| 44 | 4 | `flags` | bit0 = `dev`；其余保留为 0 |
| 48 | 32 | `build_fingerprint` | SHA-256（构建输入指纹，可复现校验） |
| 80 | 16 | `key_id` | build key 标识（对应证书链） |
| 96 | 32 | `reserved` | 必须为 0 |

## 3. 段表（`seg_count × 32` 字节）

| off | size | 字段 | 语义 |
|---|---|---|---|
| 0 | 8 | `vaddr` | 目标虚拟地址 |
| 8 | 8 | `file_off` | 文件内偏移（`bss` 为 0） |
| 16 | 8 | `memsz` | 内存大小（`bss` 用此字段扩展） |
| 24 | 1 | `perm` | R=1, W=2, X=4（组合） |
| 25 | 1 | `kind` | 1=text 2=rodata 3=data 4=bss 5=stack 6=vectors |
| 26 | 6 | `reserved` | 0 |

段权限必须与 `kind` 一致：`text` 必须含 `X` 且不含 `W`；`rodata` 只读；`vectors` 只读、
置于 `vaddr` 最低区。**`W` 且 `X` 同时置位 ⇒ `LC-SEG`。**

## 4. Cap 表（`cap_count × 32` 字节，签名区内）

| off | size | 字段 | 语义 |
|---|---|---|---|
| 0 | 1 | `kind` | 1=`Unsafe` 2=`Alloc` 3=`Dma` 4=`Irq` 5=`Mmio` |
| 1 | 1 | `rights` | 位掩码（读/写/执行/委托，v0 只用 bit0–3） |
| 2 | 6 | `reserved` | 0 |
| 8 | 8 | `range_start` | `Mmio`/`Dma` 的起点；其他 kind 为 0 |
| 16 | 8 | `range_end` | 结束（开区间）；其他 kind 为 0 |
| 24 | 8 | `params` | `Irq` 的中断号 / `Alloc` 的预算上限 |

- `Mmio` 项必须**同时**出现在平台签名清单中（I-2），否则 `LC-MMIO`；
- `Unsafe`/`Alloc` 的授予是**一次性**的：运行时不能再自我提权（`E-LS-CAP` 的静态面）。

## 5. 签名与证书链

| 项 | 规定 |
|---|---|
| 算法 | Ed25519（确定性 ⇒ 可复现） |
| 签名覆盖 | 见 §1 的「签名区」定义 |
| 证书结构 | `build_pub`(32) ‖ `root_id`(1) ‖ `root_sig`(64) ‖ pad(7) = **104 B** |
| 证书校验 | `root_sig` 必须由内置 `root_id` 对应公钥对 `build_pub` 的签名 |
| 尾部 | `cert_len`(4) ‖ cert chain（`cert_len` 字节） ‖ `signature`(64) |
| 轮换 | 允许 `1..2` 层证书；任一内置 root 可验证即通过（ADR-16 第 2 条） |

> 签名区**不含**证书与签名字段本身；也不含时间戳（I-5）。

## 6. 防回滚

- 安全存储中维护单调 `version_floor`（不可被应用写入）；
- `header.version < version_floor` ⇒ `LC-ROLLBACK`，不加载；
- 加载成功后若 `version >= version_floor`，可（按平台策略）提升 `version_floor = version`；
- **不做在线吊销**：新加载器 + 内置 advisory（`H-LS-26` 把密钥托管登记为运维边界）。

## 7. 加载器伪代码（TCB，必须可照实现）

```c
// 返回 0 表示成功；非 0 为拒绝码（见下表）。任何失败都不得留下可执行映射。
enum lc {
    LC_OK = 0, LC_MAGIC, LC_HDR, LC_ABI, LC_DEV, LC_SIGN, LC_CERT,
    LC_MMIO, LC_ROLLBACK, LC_SEG, LC_MAP, LC_ENTRY
};

int load_image(const struct hdr *h, const struct seg *segs,
               const struct cap *caps, const u8 *cert, size_t cert_len,
               const u8 *sig)
{
    // 1. 结构校验
    if (h->magic != 0x4C53494D)          return LC_MAGIC;
    if (h->header_ver != 1 || h->header_len != 128) return LC_HDR;
    if (h->alg != 1)                     return LC_HDR;

    // 2. 兼容性（I-3 之前先判 ABI，避免无谓验签开销）
    if (h->abi != ABI_VERSION || h->edition != EDITION_ID) return LC_ABI;
    if ((h->flags & FLAG_DEV) && !DEV_BUILD_ALLOWED)        return LC_DEV;

    // 3. 证书链 + 验签（签名区 = header ‖ segs ‖ caps ‖ fingerprint）
    if (!verify_cert_chain(cert, cert_len, h->key_id))      return LC_CERT;
    if (!ed25519_verify(build_pub, signed_region(h), sig))  return LC_SIGN;

    // 4. 防回滚（I-4）
    if (h->version < read_version_floor())                  return LC_ROLLBACK;

    // 5. 段权限自洽（§3）：W+X ⇒ 拒绝
    for (i = 0; i < h->seg_count; i++)
        if ((segs[i].perm & PERM_W) && (segs[i].perm & PERM_X)) return LC_SEG;

    // 6. cap 表：Mmio 需平台清单二次确认（I-2）
    for (i = 0; i < h->cap_count; i++)
        if (caps[i].kind == CAP_MMIO &&
            !platform_allows(caps[i].range_start, caps[i].range_end))
            return LC_MMIO;

    // 7. 映射（只由 cap 表驱动；不采信程序自述的地址）
    if (map_segments(h, segs) != 0)                         return LC_MAP;
    grant_caps(h, caps);

    // 8. 入口必须落在 text 段内
    if (!in_exec_segment(h->entry, segs))                   return LC_ENTRY;

    // 9. 预算从 header 读取后交给运行时
    rt_set_stack_bound(h->stack_bound);
    return LC_OK;
}
```

| 拒绝码 | 触发条件 | 对应不变量 / 验收项 |
|---|---|---|
| `LC-MAGIC` / `LC-HDR` | 幻数、头部版本、算法不符 | — |
| `LC-ABI` | `abi`/`edition` 不匹配 | — |
| `LC-DEV` | 生产加载器遇到 `flags.dev` | I-3 |
| `LC-SIGN` | 签名校验失败（含 **cap 表被篡改**） | I-1 |
| `LC-CERT` | 证书链无法链到内置 root（含轮换后旧链） | I-6 |
| `LC-MMIO` | `Mmio` 范围不在平台签名清单 | I-2 |
| `LC-ROLLBACK` | `version < version_floor` | I-4 |
| `LC-SEG` | 段权限自相矛盾（`W`+`X`） | §3 |
| `LC-MAP` / `LC-ENTRY` | 映射失败 / 入口不在 text 段 | — |

> 拒绝码是**加载期**命名空间（`LC-*`），与编译期诊断码（`E-LS-*`）不混用。

## 8. 四负例（ADR-16 验收，必须有可执行用例）

| # | 场景 | 期望 | 覆盖 |
|---|---|---|---|
| N-1 | 篡改 cap 表（签名后改 `rights` 或加一项） | `LC-SIGN` | I-1 |
| N-2 | dev 镜像交给生产加载器 | `LC-DEV` | I-3 |
| N-3 | 回滚镜像（`version` 低于 floor） | `LC-ROLLBACK` | I-4 |
| N-4 | 证书链的 root 不在内置列表（轮换后旧/伪造链） | `LC-CERT` | I-6 |

补充负例（非 ADR-16 必选，但已在伪代码中覆盖）：`W`+`X` 段 → `LC-SEG`；
`Mmio` 越出平台清单 → `LC-MMIO`。

## 9. `ls image --verify` 规格（离线校验）

```bash
ls image --verify build/app.img             # 退出码 0/非 0，打印 LC-* 或 OK
ls image --verify --root root.pub app.img   # 用指定 root 复验证书链
ls image --fingerprint app.img              # 打印 build_fingerprint
```

- `--verify` 必须复用与加载器**同一份**校验实现（避免「工具通过、加载器拒绝」）；
- `--fingerprint` 供复现比对：两个构建机产出相同指纹 + 逐位相同镜像（ADR-16 验收第 2 条）。

## 10. 待办

- [ ] §2–§5 的字段级布局走评审后标记「冻结」（当前为草案）；
- [ ] 与 `spec/coherence.md` 交叉：`dyn` vtable ABI 是否进入签名区；
- [ ] `rights` 位掩码的最终定义（v0 只用 bit0–3）；
- [ ] 四负例的测试载体：需要在 S2 有 loader 仿真器（`dossiers/` 风格的最小实现）；
- [ ] 平台签名清单的格式与验签（loader 持有，属于板级 TCB，不在本文件定义）；
- [ ] 轮换场景的完整用例（新 root 签发的链必须通过，旧 root 链的处置需明确）。
