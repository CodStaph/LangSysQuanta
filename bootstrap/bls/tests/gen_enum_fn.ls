// Stage 2: user generic enum in a function return type.
enum Box[T] { Box(T), Empty }
fn make(x: Int) -> Box[Int] {
    if x == 0 { return Box.Empty; }
    return Box.Box(7);
}
fn main() -> Int {
    let b = make(1);
    match b {
        Box.Box(v) => { return v; },
        Box.Empty => { return 9; }
    }
    return 0;
}
