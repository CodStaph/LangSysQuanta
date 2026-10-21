// Stage 2: user generic enum with boxed Str payload.
enum Box[T] { Box(T), Empty }
fn main() -> Int {
    let s: Str = "ok";
    let b = Box.Box(s);
    match b {
        Box.Box(v) => { return v.len; },
        Box.Empty => { return 9; }
    }
    return 0;
}
