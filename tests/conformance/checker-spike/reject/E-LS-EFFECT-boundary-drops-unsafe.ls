// EXPECT: E-LS-EFFECT
// Q4 / effects.md §3: the boundary trampoline drops Unsafe from its callee.
fn boundary_helper(x: U32) -> U32 eff(Unsafe) {
    x
}

#[boundary]
fn boundary_bad(x: U32) -> U32 eff(Write) {
    boundary_helper(x)
}
