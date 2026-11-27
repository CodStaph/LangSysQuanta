// R2.6-F: plain B7 struct by-value parameters and by-value returns.
struct Point { x: Int, y: Int }

fn get_x(p: Point) -> Int { return p.x; }

fn sum2(p: Point, q: Point) -> Int { return p.x + q.y; }

fn bump(p: Point) -> Int {
    p.x = 99;
    return p.x;
}

fn mk() -> Point {
    let q: Point;
    q.x = 9;
    q.y = 20;
    return q;
}

fn fwd(p: Point) -> Int { return get_x(p); }

fn main() -> Int {
    let p: Point;
    p.x = 11;
    p.y = 22;
    if get_x(p) != 11 { return 1; }
    let q: Point;
    q.x = 3;
    q.y = 5;
    if sum2(p, q) != 16 { return 2; }
    if bump(p) != 99 { return 3; }
    if p.x != 11 { return 4; }
    let r = mk();
    if r.x != 9 { return 5; }
    if r.y != 20 { return 6; }
    if fwd(p) != 11 { return 8; }
    return 7;
}
