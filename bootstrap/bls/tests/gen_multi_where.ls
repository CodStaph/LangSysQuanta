// B4: `where` clause form of generic bounds.
fn min_where[A](a: A, b: A) -> A where A: Ord {
    if a < b { return a; }
    return b;
}
fn id_where[A](x: A) -> A where A: Eq { return x; }
fn main() -> Int {
    let s: Str = "abc";
    let t: Str = "ab";
    let m = min_where(3, 5);
    if m != 3 { return 1; }
    let z = min_where(s, t);
    if z.len != 2 { return 2; }
    let q = id_where(9);
    if q != 9 { return 3; }
    return 7;
}
