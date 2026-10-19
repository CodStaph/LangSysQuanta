// R5 positive (W1): region-level does not mean "the whole region is read-only".
//
// Freeze `p[0]`; `p[1]` is a disjoint place in the same region A.
//
//     live(Λ, p[1]) = ∅   ⇒   Aliases*(Σ, p[1]) = ∅   ⇒   writable(p[1])
//
// A checker that marks the whole allocation (or the whole region) frozen after
// one `freeze` would wrongly reject this.  Rule: semantics.md §2.3.6.
fn r5_sibling_index_write() eff(Alloc, Write) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let p: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        let v0: val[Int] = freeze p[0];   // mode(p[0]) := frozen; p[1] stays uniq
        p[1] = 7;                         // OK: sibling place, no overlap
        let s = v0 + p[1];
    }
}
