// R2.6-C reject: trait-method argument must be the same struct type.
struct Pt { x: Int }
impl Eq for Pt { fn eq(ref a: Pt, ref b: Pt) -> Int { return 1; } }
fn main() -> Int {
    let p: Pt;
    p.x = 1;
    if p.eq(1) != 1 { return 1; }
    return 7;
}