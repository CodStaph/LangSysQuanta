fn serve(sock: ref[Socket]) -> Result[Unit, Error] eff(Io, Alloc, Block) { ... }
fn pure_add(a: Int, b: Int) -> Int { a + b }            // 默认 Pure
fn push(r: ref[Ring], v: U8) -> Result[Unit, Error]
    requires r.count <= r.buf.len
    ensures  Ok(_) => r.count == old(r.count) + 1
eff(Write)
