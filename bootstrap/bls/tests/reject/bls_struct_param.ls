// R2.6-F reject: struct parameters (ref or by value) must sit in the first
// four argument slots.
struct Point { x: Int, y: Int }
fn take(p: Point, q: Point, r: Point, s: Point, t: Point) -> Int { return p.x; }
fn main() -> Int { return 0; }
