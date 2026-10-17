// B-LS M1b-3b: structs with Int fields.
struct Point { x: Int, y: Int }

fn main() -> Int {
    let p: Point;
    p.x = 3;
    p.y = 4;
    write("struct ok\n");
    return p.x + p.y;
}
