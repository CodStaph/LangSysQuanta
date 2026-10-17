// B-LS M1c-0a: Slice parameters.
fn sum2(s: Slice[U8]) -> Int {
    if s.len != 2 {
        return -1;
    }
    return s[0] + s[1];
}

fn main() -> Int {
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = 72;
    buf[1] = 105;
    let s: Slice[U8] = slice(buf, 0, 2);
    write("sparam ok\n");
    return sum2(s);
}
