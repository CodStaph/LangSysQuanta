// B3-4a/B3-5a: Buffer[Int] index read/write (buffer_get/buffer_set).
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

    // B3-5a: writes are bounds-checked against len; out-of-range is ignored.
    b[0] = 99;
    b[2] = 55;
    if b[0] != 99 { return 10; }
    if b[n - 1] != 55 { return 11; }
    b[n] = 7;
    b[99] = 7;
    if b[0] != 99 { return 12; }
    if b.len != 3 { return 13; }
    if b[1] != 22 { return 14; }
    return 7;
}
