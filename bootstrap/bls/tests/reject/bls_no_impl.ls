struct Point { x: Int, y: Int }
fn main() -> Int {
    let p: Point;
    p.x = 3; p.y = 4;
    let q: Point;
    q.x = 3; q.y = 5;
    if p == q { return 1; }
    return 0;
}
