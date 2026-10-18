// Q4 / effects.md §4.1 positive: a safe wrapper does not expose rawptr,
// has an explicit Cap[Unsafe] value, and is covered by #[trusted].
// Therefore Unsafe is terminated and eff(Write) is accepted.
#[trusted]
fn good_wrapper(cap: Cap[Unsafe], x: U32) -> U32 eff(Write) {
    unsafe { x }
}
