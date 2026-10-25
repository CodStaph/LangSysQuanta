// B5-7: ref field values must be bound to a ref local first.
struct R { x: ref[Int] }
fn main() -> Int { let h: R; return h.x + 1; }
