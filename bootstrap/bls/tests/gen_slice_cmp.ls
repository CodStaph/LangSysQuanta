// Stage 2: generic Slice[U8] elementwise/lexicographic comparison.
fn eq[T](a: T, b: T) -> Int { if a == b { return 1; } return 0; }
fn lt[T](a: T, b: T) -> Int { if a < b { return 1; } return 0; }
fn main() -> Int {
    let a: Array[U8, 4] = Array.zeroed();
    let b: Array[U8, 4] = Array.zeroed();
    a[0] = 1; a[1] = 2;
    b[0] = 1; b[1] = 3;
    let x: Slice[U8] = slice(a, 0, 2);
    let y: Slice[U8] = slice(b, 0, 2);
    let e = eq(x, x);
    let n = eq(x, y);
    let l = lt(x, y);
    if e == 1 && n == 0 && l == 1 { return 5; }
    return 9;
}
