// Stage 2: typed let with a user generic enum.
enum Box[T] { Box(T), Empty }
fn make() -> Box[Int] { return Box.Box(7); }
fn main() -> Int {
    let b: Box[Int] = make();
    match b {
        Box.Box(v) => { return v; },
        Box.Empty => { return 9; }
    }
    return 0;
}
