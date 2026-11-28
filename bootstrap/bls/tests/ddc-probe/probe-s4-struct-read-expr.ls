// DDC probe s4: struct field READ inside a plain expression. Expect 7.
struct Point { x_coord: Int }

fn main() -> Int {
    let point: Point;
    point.x_coord = 3;
    return point.x_coord + 4;
}
