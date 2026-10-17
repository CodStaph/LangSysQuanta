// B-LS M1b-3c: local Slice view over an Array[U8].
fn main() -> Int {
    let buf: Array[U8, 8] = Array.zeroed();
    buf[0] = 72;
    buf[1] = 105;
    let s: Slice[U8] = slice(buf, 0, 2);
    if s.len == 2 {
        write("slice ok\n");
    }
    return s[0] + s[1];
}
