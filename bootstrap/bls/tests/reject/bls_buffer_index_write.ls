// B-LS B3-4a: Buffer[Int] index write is not implemented (b[i] is read-only).
fn main() -> Int {
    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    b[0] = 5;
    return 0;
}
