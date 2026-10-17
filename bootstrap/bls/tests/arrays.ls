// B-LS M1b-1: fixed-size arrays.
fn main() -> Int {
    let a: Array[Int, 4] = Array.zeroed();
    let b: Array[U8, 4] = Array.zeroed();
    a[0] = 3;
    a[1] = 4;
    b[0] = 65;
    b[1] = 66;
    b[2] = 10;
    write("arr ok\n");
    return a[0] + a[1];
}
