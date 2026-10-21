// R5 positive (W1): write permission is region-scoped, not global.
//
// A frozen alias lives in region A; the written place lives in a sibling
// region B.  Two independent reasons make the write legal:
//
//   1. no borrow overlaps `buf_b[0]`, so Aliases*(Σ, buf_b[0]) = ∅;
//   2. even if an alias did overlap, A and B are siblings (A ⊑ B is false).
//
// This is the "negative space" test: it FAILS if a checker treats the alias
// table as global ("some val exists somewhere ⇒ reject all writes").
// Rule: spec/semantics.md §2.3.6 (R5-writable), R5 is region-level (00 §4.4).
fn r5_two_regions_disjoint() eff(Alloc, Write) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let buf_a: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        let va: val[Array[Int, 4]] = freeze buf_a;   // frozen alias @ A

        region B {
            let b: Alloc[Region] = B.allocator();
            let buf_b: box[Array[Int, 4]] = b.alloc(Array.zeroed());
            buf_b[0] = 1;                            // OK: ρ_alias = A is not ⊑ ρ_place = B
            let x = va[0] + buf_b[0];
        }
    }
}
