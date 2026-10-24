// R4.2: arena accounting + 8-byte-aligned Str allocation shared with Buffer.
fn concat2(a: Str, b: Str) -> Int {
    let r: Result[Str, AllocError] = str_try_concat(a, b);
    match r {
        Result.Ok(s) => { return s.len; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn try_big() -> Int {
    let big = arena_budget();
    let r: Result[Buffer[Int], AllocError] = Buffer.try_new[Int](big, heap);
    match r {
        Result.Ok(b) => { return 1; },
        Result.Err(e) => { return e + 1; }
    }
}

fn main() -> Int {
    let a: Str = "ab";
    let b: Str = "cd";

    if arena_stat(1) != 0 { return 1; }   // allocs
    if concat2(a, b) != 4 { return 2; }
    if arena_used() != 8 { return 3; }    // 4 bytes rounded up to 8
    if arena_stat(0) != 8 { return 4; }   // high_water
    if arena_stat(1) != 1 { return 5; }   // allocs

    // Buffer uses the same arena/budget/stats.
    let buf: Buffer[Int] = Buffer.new[Int](2, heap);
    if arena_used() != 8 + 48 { return 6; }
    if arena_stat(1) != 2 { return 7; }
    if arena_stat(0) != 56 { return 8; }
    if buf.release() != 0 { return 9; }
    if arena_used() != 8 { return 10; }
    if arena_stat(3) != 1 { return 11; }  // reclaims
    if arena_stat(0) != 56 { return 12; } // high_water is a peak

    // Direct arena_alloc shares the same counters.
    if arena_alloc(8) != 8 { return 13; }
    if arena_stat(1) != 3 { return 14; }
    if arena_used() != 16 { return 15; }
    arena_reset();
    if arena_stat(3) != 2 { return 16; }
    if arena_used() != 0 { return 17; }

    // A failed Buffer.try_new counts a rejection and leaves the arena empty.
    if try_big() != 0 { return 18; }
    if arena_stat(2) != 1 { return 19; }
    if arena_used() != 0 { return 20; }
    return 7;
}
