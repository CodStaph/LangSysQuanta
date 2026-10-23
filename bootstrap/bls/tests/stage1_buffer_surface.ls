// B3-2b: Buffer[Int] surface syntax over the runtime builtins.
fn main() -> Int {
    let b: Buffer[Int] = Buffer.new[Int](4, heap);
    if b.len != 0 { return 1; }
    if b.cap != 4 { return 2; }
    b.push(11);
    b.push(22);
    if b.len != 2 { return 3; }
    return 7;
}
