// Stage 2: generic function with boxed Slice[U8].
fn id[T](x: T) -> T { return x; }
fn main() -> Int {
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = 4;
    buf[1] = 6;
    let v: Slice[U8] = slice(buf, 0, 2);
    let y = id(v);
    return y[0] + y[1];
}
