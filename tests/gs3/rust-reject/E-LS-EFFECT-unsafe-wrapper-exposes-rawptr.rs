// EXPECT-RUSTC: E0133
// Rust counterpart of E-LS-EFFECT-unsafe-wrapper-exposes-rawptr:
// dereferencing a raw pointer requires an unsafe scope; a function with a
// safe-signature raw-pointer parameter that dereferences it internally is
// rejected.
fn bad_wrapper(p: *const u8) -> u8 {
    let v = *p;
    v
}
