// EXPECT: E-LS-ALIAS
// R2/R5 negative (W1): writing through the owner while a mut alias is alive.
//
//   Λ contains (b, p[0], mut, ρ_s),  ρ_s = local(borrow-site) ⊑ ρ_p
//   Aliases*(Σ, p[0]) ∋ (r, b) with B(b).m_b = mut ⇒ R5-writable fails.
//
// The diagnostic comes from the write (R5), not from the borrow (R2): R2 itself
// is satisfied (uniq + uniqOk at the borrow site).
// Rule: semantics.md §2.3.3/§2.3.6.
fn r2_write_during_borrow() eff(Alloc, Write) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let p: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        borrow mut p[0] as r {
            p[0] = 1;              // E-LS-ALIAS
            r += 1;
        }
    }
}
