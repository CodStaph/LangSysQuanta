// Regression: && / || must combine both operands, including nested slices.
fn check(src: Slice[U8], st: Slice[Int], n: Int) -> Int {
    if n == 3 && src[st[0]] == 115 { return 201; }
    if src[st[0]] == 115 || src[st[0]] == 102 { return 202; }
    return 203;
}

fn main() -> Int {
    let s: Array[U8, 8] = Array.zeroed();
    let st: Array[Int, 4] = Array.zeroed();
    s[0] = 102;
    s[1] = 110;
    s[2] = 0;
    let ss: Slice[U8] = slice(s, 0, 3);
    let sts: Slice[Int] = slice(st, 0, 4);
    return check(ss, sts, 3);
}
