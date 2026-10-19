// EXPECT: E-LS-ALIAS
// R5 negative (W1): writing a frozen place.
//
// R3-freeze does two things:
//   Λ += (b, p[0], frozen, ρ_p)   and   mode(p[0]) := frozen
//
// R5-writable then fails on both premises:
//   (a) m ∈ {uniq, mut} is false (m = frozen);
//   (b) Aliases*(Σ, p[0]) = {(p[0], b)} with B(b).m_b = frozen, ρ_b = ρ_p ⊑ ρ_p.
//
// Either premise is enough for E-LS-ALIAS.  Rule: semantics.md §2.3.4/§2.3.6.
fn r5_frozen_place_write() eff(Alloc, Write) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let p: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        let v = freeze p[0];
        p[0] = 1;                  // E-LS-ALIAS
        let s = v;
    }
}
