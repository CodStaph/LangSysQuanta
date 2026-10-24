// R4.7: per-region hard quota (`region R(cap) { ... }`).
fn try_str() -> Int {
    let sa: Str = "abcd";
    let sb: Str = "efgh";
    let r: Result[Str, AllocError] = str_try_concat(sa, sb);
    match r {
        Result.Ok(s) => { return 1; },
        Result.Err(e) => { return e + 1; }
    }
}

fn main() -> Int {
    let total = arena_budget();

    // Exact fill: the global arena has room, but the region stops at 128.
    region A(128) {
        if region_limit() != 128 { return 1; }
        if arena_budget() != 128 { return 2; }
        if region_used() != 0 { return 3; }
        let a: Buffer[Int] = Buffer.new[Int](2, heap);   // 48
        let b: Buffer[Int] = Buffer.new[Int](2, heap);   // 48 -> used 96
        if arena_used() != 96 { return 4; }
        let c: Buffer[Int] = Buffer.new[Int](2, heap);   // needs 144 > 128
        if c >= 0 { return 5; }
        if arena_used() != 96 { return 6; }
        if arena_alloc(40) >= 0 { return 7; }            // 136 > 128
        if arena_alloc(32) < 0 { return 8; }             // exactly 128
        if region_used() != 128 { return 9; }
        if region_limit() != 128 { return 10; }
        if try_str() != 0 { return 11; }                 // Str shares the limit
        if arena_used() != 128 { return 12; }
    }
    if arena_used() != 0 { return 13; }
    if region_limit() != total { return 14; }
    if arena_budget() != total { return 15; }

    // Nested quota is relative to the inner entry mark and never exceeds the
    // enclosing region's effective end.
    region B(200) {
        let a: Buffer[Int] = Buffer.new[Int](2, heap);   // 48
        region Inner(64) {
            if region_limit() != 64 { return 16; }
            let d: Buffer[Int] = Buffer.new[Int](2, heap);  // 48 -> used 96
            if arena_used() != 96 { return 17; }
            let e: Buffer[Int] = Buffer.new[Int](2, heap);  // needs 144 > 112
            if e >= 0 { return 18; }
        }
        if region_limit() != 200 { return 19; }
        let b: Buffer[Int] = Buffer.new[Int](2, heap);   // 48 -> used 96
        if arena_used() != 96 { return 20; }
    }
    if arena_used() != 0 { return 21; }
    if region_limit() != total { return 22; }

    // c, arena_alloc(40), try_str and e were rejected.
    if arena_stat(2) != 4 { return 23; }
    return 7;
}
