// B3-4a: Buffer[Int] read indexing -> buffer_get; out-of-range yields -1.
fn ok_first() -> Int {
    let r: Result[Buffer[Int], Int] = Buffer.try_new[Int](2, heap);
    match r {
        Result.Ok(c) => { return c.push(5) + c[0]; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn main() -> Int {
    let b: Buffer[Int] = Buffer.new[Int](4, heap);
    b.push(11);
    b.push(22);
    b.push(33);
    let n = b.len;
    if b[0] != 11 { return 1; }
    if b[1] != 22 { return 2; }
    if b[n - 1] != 33 { return 3; }
    if b[3] != 0 - 1 { return 4; }
    if b[n] != 0 - 1 { return 5; }
    if b[99] != 0 - 1 { return 6; }
    if b[0] + b[1] + b[2] != 66 { return 8; }
    if ok_first() != 6 { return 9; }
    return 7;
}
