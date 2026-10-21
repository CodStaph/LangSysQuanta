// EXPECT: E-LS-RACE
// R6 negative (W1): a plain read of an `atom` place.
//
// R6-read requires atomOk(p).  The tail expression reads `c` outside any
// atomic(...) or lock guard, so atomOk fails.
// Note: `shared[Atomic[T]]` would still need an atomic method; `shared[T]`
// is lock-semantics only and has no atomicOps.
// Rule: semantics.md §2.3.7.
fn r6_shared_plain_read(c: shared[U64]) -> U64 {
    c                               // E-LS-RACE
}
