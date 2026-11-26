// R2.6-B reject: constructor concrete-field type mismatch (hit: Int gets Str).
struct Pair[A, B] { f0: A, f1: B, hit: Int }
fn main() -> Int {
    let s: Str = "xy";
    let p = Pair.new(1, 2, s);
    return p.hit;
}
