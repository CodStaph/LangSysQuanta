// B5-5: ref Slice descriptor assignment and index write.
fn vlen(ref s: Slice[U8]) -> Int { return s.len; }
fn retarget(ref s: Slice[U8], t: Slice[U8]) -> Int { s = t; return s.len; }
fn set0(ref s: Slice[U8], v: Int) -> Int { s[1] = v; return s[1]; }
fn iset(ref s: Slice[Int], v: Int) -> Int { s[1] = v; return s[1]; }

fn main() -> Int {
    let a: Array[U8, 4] = Array.zeroed();
    let b: Array[U8, 2] = Array.zeroed();
    let x: Slice[U8] = slice(a, 0, 4);
    let y: Slice[U8] = slice(b, 0, 2);
    if retarget(x, y) != 2 { return 1; }
    if vlen(x) != 2 { return 2; }
    if set0(x, 200) != 200 { return 3; }
    if b[1] != 200 { return 4; }
    let c: Array[Int, 3] = Array.zeroed();
    let z: Slice[Int] = slice(c, 0, 3);
    if iset(z, 1234) != 1234 { return 5; }
    if c[1] != 1234 { return 6; }
    return 7;
}
