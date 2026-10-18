// Regression: data offsets above the old 256 MiB (28-bit) metadata limit.
fn main() -> Int {
    let pad: Array[U8, 314572800] = Array.zeroed();
    let vals: Array[Int, 4] = Array.zeroed();
    let s: Slice[Int] = slice(vals, 0, 4);
    s[0] = 7;
    s[1] = 9;
    s[2] = 11;
    s[3] = 13;
    return s[0] + s[1] + s[2] + s[3] + 137;
}
