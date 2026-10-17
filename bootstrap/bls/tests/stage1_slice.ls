// M1d-0b: Array/Slice support in stage1.
fn sum(s: Slice[U8]) -> Int {
    return s[0] + s[1];
}
fn main() -> Int {
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = 72;
    buf[1] = 105;
    let s: Slice[U8] = slice(buf, 0, 2);
    return sum(s);
}
