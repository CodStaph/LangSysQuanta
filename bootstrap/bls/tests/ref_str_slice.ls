// B5-2: ref Str/Slice read-only views and ref forwarding.
fn slen(ref s: Str) -> Int { return s.len; }
fn fwd(ref s: Str) -> Int { return slen(s); }
fn vlen(ref s: Slice[U8]) -> Int { return s.len; }
fn ilen(ref s: Slice[Int]) -> Int { return s.len; }

fn main() -> Int {
    let s: Str = "abc";
    let arr: Array[U8, 4] = Array.zeroed();
    let v: Slice[U8] = slice(arr, 0, 3);
    if slen(s) != 3 { return 1; }
    if fwd(s) != 3 { return 2; }
    if vlen(v) != 3 { return 3; }
    let ia: Array[Int, 2] = Array.zeroed();
    let iv: Slice[Int] = slice(ia, 0, 2);
    if ilen(iv) != 2 { return 4; }
    return 7;
}
