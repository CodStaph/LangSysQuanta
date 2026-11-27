// EXPECT-RUSTC: E0506
// Rust counterpart of E-LS-ALIAS-r5-nested-write-site:
// the offending write sits in a nested block, but the borrow is evaluated
// against the place, not the write site (rustc: E0506 at the assignment).
fn r5_nested_write_site(v: &mut [i32; 4]) {
    let r = &mut v[0];
    {
        v[0] = 1;
        *r += 1;
    }
}
