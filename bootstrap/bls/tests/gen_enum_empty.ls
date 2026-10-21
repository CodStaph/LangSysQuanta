// Stage 2: typed let + Empty variant of a user generic enum.
enum Box[T] { Box(T), Empty }
fn main() -> Int {
    let b: Box[Int] = Box.Empty;
    match b {
        Box.Box(v) => { return v; },
        Box.Empty => { return 9; }
    }
    return 0;
}
