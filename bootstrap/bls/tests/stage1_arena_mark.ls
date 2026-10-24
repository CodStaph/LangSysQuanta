// R4.4: explicit mark/rewind for multi-allocation LIFO reclamation.
fn main() -> Int {
    if arena_mark() != 0 { return 1; }
    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    if arena_used() != 48 { return 2; }
    let m = arena_mark();
    if m != 48 { return 3; }

    let a: Str = "xy";
    let r: Result[Str, AllocError] = str_try_concat(a, a);   // 4 B -> aligned 8
    if arena_used() != 56 { return 4; }
    if arena_rewind(m) != 0 { return 5; }
    if arena_used() != 48 { return 6; }
    if arena_stat(3) != 1 { return 7; }     // reclaims
    if arena_stat(0) != 56 { return 8; }    // peak retained

    if b.release() != 0 { return 9; }       // buffer below the mark still valid
    if arena_used() != 0 { return 10; }
    if arena_rewind(1000) != 0 - 1 { return 11; }
    if arena_rewind(0) != 0 { return 12; }

    // Inside a region, rewinding below the region mark is rejected.
    if arena_alloc(8) != 0 { return 13; }
    let e = 0;
    region R {
        let c: Buffer[Int] = Buffer.new[Int](2, R);
        if arena_rewind(0) != 0 - 1 { e = 14; }
        if arena_rewind(8) != 0 { e = 15; }
    }
    if e != 0 { return e; }
    if arena_used() != 8 { return 16; }
    return 7;
}
