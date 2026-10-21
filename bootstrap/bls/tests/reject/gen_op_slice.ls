fn add[T](a: T, b: T) -> T { return a + b; }
fn main() -> Int {
    let buf: Array[U8, 4] = Array.zeroed();
    let v: Slice[U8] = slice(buf, 0, 2);
    let u = add(v, v);
    return 0;
}
