// DDC probe s3: struct decl + typed var + two field assignments (exact shape
// of stage1_names.ls lines 13-15). Expect 7.
struct Point { x_coord: Int, y_coord: Int }

fn main() -> Int {
    let first_value = 3;
    let second_value = 4;
    let point: Point;
    point.x_coord = first_value;
    point.y_coord = second_value;
    return point.x_coord + point.y_coord;
}
