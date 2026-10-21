// Stage 2: user generic enum with boxed Slice[U8] payload.
enum Box[T] { Box(T), Empty }
fn main() -> Int {
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = 4;
    buf[1] = 6;
    let v: Slice[U8] = slice(buf, 0, 2);
    let b = Box.Box(v);
    match b {
        Box.Box(w) => { return w[0] + w[1]; },
        Box.Empty => { return 9; }
    }
    return 0;
}
