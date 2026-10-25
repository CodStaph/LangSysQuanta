// B5-6: ref locals, ref returns and ref forwarding value types.
fn idref(ref x: Int) -> ref[Int] { return x; }
fn bump(ref x: Int) -> Int { let r: ref[Int] = x; r = r + 1; return r; }
fn sref(ref s: Str) -> ref[Str] { return s; }
fn vref(ref s: Slice[U8]) -> ref[Slice[U8]] { return s; }
fn bref(ref b: Buffer[Int]) -> ref[Buffer[Int]] { return b; }

fn main() -> Int {
    let a = 5;
    let r: ref[Int] = idref(a);
    if r != 5 { return 1; }
    r = 9;
    if a != 9 { return 2; }
    if bump(a) != 10 { return 3; }
    if a != 10 { return 4; }

    let s: Str = "abc";
    let q: ref[Str] = sref(s);
    if q.len != 3 { return 5; }
    q = "xy";
    if s.len != 2 { return 6; }
    let q2: ref[Str] = s;
    if q2.len != 2 { return 7; }

    let arr: Array[U8, 3] = Array.zeroed();
    let v: Slice[U8] = slice(arr, 0, 3);
    let rv: ref[Slice[U8]] = vref(v);
    rv[0] = 7;
    if arr[0] != 7 { return 8; }
    let rv2: ref[Slice[U8]] = v;
    rv2[1] = 8;
    if arr[1] != 8 { return 9; }

    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    let rb: ref[Buffer[Int]] = bref(b);
    rb.push(3);
    if b.len != 1 { return 10; }
    return 7;
}
