// R2.6-C: explicit trait-method calls `p.eq(q)` / `p.lt(q)` and the `+`
// operator provided by `impl Add`.
struct Pt { x: Int, y: Int }
impl Eq for Pt {
    fn eq(ref a: Pt, ref b: Pt) -> Int {
        if a.x != b.x { return 0; }
        if a.y != b.y { return 0; }
        return 1;
    }
}
impl Ord for Pt {
    fn lt(ref a: Pt, ref b: Pt) -> Int {
        if a.x < b.x { return 1; }
        if a.x > b.x { return 0; }
        return a.y < b.y;
    }
}
impl Add for Pt {
    fn add(ref a: Pt, ref b: Pt) -> Int {
        return a.x + b.x + a.y + b.y;
    }
}
fn main() -> Int {
    let p: Pt;
    p.x = 1; p.y = 2;
    let q: Pt;
    q.x = 1; q.y = 2;
    let r: Pt;
    r.x = 3; r.y = 4;
    // explicit trait-method calls
    if p.eq(q) != 1 { return 1; }
    if p.eq(r) != 0 { return 2; }
    if p.lt(r) != 1 { return 3; }
    if r.lt(p) != 0 { return 4; }
    // `+` through impl Add (1+3+2+4 = 10)
    if p + r != 10 { return 5; }
    // B7 derived comparisons keep working next to the explicit forms
    if p == q { return 6; }
    if p >= r { return 7; }
    return 7;
}