// Combined positive (TM-0, D-TM-3): region scoping + borrow + write-back +
// post-region return, all legal together.
//
// Rules stacked (>=3, spec/test-matrix.md §4):
//   region A { ... }                  region scoping        (00 §4.1)
//   borrow mut p[0] as r { r += n }   R2 borrow liveness    (semantics §2.3.3)
//   p[0] += 1 (after borrow ends)     R5 writable place     (semantics §2.3.6)
//   requires/ensures n >= 0 / result >= n   contract clauses
// The value crosses the region boundary BY COPY (no return from inside the
// region), so no E-LS-REGION-ESCAPE fires.
fn combined_region_borrow_contract(n: Int) -> Int eff(Alloc, Write)
    requires n >= 0
    ensures result >= n
{
    let out: Int = n;
    region A {
        let a: Alloc[Region] = A.allocator();
        let p: box[Array[Int, 2]] = a.alloc(Array.zeroed());
        borrow mut p[0] as r {
            r += n;
        };
        p[0] += 1;                 // OK: borrow ended (S7 BorrowEnd)
    }
    return out;                    // OK: by-value, no region carry
}
