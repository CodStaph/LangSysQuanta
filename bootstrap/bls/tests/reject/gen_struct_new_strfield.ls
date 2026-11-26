// R2.6-B reject: struct slots are 8 bytes, so a Str field cannot be stored
// by the constructor (same boundary as R2.2 field writes).
struct Pair[A, B] { f0: A, f1: B, hit: Int }
fn main() -> Int {
    let s: Str = "xy";
    let p = Pair.new(s, 2, 3);
    return p.hit;
}
