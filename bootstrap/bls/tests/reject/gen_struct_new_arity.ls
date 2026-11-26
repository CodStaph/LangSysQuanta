// R2.6-B reject: constructor argument count mismatch.
struct Pair[A, B] { f0: A, f1: B, hit: Int }
fn main() -> Int {
    let p = Pair.new(1);
    return p.f0;
}
