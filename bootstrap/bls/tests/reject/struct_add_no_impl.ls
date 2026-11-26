// R2.6-E reject: `+` on struct values without an Add impl.
struct Pt { x: Int }
fn main() -> Int {
    let p: Pt;
    p.x = 1;
    let q: Pt;
    q.x = 2;
    let s = p + q;
    return 7;
}