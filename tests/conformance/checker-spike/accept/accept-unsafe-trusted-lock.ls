module test.trusted_lock;

// Q4 condition 3 via trusted.lock: no #[trusted] attribute, but the lock
// entry covers this module's public API with a matching content hash and a
// non-empty audit report hash.
fn locked_wrapper(cap: Cap[Unsafe], x: U32) -> U32 eff(Write) {
    unsafe { x }
}
