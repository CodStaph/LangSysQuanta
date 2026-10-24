// B5-2: assignment through ref Str is not implemented.
fn clear(ref s: Str, t: Str) -> Int { s = t; return 0; }
fn main() -> Int {
    let s: Str = "abc";
    let t: Str = "x";
    return clear(s, t);
}
