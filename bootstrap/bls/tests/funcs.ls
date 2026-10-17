// B-LS M1b-1: functions with Int params/return.
fn add(a: Int, b: Int) -> Int {
    return a + b;
}
fn mul(a: Int, b: Int) -> Int {
    return a * b;
}
fn main() -> Int {
    let x = add(3, mul(4, 1));
    write("funcs ok\n");
    return x;
}
