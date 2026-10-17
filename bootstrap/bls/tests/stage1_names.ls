// M1d-0d: multi-character names in stage1.
struct Point { x_coord: Int, y_coord: Int }
enum Color { Red, Green, Blue }

fn add_values(first: Int, second: Int) -> Int {
    return first + second;
}

fn main() -> Int {
    let first_value = 3;
    let second_value = 4;
    let sum_value = add_values(first_value, second_value);
    let point: Point;
    point.x_coord = first_value;
    point.y_coord = second_value;
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
