// B5-10: effect clauses, Cap tokens and `let val` frozen locals.
fn pure_add(x: Int, y: Int) -> Int eff(pure) {
    return x + y;
}

// read/write are internal effects: they may be inferred, not declared.
fn peek() -> Int eff(read) {
    if arena_used() < 0 { return 1; }
    return 0;
}

// Buffer reads/writes are also internal (no clause needed), but allocating the
// buffer is a boundary effect, so this one declares alloc + takes a Cap.
fn buf_peek(c: Cap[Alloc], n: Int) -> Int eff(alloc) {
    let b: Buffer[Int] = Buffer.new[Int](n, heap);
    b.push(7);
    b.push(8);
    if b.len != 2 { return 1; }
    if b[1] != 8 { return 2; }
    return 0;
}

// alloc is a boundary effect: it needs an explicit clause *and* a Cap token.
fn alloc_buf(c: Cap[Alloc], n: Int) -> Int eff(alloc) {
    let b: Buffer[Int] = Buffer.new[Int](n, heap);
    b.push(7);
    if b.len != 1 { return 1; }
    return 0;
}

// A caller that propagates an allocating callee must declare alloc too.
fn caller(c: Cap[Alloc], n: Int) -> Int eff(alloc) {
    let d: Cap[Alloc] = 0;
    return alloc_buf(d, n);
}

// `let val` binds a frozen local (read-only, aliasable).
fn frozen_local() -> Int {
    let val k = 5;
    let val m = k * 2;
    return k + m;
}

fn main() -> Int {
    let c: Cap[Alloc] = 0;
    if pure_add(1, 2) != 3 { return 1; }
    if peek() != 0 { return 2; }
    if buf_peek(c, 4) != 0 { return 6; }
    if alloc_buf(c, 4) != 0 { return 3; }
    if caller(c, 2) != 0 { return 4; }
    if frozen_local() != 15 { return 5; }
    return 7;
}
