// EXPECT: E-LS-EFFECT
// Q4 / effects.md §4.1: a function that terminates Unsafe must be a safe
// wrapper.  Exposing rawptr in the signature violates condition 1, so Unsafe
// cannot be dropped from eff(...); with eff(Write) the declaration is rejected.
fn bad_wrapper(cap: Cap[Unsafe], p: rawptr[U8]) -> U8 eff(Write) {
    unsafe { *p }
}
