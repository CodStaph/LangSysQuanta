// EXPECT: E-LS-RACE
// R8 negative (W1): `val` across a domain fails the region constraint.
//
// R8-transfer:
//   m = frozen  ⇒  C' = C ∪ { thread ⊑ Rgn(v) }
//
// Here Rgn(v) = region(A), and region(A) ⊑ thread is false (A is nested inside
// thread, not above it), so solve(C) = Err.  This is the case a naive
// "frozen is shared, therefore thread-safe" implementation would wrongly accept.
// Rule: semantics.md §2.3.9; lattice §2.4.
struct Config { depth: U32 }

fn use_cfg(c: val[Config]) -> U32 { c.depth }

fn r8_val_local_region() eff(Alloc, Spawn) {
    region A {
        let a: Alloc[Region] = A.allocator();
        let c: box[Config] = a.alloc(Config { depth: 4 });
        let v: val[Config] = freeze c;
        let h = spawn use_cfg(v);        // E-LS-RACE: thread ⊑ region(A) fails
        join(h);
    }
}
