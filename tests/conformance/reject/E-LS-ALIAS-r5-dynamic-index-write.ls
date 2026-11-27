// EXPECT: E-LS-ALIAS
// ALIAS negative (TM-0): dynamic-index borrow over the whole array place.
//
// Equivalence class: alias source = borrow(mut, index), access = write to a
// DIFFERENT index expression.  The index is not statically known, so the
// checker must be conservative: any write to p[_] while the borrow is live
// is rejected (place region = A, alias region ⊑ A, R5-writable fails).
// Rule: semantics.md §2.3.3/§2.3.6 (conservative alias coverage).
fn r5_dynamic_index_alias() eff(Alloc, Write) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let p: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        let i: Int = 0;
        borrow mut p[i] as r {
            let j: Int = 1;
            p[j] = 2;              // E-LS-ALIAS: unknown index => whole place covered
            r += 1;
        }
    }
}
