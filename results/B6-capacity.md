# B6 · source/code 容量扩展

> 状态：**完成（2026-10-25）**。QEMU/TCG 全量固定点 `80e12183…79ce`，`stage2 == stage3`，
> `QEMU-GUEST: RESULT=PASS`。
> 上位：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md)、[`bootstrap/src/README.md`](../bootstrap/src/README.md)、
> [`results/B5-3-ref-buffer.md`](B5-3-ref-buffer.md)。
> 目的：B5 后 stage1 源码 456307 B、生成代码 767983 B，已接近旧上限
> （source 458752 / code 786432 / out 900000）；先扩容，避免下一步语言特性再次撞墙。

## 1. 新布局

```text
membuf[2293760]:
  source [0,        655360)   640 KiB
  code   [655360,  2228224)   1.5 MiB
  data   [2228224, 2293760)   64 KiB

out[1900000]                  1.81 MiB（filetotal 上限）
```

| 项 | 旧 | 新 |
|---|---:|---:|
| source | 458752 | **655360** |
| code | 786432 | **1572864** |
| data | 65536 | 65536 |
| membuf | 1310720 | **2293760** |
| out / filetotal | 900000 | **1900000** |
| post | 360000 | 360000（不变） |

`out` 取 1900000：最大 `filetotal = 120 + code(1572864) + static data(65536) = 1638520`，
留 ~260 KB 余量。宿主解释器 `data[]` 为 16 MiB；当前 stage1 数组总量约 7.1 MiB。

## 2. 修改点

- `bootstrap/src/names_stage.ls` 中所有 `membuf` 偏移/长度：
  - `slice_at(mem, 0, n)` 不变；
  - `c = slice_at(mem, 458752, 786432)` → `(655360, 1572864)`；
  - `ds = slice_at(mem, 1245184, 65536)` → `(2228224, 65536)`；
  - `membuf[1310720]` → `[2293760]`；
  - `read_file(..., 458752)` / `n >= 458752` → `655360`；
  - `out[900000]` / `filetotal > 900000` / `slice(out, 0, 900000)` → `1900000`。
- 注释中的 layout 同步更新。
- 未改 `post`/`sast`/`ctxi`/patch 表布局（B5-2 已扩到 `post=360000`）。

## 3. 验收

- 本机 `bootstrap/build.sh` PASS；`names_stage` 自编译 PASS，输出 767983 B；
- QEMU/TCG **全量** `run-stage1.sh`：
  - 所有已编译测试通过；
  - `PASS fixed point: stage2 == stage3`，固定点 **`80e12183…79ce`**；
  - `QEMU-GUEST: RESULT=PASS`；
- B5 正/负例（`ref_int`/`ref_str_slice`/`ref_buffer`/`ref_slice_index` 与 reject）全部通过；
- `run-interp.sh`、`tools/check-docs.sh`、`freeze-hash --check` 全绿。

## 4. 边界

- 扩容只改变编译器的缓冲上限/数据布局，不改变语言语义；
- 生成 ELF 的 memsz 增大（`membuf`/`out` 是 BSS），文件字节数不变（仍 767983 B）；
- 固定点因数据布局变化而变化，属预期；
- 下一轮若继续增加 stage1 代码，source 仍有约 199 KB、code 约 804 KB、out 约 1.13 MB 余量。

**下一步**：B5-4（Str/Slice ref 写入、`ref Str[i]`、引用类型/生命周期）或 `mode`/cap/effect、
契约/非空 `comptime`、struct/`Error`、结构化诊断。
