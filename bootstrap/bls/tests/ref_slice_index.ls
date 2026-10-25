fn at(ref s: Slice[U8]) -> Int { return s[1]; }
fn iat(ref s: Slice[Int]) -> Int { return s[1]; }
fn main() -> Int {
    let a: Array[U8, 3] = Array.zeroed();
    a[1] = 9;
    let v: Slice[U8] = slice(a, 0, 3);
    if at(v) != 9 { return 1; }
    let b: Array[Int, 3] = Array.zeroed();
    b[1] = 7;
    let w: Slice[Int] = slice(b, 0, 3);
    if iat(w) != 7 { return 2; }
    return 7;
}
