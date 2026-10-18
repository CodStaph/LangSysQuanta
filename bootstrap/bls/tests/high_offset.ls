// Regression: data offsets above 1 MB must survive Array/Slice metadata.
// Two 1 MB padding arrays push vals/s beyond the old 20-bit offset limit.
fn main() -> Int {
    let pad1: Array[U8, 1048576] = Array.zeroed();
    let pad2: Array[U8, 1048576] = Array.zeroed();
    let vals: Array[Int, 4] = Array.zeroed();
    let s: Slice[Int] = slice(vals, 0, 4);
    s[0] = 7;
    s[1] = 9;
    s[2] = 11;
    s[3] = 13;
    return s[0] + s[1] + s[2] + s[3] + 137;
}
