# bootstrap/src · stage1（B-LS）

**状态**：未开始。M1 完成后在此写第一版 L-Sys 编译器。

计划文件：

```text
main.ls  lexer.ls  parser.ls  ast.ls  resolve.ls  types.ls
ir.ls  codegen_x86_64.ls  elf.ls  arena.ls  vec.ls  map.ls  diag.ls
```

约束见 [`spec/bls.md`](../../spec/bls.md)：
无 region 推断、无泛型/trait/闭包、arena + `u32` 索引、整程序编译。
