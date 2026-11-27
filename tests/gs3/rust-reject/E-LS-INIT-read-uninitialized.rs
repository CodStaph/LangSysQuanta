// EXPECT-RUSTC: E0381
// Rust counterpart of E-LS-INIT-read-uninitialized:
// using a value before any assignment reaches it.
struct Point { x: i32, y: i32 }

fn bad_init() {
    let p: Point;
    let q = p.x;
    let _ = q;
}
