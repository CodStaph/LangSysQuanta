// B3-4b: Buffer.release / drop b + LIFO arena rewind.
fn realloc_ok() -> Int {
    let r: Result[Buffer[Int], Int] = Buffer.try_new[Int](4, heap);
    match r {
        Result.Ok(c) => { return c.cap + c.len; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn drop_stmt() -> Int {
    let before = arena_used();
    let d: Buffer[Int] = Buffer.new[Int](2, heap);
    d.push(9);
    drop d;
    if arena_used() != before { return 0 - 1; }
    return 0;
}

fn main() -> Int {
    let b: Buffer[Int] = Buffer.new[Int](4, heap);
    b.push(11);
    if arena_used() == 0 { return 1; }
    if b.release() != 0 { return 2; }
    if arena_used() != 0 { return 3; }

    // The released space is reusable (cap 4 -> 32 + 32 bytes).
    if realloc_ok() != 4 { return 4; }
    let used1 = arena_used();
    if used1 == 0 { return 5; }

    // Non-top release fails and leaves the arena unchanged; then unwind LIFO.
    let a: Buffer[Int] = Buffer.new[Int](2, heap);
    let c: Buffer[Int] = Buffer.new[Int](2, heap);
    // R4.6: non-top release now frees into the general free list (0, not -1).
    if a.release() != 0 { return 6; }
    if arena_used() != used1 + 96 { return 7; }
    if c.release() != 0 { return 8; }
    if arena_used() != used1 + 48 { return 9; }
    if a.release() != 0 { return 10; }
    if arena_used() != used1 { return 11; }

    // `drop b;` is the statement form of the same LIFO release.
    if drop_stmt() != 0 { return 12; }
    return 7;
}
