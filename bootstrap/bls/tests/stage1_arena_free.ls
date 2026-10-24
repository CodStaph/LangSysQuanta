// R4.6: general free (arbitrary order), hole reuse and coalescing.
fn main() -> Int {
    let a: Buffer[Int] = Buffer.new[Int](2, heap);   // 0..48
    let b: Buffer[Int] = Buffer.new[Int](2, heap);   // 48..96
    let c: Buffer[Int] = Buffer.new[Int](2, heap);   // 96..144
    if arena_used() != 144 { return 1; }

    // Arbitrary-order release: b is not the arena top.
    if b.release() != 0 { return 2; }
    if arena_used() != 144 { return 3; }

    // Hole reuse: the new buffer takes b's 48-byte hole.
    let d: Buffer[Int] = Buffer.new[Int](2, heap);
    if arena_used() != 144 { return 4; }
    if d.release() != 0 { return 5; }

    // a (0..48) and d (48..96) are adjacent free holes -> coalesced to 96 B.
    let e: Buffer[Int] = Buffer.new[Int](6, heap);   // needs 32 + 48 = 80
    if e.cap != 6 { return 6; }
    if arena_used() != 144 { return 7; }
    if e.release() != 0 { return 8; }

    // c is the top right now: release rewinds instead of using the free list.
    if c.release() != 0 { return 9; }
    if arena_used() != 96 { return 10; }

    // Rewind purges the holes above the new top.
    if arena_rewind(0) != 0 { return 11; }
    if arena_used() != 0 { return 12; }
    let f: Buffer[Int] = Buffer.new[Int](2, heap);
    if arena_used() != 48 { return 13; }
    if f.release() != 0 { return 14; }
    if arena_used() != 0 { return 15; }

    // Raw arena blocks can be freed/reused explicitly.
    let p = arena_alloc(16);
    if p != 0 { return 16; }
    if arena_free(p, 16) != 0 { return 17; }
    if arena_alloc(16) != 0 { return 18; }
    if arena_coalesce() != 0 { return 19; }

    // Reclamation counter: b,d,e,c,rewind,f,arena_free = 7.
    if arena_stat(3) != 7 { return 20; }
    return 7;
}
