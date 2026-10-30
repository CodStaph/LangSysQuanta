// B5-10: a caller must declare the boundary effects of its callees.
fn alloc_fn(c: Cap[Alloc]) -> Int eff(alloc) {
    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    return b.len;
}
fn caller() -> Int eff(pure) {
    let d: Cap[Alloc] = 0;
    return alloc_fn(d);
}
fn main() -> Int { return 7; }
