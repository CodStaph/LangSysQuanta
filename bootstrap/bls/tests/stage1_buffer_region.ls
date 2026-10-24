// B3-4c: region ownership: region-scoped buffers auto-release at block exit.
// Region frames are runtime frames: a callee's region nests inside the
// caller's region and unwinds back to the caller's mark.
fn alloc_inside() -> Int {
    let e = 0;
    let before = arena_used();
    region S {
        let b: Buffer[Int] = Buffer.new[Int](2, S);
        b.push(7);
        if b.len != 1 { e = 1; }
        if arena_used() <= before { e = 2; }
    }
    if arena_used() != before { e = 3; }
    return e;
}

// (B3-4c rejects `return` inside a region, so errors are collected in `err`.)
fn main() -> Int {
    if arena_used() != 0 { return 1; }

    // A region owns its allocations: they are released when it exits.
    let err = 0;
    region R {
        let b: Buffer[Int] = Buffer.new[Int](4, R);
        b.push(11);
        if b.len != 1 { err = 2; }
        if arena_used() == 0 { err = 3; }
    }
    if err != 0 { return err; }
    if arena_used() != 0 { return 4; }

    // Nested regions release in LIFO order.
    region A {
        let a: Buffer[Int] = Buffer.new[Int](2, A);
        let ua = arena_used();
        region B {
            let c: Buffer[Int] = Buffer.new[Int](2, B);
            if arena_used() <= ua { err = 5; }
        }
        if arena_used() != ua { err = 6; }
    }
    if err != 0 { return err; }
    if arena_used() != 0 { return 7; }

    // A root buffer cannot be released from inside a region (owner mismatch).
    let root: Buffer[Int] = Buffer.new[Int](2, heap);
    let ru = arena_used();
    region C {
        if root.release() != 0 - 1 { err = 8; }
        if arena_used() != ru { err = 9; }
    }
    if err != 0 { return err; }
    if arena_used() != ru { return 10; }
    if root.release() != 0 { return 11; }
    if arena_used() != 0 { return 12; }

    // Explicit release inside a region still works; exit is idempotent.
    region D {
        let d: Buffer[Int] = Buffer.new[Int](2, D);
        if d.release() != 0 { err = 13; }
        if arena_used() != 0 { err = 14; }
    }
    if err != 0 { return err; }
    if arena_used() != 0 { return 15; }

    // Cross-function nesting: callee region unwinds to the caller's mark.
    let u0 = 0;
    region N {
        let a: Buffer[Int] = Buffer.new[Int](2, N);
        u0 = arena_used();
        if alloc_inside() != 0 { err = 16; }
        if arena_used() != u0 { err = 17; }
    }
    if err != 0 { return err; }
    if arena_used() != 0 { return 18; }

    return 7;
}
