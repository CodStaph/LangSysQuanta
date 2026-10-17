# bootstrap/src · stage1（B-LS）

**当前**：`main.ls` 实现 hello 子集（`write` + `return`），可被 seed 编译并由 `--run` 调试。

## M1c-3b 计划（calc）

stage1 还需：

1. **表达式**：数字/变量/`+ - * / %`/比较/括号；
   - 建议用**显式运算符栈（shunting-yard）→ 后缀**，避免 B-LS 递归；
   - 后缀数组 `Array[Int, N]`，每个 token 两项（kind, value/name/op）。
2. **变量**：名字打包为 8 字节 Int；变量槽在输出 ELF 数据段分配，`[rip+disp]` 回填。
3. **语句**：`let`、赋值、`if/else`、`while`；
   - 控制流用 `je/jmp` 占位 + 回填；
   - 复用 loop 栈处理 `break/continue`。
4. **codegen**：表达式走机器栈（push/pop），语句用 `dpos`/`jpos` 补丁表。
5. **验证**：
   - `--run` 跑 stage1 编译 `calc.ls`；
   - CI 执行 stage1 产物，校验 `calc ok` 与退出码 14。

## 约束

- 无递归：表达式用运算符栈，语句用显式块栈；
- 变量最多 64 个，表达式 token 最多 1024；
- 只支持 `Int`；数组/结构/枚举暂不进入 stage1 的第一版。
