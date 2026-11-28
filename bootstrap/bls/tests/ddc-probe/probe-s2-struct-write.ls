// DDC probe s2: struct decl + typed uninitialized struct var + ONE field
// assignment. Minimal struct-field-write shape of stage1_names.ls. Expect 3.
struct Point { x_coord: Int, y_coord: Int }

fn main() -> Int {
    let point: Point;
    point.x_coord = 3;
    return point.x_coord;
}
