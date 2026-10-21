// Stage 2: user generic enum Box[T] inference.
enum Box[T] { Box(T), Empty }
fn main() -> Int {
    let b = Box.Box(1);
    match b {
        Box.Box(v) => { return v; },
        Box.Empty => { return 9; }
    }
    return 0;
}
