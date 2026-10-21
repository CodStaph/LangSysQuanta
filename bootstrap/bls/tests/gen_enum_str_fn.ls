// Stage 2: user generic enum Box[Str] in a function return type.
enum Box[T] { Box(T), Empty }
fn make() -> Box[Str] {
    let s: Str = "ok";
    return Box.Box(s);
}
fn main() -> Int {
    let b: Box[Str] = make();
    match b {
        Box.Box(v) => { return v.len; },
        Box.Empty => { return 9; }
    }
    return 0;
}
