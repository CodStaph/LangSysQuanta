// B5-5: ref Slice assignment requires a matching Slice.
fn bad(ref s: Slice[U8], v: Int) -> Int { s = v; return 0; }
fn main() -> Int {
    let a: Array[U8, 2] = Array.zeroed();
    let x: Slice[U8] = slice(a, 0, 2);
    return bad(x, 1);
}
