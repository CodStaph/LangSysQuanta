fn set(ref s: Str) -> Int { s = "xyz"; return s.len; }
fn copy(ref s: Str, t: Str) -> Int { s = t; return s.len; }
fn byte_at(ref s: Str, i: Int) -> Int { return s[i]; }
fn main() -> Int {
    let s: Str = "abc";
    let t: Str = "hell";
    if set(s) != 3 { return 1; }
    if s.len != 3 { return 2; }
    if copy(s, t) != 4 { return 3; }
    if s.len != 4 { return 4; }
    if byte_at(s, 0) != 104 { return 5; }
    if byte_at(s, 1) != 101 { return 6; }
    return 7;
}
