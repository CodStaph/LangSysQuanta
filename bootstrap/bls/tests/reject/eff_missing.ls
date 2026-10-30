// B5-10: `eff(pure)` must not allocate.
fn bad() -> Int eff(pure) {
    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    return b.len;
}
fn main() -> Int { return 7; }
