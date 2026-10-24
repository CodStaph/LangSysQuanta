// B-LS B3-5a: Buffer[Int] index write value must be Int.
fn main() -> Int {
    let s: Str = "x";
    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    b[0] = s;
    return 0;
}
