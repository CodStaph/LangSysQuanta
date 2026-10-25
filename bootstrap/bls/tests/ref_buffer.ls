fn fill(ref b: Buffer[Int]) -> Int {
    b.push(1);
    b[0] = 7;
    return b.len + b[0] + b.cap;
}
fn len_of(ref b: Buffer[Int]) -> Int { return b.len; }
fn main() -> Int {
    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    if fill(b) != 10 { return 1; }
    if len_of(b) != 1 { return 2; }
    if b[0] != 7 { return 3; }
    return 7;
}
