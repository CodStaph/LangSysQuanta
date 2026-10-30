// B5-8: accepted lifetime patterns. A `ref` parameter is a reborrow and may be
// returned/stored; a local ref may only flow into same-scope or shorter-lived
// places.
struct Holder { r: ref[Int], n: Int }

fn idref(ref x: Int) -> ref[Int] { return x; }
// Reborrow of a ref parameter through a ref local, then returned.
fn same(ref x: Int) -> ref[Int] { let r: ref[Int] = x; return r; }
// A local struct inside the callee keeps the reborrowed parameter: allowed.
fn keep(ref v: Int) -> Int {
    let h: Holder;
    h.n = 2;
    h.r = v;
    let q: ref[Int] = h.r;
    q = 55;
    return 0;
}

fn main() -> Int {
    let a = 5;
    let r: ref[Int] = same(a);
    if r != 5 { return 1; }
    r = 6;
    if a != 6 { return 2; }
    if keep(a) != 0 { return 3; }
    if a != 55 { return 4; }

    // Same-scope local into a same-scope struct field.
    let h: Holder;
    let b = 7;
    h.r = b;
    let w: ref[Int] = h.r;
    w = 8;
    if b != 8 { return 5; }
    // Call-returned ref stored into a same-scope field.
    h.r = idref(b);
    // Array element ref within the declaring block.
    let ai: Array[Int, 2] = Array.zeroed();
    let re: ref[Int] = ai[0];
    re = 3;
    if ai[0] != 3 { return 6; }
    // Inner block: short-lived refs stay inside that block.
    if 1 == 1 {
        let c = 9;
        let t: ref[Int] = c;
        t = 10;
        if c != 10 { return 7; }
        let inner: Holder;
        inner.r = idref(c);
        let iq: ref[Int] = inner.r;
        iq = 11;
        if c != 11 { return 8; }
    }
    return 7;
}
