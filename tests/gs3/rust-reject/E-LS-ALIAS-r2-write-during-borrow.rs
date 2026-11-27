// EXPECT-RUSTC: E0506
// Rust counterpart of E-LS-ALIAS-r2-write-during-borrow:
// writing through the owner while a mutable borrow is alive
// (rustc reports the assignment site as E0506).
fn r2_write_during_borrow(v: &mut [i32; 4]) {
    let r = &mut v[0];
    v[0] = 1;
    *r += 1;
}
