// EXPECT-RUSTC: E0369
// Rust counterpart of E-LS-MOVE-use-after-move:
// a whole-value move followed by a use of the moved-from binding
// (rustc surfaces the first hard use at the binary operation: E0369).
fn bad_move() {
    let b = Box::new(1i32);
    let c = b;
    let d = b;
    let _ = c + d;
}
