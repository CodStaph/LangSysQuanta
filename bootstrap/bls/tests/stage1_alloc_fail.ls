// R4.5: allocation-failure paths, `?` propagation and recovery.
fn get_buf(cap: Int) -> Result[Buffer[Int], AllocError] {
    let r: Result[Buffer[Int], AllocError] = Buffer.try_new[Int](cap, heap);
    let b: Buffer[Int] = r?;
    return Result.Ok(b);
}

fn cat(a: Str, b: Str) -> Result[Str, AllocError] {
    let s: Str = str_try_concat(a, b)?;
    return Result.Ok(s);
}

fn cat_ok(a: Str, b: Str) -> Int {
    let r: Result[Str, AllocError] = cat(a, b);
    match r {
        Result.Ok(s) => { return s.len; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn cat_err(a: Str, b: Str) -> Int {
    let r: Result[Str, AllocError] = cat(a, b);
    match r {
        Result.Ok(s) => { return 1; },
        Result.Err(e) => { return e + 1; }
    }
}

fn buf_ok(cap: Int) -> Int {
    let r: Result[Buffer[Int], AllocError] = get_buf(cap);
    match r {
        Result.Ok(b) => { return b.cap; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn buf_err(cap: Int) -> Int {
    let r: Result[Buffer[Int], AllocError] = get_buf(cap);
    match r {
        Result.Ok(b) => { return 1; },
        Result.Err(e) => { return e + 1; }
    }
}

fn concat_cap_err(x: Slice[U8], y: Slice[U8], o: Slice[U8]) -> Int {
    let r: Result[Slice[U8], AllocError] = concat_into(x, y, o);
    match r {
        Result.Ok(s) => { return 1; },
        Result.Err(e) => { return e + 1; }
    }
}

fn main() -> Int {
    let a: Str = "ab";
    let b: Str = "cd";

    // Ok paths (including `?` unboxing of Str and Buffer).
    if cat_ok(a, b) != 4 { return 1; }
    if buf_ok(2) != 2 { return 2; }

    // Fill the arena: Str/Buffer allocation fails and `?` propagates Err(-1).
    let bud = arena_budget() - arena_used();
    arena_alloc(bud);
    let used = arena_used();
    if cat_err(a, b) != 0 { return 3; }
    if buf_err(2) != 0 { return 4; }
    if arena_used() != used { return 5; }

    // Raw arena allocation fails cleanly; rejects are counted.
    arena_reset();
    let big = arena_budget() + 1;
    if arena_alloc(big) != 0 - 1 { return 6; }
    if arena_stat(2) != 3 { return 7; }     // str + buffer + arena_alloc

    // concat_into capacity failure returns Err and writes nothing.
    let outa: Array[U8, 1] = Array.zeroed();
    let ra: Array[U8, 2] = Array.zeroed();
    let rb: Array[U8, 2] = Array.zeroed();
    let o: Slice[U8] = slice(outa, 0, 1);
    let x: Slice[U8] = slice(ra, 0, 2);
    let y: Slice[U8] = slice(rb, 0, 2);
    if concat_cap_err(x, y, o) != 0 { return 8; }
    if outa[0] != 0 { return 9; }

    // Recovery: after reset the same operations succeed again.
    arena_reset();
    if cat_ok(a, b) != 4 { return 10; }
    return 7;
}
