// EXPECT-RUSTC: E0133
// Rust counterpart of E-LS-EFFECT-boundary-drops-unsafe:
// a function with a safe signature calling an unsafe callee without an
// unsafe boundary is rejected.
unsafe fn boundary_helper(x: u32) -> u32 {
    x
}

fn boundary_bad(x: u32) -> u32 {
    boundary_helper(x)
}
