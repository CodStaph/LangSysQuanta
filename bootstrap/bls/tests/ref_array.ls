// B5-9: ref values as array elements (Array[ref[T], N]).
struct Holder { r: ref[Int], n: Int }

fn idref(ref x: Int) -> ref[Int] { return x; }
fn idstr(ref s: Str) -> ref[Str] { return s; }
fn idbuf(ref b: Buffer[Int]) -> ref[Buffer[Int]] { return b; }

fn main() -> Int {
    let a = 5;
    let b = 7;
    let ai: Array[ref[Int], 3] = Array.zeroed();
    ai[0] = idref(a);
    ai[1] = idref(b);
    let p: ref[Int] = ai[0];
    if p != 5 { return 1; }
    p = 11;
    if a != 11 { return 2; }
    let q: ref[Int] = ai[1];
    q = 13;
    if b != 13 { return 3; }
    // ref local stored through a ref variable read
    let rl: ref[Int] = idref(a);
    ai[2] = rl;
    let s: ref[Int] = ai[2];
    s = 17;
    if a != 17 { return 4; }
    // Str / Buffer ref elements
    let sv: Str = "abc";
    let as: Array[ref[Str], 2] = Array.zeroed();
    as[0] = idstr(sv);
    let qs: ref[Str] = as[0];
    if qs.len != 3 { return 6; }
    qs = "xy";
    if sv.len != 2 { return 7; }
    let bv: Buffer[Int] = Buffer.new[Int](2, heap);
    let ab: Array[ref[Buffer[Int]], 1] = Array.zeroed();
    ab[0] = idbuf(bv);
    let qb: ref[Buffer[Int]] = ab[0];
    qb.push(3);
    if bv.len != 1 { return 8; }
    // struct field ref still works alongside array refs
    let h: Holder;
    h.r = idref(a);
    let hr: ref[Int] = h.r;
    hr = 19;
    if a != 19 { return 9; }
    return 7;
}
