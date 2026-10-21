// EXPECT: E-LS-ALIAS
// R5 negative (W1, two regions): the check uses the *place* region, not the
// write site.
//
//   ρ_place(p[0]) = A
//   ρ_alias(r)    = local(borrow-site) ⊑ A     (R2-borrow)
//   B(b).m_b = mut ∈ {frozen, mut} ∧ ρ_b ⊑ ρ_place   (R5-writable fails)
//
// The write happens inside the nested region B, but that is irrelevant: R5 is
// evaluated against ρ_place = A.  A checker that used the ambient region (B)
// would wrongly accept this program.
// Rule: spec/semantics.md §2.3.6.
fn r5_nested_write_site() eff(Alloc, Write) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let p: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        borrow mut p[0] as r {
            region B {
                p[0] = 1;          // E-LS-ALIAS
                r += 1;
            }
        }
    }
}
