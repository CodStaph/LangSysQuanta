fn parse(src: val[Str]) -> Result[Ast, Error]           // 只读共享
fn mutate(dst: ref[Buf]) -> Unit eff(Write)             // 线程内独占借用
fn send(q: iso[Queue]) -> Unit eff(Spawn)               // 跨域独占转移
fn freeze(q: iso[Queue]) -> val[Queue]                  // 冻结（单向）
fn reuse(q: val[Queue]) -> iso[Queue] { recover { q } } // 线性恢复（要求别名全部消费）
