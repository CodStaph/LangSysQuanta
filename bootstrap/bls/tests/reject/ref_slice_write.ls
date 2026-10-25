// B5-4: assignment through ref Slice is still not implemented.
fn clear(ref s: Slice[U8], t: Slice[U8]) -> Int { s = t; return 0; }
fn main() -> Int {
    let a: Array[U8, 2] = Array.zeroed();
    let b: Array[U8, 2] = Array.zeroed();
    let x: Slice[U8] = slice(a, 0, 2);
    let y: Slice[U8] = slice(b, 0, 2);
    return clear(x, y);
}
