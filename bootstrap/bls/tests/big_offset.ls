// Regression: data offsets above the old 16 MB (24-bit) metadata limit.
// This is compiled by stage1/stage2, not run by the seed interpreter.
fn main() -> Int {
    let pad0: Array[U8, 1048576] = Array.zeroed();
    let pad1: Array[U8, 1048576] = Array.zeroed();
    let pad2: Array[U8, 1048576] = Array.zeroed();
    let pad3: Array[U8, 1048576] = Array.zeroed();
    let pad4: Array[U8, 1048576] = Array.zeroed();
    let pad5: Array[U8, 1048576] = Array.zeroed();
    let pad6: Array[U8, 1048576] = Array.zeroed();
    let pad7: Array[U8, 1048576] = Array.zeroed();
    let pad8: Array[U8, 1048576] = Array.zeroed();
    let pad9: Array[U8, 1048576] = Array.zeroed();
    let pad10: Array[U8, 1048576] = Array.zeroed();
    let pad11: Array[U8, 1048576] = Array.zeroed();
    let pad12: Array[U8, 1048576] = Array.zeroed();
    let pad13: Array[U8, 1048576] = Array.zeroed();
    let pad14: Array[U8, 1048576] = Array.zeroed();
    let pad15: Array[U8, 1048576] = Array.zeroed();
    let pad16: Array[U8, 1048576] = Array.zeroed();
    let vals: Array[Int, 4] = Array.zeroed();
    let s: Slice[Int] = slice(vals, 0, 4);
    s[0] = 7;
    s[1] = 9;
    s[2] = 11;
    s[3] = 13;
    return s[0] + s[1] + s[2] + s[3] + 137;
}
