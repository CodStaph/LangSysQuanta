// B0.3a: slice_at(src, off, len) — sub-view of a Slice/Str, off in elements.
fn main() -> Int {
    let buf: Array[U8, 8] = Array.zeroed();
    buf[0] = 1; buf[1] = 2; buf[2] = 3; buf[3] = 4;
    buf[4] = 5; buf[5] = 6; buf[6] = 7; buf[7] = 8;
    let s: Slice[U8] = slice(buf, 0, 8);
    let t: Slice[U8] = slice_at(s, 2, 3);      // 3,4,5
    let u: Slice[U8] = slice_at(t, 1, 2);      // 4,5

    let iv: Array[Int, 4] = Array.zeroed();
    iv[0] = 10; iv[1] = 20; iv[2] = 30; iv[3] = 40;
    let si: Slice[Int] = slice(iv, 0, 4);
    let ti: Slice[Int] = slice_at(si, 1, 2);   // 20,30

    let str: Str = "abcdef";
    let bs: Slice[U8] = slice_at(str, 2, 2);   // "cd"

    return (t[0] + t[2]) * 10 + u[1] + ti[0] / 10 + (bs[0] - 99) + (bs[1] - 99);
}
