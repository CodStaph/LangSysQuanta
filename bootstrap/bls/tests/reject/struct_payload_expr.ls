// B5-12: struct values may only be used through field access.
struct Point { x: Int, y: Int }
fn main() -> Int {
    let p: Point;
    p.x = 1;
    p.y = 2;
    return p + 1;
}
