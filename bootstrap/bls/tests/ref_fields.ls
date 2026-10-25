// B5-7: ref struct fields and ref array elements.
struct Holder { r: ref[Int], n: Int }
struct HStr { s: ref[Str] }
struct HVec { v: ref[Slice[U8]] }
struct HBuf { b: ref[Buffer[Int]] }

fn idref(ref x: Int) -> ref[Int] { return x; }
fn sref(ref s: Str) -> ref[Str] { return s; }
fn vref(ref s: Slice[U8]) -> ref[Slice[U8]] { return s; }
fn bref(ref b: Buffer[Int]) -> ref[Buffer[Int]] { return b; }

fn main() -> Int {
    let h: Holder;
    let a = 5;
    h.r = idref(a);
    let q: ref[Int] = h.r;
    if q != 5 { return 1; }
    q = 9;
    if a != 9 { return 2; }
    h.r = a;
    let w: ref[Int] = h.r;
    w = 11;
    if a != 11 { return 3; }
    h.n = 3;
    if h.n != 3 { return 4; }

    let s: Str = "abc";
    let hs: HStr;
    hs.s = sref(s);
    let qs: ref[Str] = hs.s;
    if qs.len != 3 { return 5; }
    qs = "xy";
    if s.len != 2 { return 6; }

    let arr: Array[U8, 3] = Array.zeroed();
    let v: Slice[U8] = slice(arr, 0, 3);
    let hv: HVec;
    hv.v = vref(v);
    let qv: ref[Slice[U8]] = hv.v;
    qv[0] = 7;
    if arr[0] != 7 { return 7; }

    let b: Buffer[Int] = Buffer.new[Int](2, heap);
    let hb: HBuf;
    hb.b = bref(b);
    let qb: ref[Buffer[Int]] = hb.b;
    qb.push(3);
    if b.len != 1 { return 8; }

    let ai: Array[Int, 3] = Array.zeroed();
    ai[1] = 5;
    let re: ref[Int] = ai[1];
    if re != 5 { return 9; }
    re = 13;
    if ai[1] != 13 { return 10; }
    return 7;
}
