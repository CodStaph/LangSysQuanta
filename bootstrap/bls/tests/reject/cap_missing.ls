// B5-10: declaring `alloc` requires a Cap[Alloc] token parameter.
fn bad() -> Int eff(alloc) {
    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    return b.len;
}
fn main() -> Int { return 7; }
