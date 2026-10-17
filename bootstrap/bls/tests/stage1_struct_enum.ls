// M1d-0c: struct + tag-only enum/match in stage1.
struct Point { x: Int, y: Int }
enum Color { Red, Green, Blue }

fn main() -> Int {
    let p: Point;
    p.x = 3;
    p.y = 4;
    let c = Color.Green;
    match c {
        Color.Red => { return 1; },
        Color.Green => { return p.x + p.y + 170; },
        Color.Blue => { return 3; }
    }
    return 0;
}
