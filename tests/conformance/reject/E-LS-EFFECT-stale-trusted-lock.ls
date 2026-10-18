// EXPECT: E-LS-EFFECT
// Q4 condition 3 fails closed: trusted.lock has a stale content hash for this
// module, so the wrapper is not trusted and must keep Unsafe in eff(...).
module test.stale_lock;

fn stale_wrapper(cap: Cap[Unsafe], x: U32) -> U32 eff(Write) {
    unsafe { x }
}
