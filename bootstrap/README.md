# bootstrap/ · 无 LLVM / 无 Rust 依赖链

> 计划：[`05-Bootstrap-实施计划.md`](../05-Bootstrap-实施计划.md)；
> 方言：[`spec/bls.md`](../spec/bls.md)。
> 状态：**M0 已落地**（seed + hello ELF）；stage1 未开始。

## 依赖

- 构建 seed：一个 C 编译器（`CC` 环境变量，默认 `clang`）；
- 运行 seed：宿主 OS；
- **不需要**：libc（Linux 路径）、`as`、`ld`、LLVM、Rust、Cargo、Make/CMake。

## 快速开始

```bash
./bootstrap/build.sh
```

- Windows/MSYS：构建 `seed/seed.exe`，生成 `build/hello`（ELF64），不执行；
- Linux：构建 `seed/seed`（freestanding），生成并执行 `build/hello`；
- 可选：`llvm-readelf`/`llvm-objdump` 验证 ELF。

## 布局

```text
bootstrap/
  seed/seed.c          # stage0 C seed（M0）
  bls/tests/hello.ls   # 第一个 B-LS 程序
  src/                 # stage1（B-LS，未开始）
  build.sh             # 唯一构建脚本
  build/               # 产物（git 忽略）
```

## M0 能做什么

```ls
fn main() -> Int {
    write("hello from L-Sys bootstrap\n");
    return 0;
}
```

生成 x86_64 Linux 静态 ELF：`write(2)` + `exit(2)`，不依赖 libc/as/ld。

## 已验证

- `clang` 在 Windows 宿主构建 seed，生成 ELF64；
- `llvm-readelf` 显示 `ET_EXEC` / `EM_X86_64` / `PT_LOAD`，entry 正确；
- `llvm-objdump` 反汇编确认 `write`/`exit` 系统调用与字符串地址；
- `clang --target=x86_64-unknown-linux-gnu -nostdlib` 交叉构建 seed 通过。

## 未验证

- Linux 上实际执行 `build/hello`（本机无 WSL/QEMU）；
- stage1 自举（M1+）。

## 下一步

1. 把 M1 语法（struct/enum/if/while/函数调用）加进 seed；
2. 在 `bootstrap/src` 写 stage1（B-LS），先编译 `hello.ls`，再自编译；
3. 固定点：`stage1 == stage2`；
4. 按 `05 §5` 逐步加入 L-Sys 特性。
