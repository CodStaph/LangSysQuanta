// B7 reject: struct parameters must be ref (method receivers copy in).
struct Point { x: Int, y: Int }
fn take(p: Point) -> Int { return p.x; }
fn main() -> Int { return 0; }
