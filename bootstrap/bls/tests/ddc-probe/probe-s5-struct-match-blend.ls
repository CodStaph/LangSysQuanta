// DDC probe s5: struct field read feeding a match arm (the full blend of
// stage1_names.ls: struct fields into buf, slice read in a match arm).
// Expect 177.
struct Point { x_coord: Int, y_coord: Int }
enum Color { Red, Green, Blue }

fn main() -> Int {
    let point: Point;
    point.x_coord = 3;
    point.y_coord = 4;
    let color = Color.Green;
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = point.x_coord;
    buf[1] = point.y_coord;
    let view: Slice[U8] = slice(buf, 0, 2);
    match color {
        Color.Red => { return 1; },
        Color.Green => { return view[0] + view[1] + 170; },
        Color.Blue => { return 3; }
    }
    return 0;
}
