// DDC probe s1: stage1_names.ls MINUS the struct (baseline: multi-char names,
// fn call, enum, array, slice, match). Expect exit 177.
enum Color { Red, Green, Blue }

fn add_values(first: Int, second: Int) -> Int {
    return first + second;
}

fn main() -> Int {
    let first_value = 3;
    let second_value = 4;
    let sum_value = add_values(first_value, second_value);
    let color = Color.Green;
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = sum_value;
    buf[1] = second_value;
    let view: Slice[U8] = slice(buf, 0, 2);
    match color {
        Color.Red => { return 1; },
        Color.Green => { return view[0] + view[1] + 170; },
        Color.Blue => { return 3; }
    }
    return 0;
}
