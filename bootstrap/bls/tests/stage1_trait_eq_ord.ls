// B7: user traits - Eq/Ord impls make struct values comparable.
struct Point { x: Int, y: Int }
impl Eq for Point {
    fn eq(ref a: Point, ref b: Point) -> Int {
        if a.x == b.x { if a.y == b.y { return 1; } }
        return 0;
    }
}
impl Ord for Point {
    fn lt(ref a: Point, ref b: Point) -> Int {
        if a.x < b.x { return 1; }
        if a.x == b.x { if a.y < b.y { return 1; } }
        return 0;
    }
}
fn main() -> Int {
    let p: Point;
    p.x = 3; p.y = 4;
    let q: Point;
    q.x = 3; q.y = 5;
    if p == q { return 1; }
    if p != q { } else { return 2; }
    if p < q { } else { return 3; }
    if p <= q { } else { return 4; }
    if q > p { } else { return 5; }
    if p >= q { return 6; }
    return 9;
}
