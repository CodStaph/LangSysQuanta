// EXPECT-RUSTC: E0594
// Rust counterpart of E-LS-ALIAS-r5-frozen-place-write:
// an immutable borrow freezes the place; plain assignment is rejected.
fn r5_frozen_place_write(v: &[i32; 4]) {
    let sv = v;
    v[0] = 1;
    let s = sv;
    let _ = s;
}
