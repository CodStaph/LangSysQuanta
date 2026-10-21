fn boundary_helper(x: U32) -> U32 eff(Unsafe) {
    x
}

// Q4 / effects.md §3: a #[boundary] trampoline must take the union of callee
// effects.  Unsafe is kept in the trampoline signature.
#[boundary]
fn boundary_ok(x: U32) -> U32 eff(Write, Unsafe) {
    boundary_helper(x)
}
