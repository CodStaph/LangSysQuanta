// R4.7: handle table + moving compaction of live Buffer blocks.
fn main() -> Int {
    let a: Buffer[Int] = Buffer.new[Int](2, heap);   // handle 0, block 0..48
    let b: Buffer[Int] = Buffer.new[Int](2, heap);   // handle 1, block 48..96
    b.push(9);
    b.push(10);
    if arena_used() != 96 { return 1; }

    // Free the lower block: the live block sits above a 48-byte hole.
    if a.release() != 0 { return 2; }
    if arena_used() != 96 { return 3; }

    // Compaction moves b down to offset 0 and rewrites its handle entry.
    if arena_compact() != 1 { return 4; }
    if arena_used() != 48 { return 5; }
    if b.len != 2 { return 6; }
    if b[0] != 9 { return 7; }
    if b[1] != 10 { return 8; }

    // The handle is stable across the move; releasing still rewinds the top.
    if b.release() != 0 { return 9; }
    if arena_used() != 0 { return 10; }
    if arena_stat(3) != 3 { return 11; }   // a.release + 1 move + b.release

    // No live blocks: compaction is a no-op.
    if arena_compact() != 0 { return 12; }

    // Handle-table capacity: the 129th live Buffer fails, but the just-allocated
    // block must go back to the free list (it may have come from a hole).
    let i = 0;
    while i < 129 {
        let x: Buffer[Int] = Buffer.new[Int](1, heap);
        i = i + 1;
    }
    if arena_used() != 5160 { return 13; }
    arena_reset();
    if arena_used() != 0 { return 14; }
    return 7;
}
