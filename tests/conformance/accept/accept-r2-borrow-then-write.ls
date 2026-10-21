// R2 positive (W1): a reborrow is scoped.
//
// The borrow region is ρ_s = local(borrow-site), and R2-borrow requires
// ρ_s ⊑ ρ_p.  S7 (BorrowEnd) removes y and b from Σ, so after the block
//
//     Holders(Σ', b) = ∅   and   live(Λ', p[0]) = ∅
//
// and the following write is accepted.  Rule: semantics.md §2.3.3.
fn r2_borrow_then_write() eff(Alloc, Write) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let p: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        borrow mut p[0] as r {
            r += 1;              // only the mut alias writes while it is alive
        };
        p[0] = 2;                // OK: borrow ended, Λ was cleared by S7
    }
}
