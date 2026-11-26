// R2.6-C reject: explicit .eq without an Eq impl for the type.
struct NoEq { x: Int }
fn main() -> Int {
    let p: NoEq;
    p.x = 1;
    let q: NoEq;
    q.x = 1;
    if p.eq(q) != 1 { return 1; }
    return 7;
}