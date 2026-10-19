// EXPECT: E-LS-RACE
// R6 negative (W1): a plain write to an `atom` place.
//
// R6-atom requires  atomicOp(E) ∨ (lockCtx(E) ∧ rankOk(E)).
// A bare assignment is neither, so atomOk(p) fails and R5-atom cannot fire.
// Rule: semantics.md §2.3.7.
fn r6_shared_plain_write(c: shared[U64]) {
    c = 1;                          // E-LS-RACE
}
