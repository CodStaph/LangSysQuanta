// EXPECT: E-LS-MOVE
// MOVE negative (TM-0): moved value used after a whole-value move
// (variable rebind form, ls-sem surface side; checker-spike has the
// box-move variant).
// Rule: semantics.md R1 move clears the source binding.
fn moved_then_rebind() eff(Alloc, Read) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let b: box[Array[Int, 2]] = a.alloc(Array.zeroed());
        let c = move b;
        let d = b;                 // E-LS-MOVE: `b` was moved
    }
}
