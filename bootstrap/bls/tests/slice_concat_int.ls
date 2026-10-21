// Stage 2: explicit concat_into/append_into for Slice[Int].
fn main() -> Int {
    let a: Array[Int, 4] = Array.zeroed();
    let b: Array[Int, 4] = Array.zeroed();
    let out: Array[Int, 8] = Array.zeroed();
    a[0] = 10; a[1] = 20;
    b[0] = 30;
    let x: Slice[Int] = slice(a, 0, 2);
    let y: Slice[Int] = slice(b, 0, 1);
    let o: Slice[Int] = slice(out, 0, 8);
    let z: Slice[Int] = concat_into(x, y, o);
    let w: Slice[Int] = append_into(z, 50, o);
    return w[0] + w[1] + w[2] + w[3];
}
