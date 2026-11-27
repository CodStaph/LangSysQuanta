// Boundary positive (TM-0, spec/test-matrix.md §3.2): whole-value move where
// only the target is used afterwards — one step from
// reject/E-LS-MOVE-rebind-after-move.ls (which rebinds the moved source).
// Rule: semantics.md R1 (move clears the source; later target use is fine).
fn accept_move_use_target() eff(Alloc, Read) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let b: box[Array[Int, 2]] = a.alloc(Array.zeroed());
        let c = move b;
        let x: Int = c[0];         // OK: uses the target, never the source
    }
}
