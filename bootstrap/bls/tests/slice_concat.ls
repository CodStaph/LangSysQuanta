// Stage 2: explicit concat_into/append_into for Slice[U8].
fn main() -> Int {
    let a: Array[U8, 4] = Array.zeroed();
    let b: Array[U8, 4] = Array.zeroed();
    let out: Array[U8, 8] = Array.zeroed();
    a[0] = 1; a[1] = 2;
    b[0] = 3; b[1] = 4;
    let x: Slice[U8] = slice(a, 0, 2);
    let y: Slice[U8] = slice(b, 0, 2);
    let o: Slice[U8] = slice(out, 0, 8);
    let z: Slice[U8] = concat_into(x, y, o);
    let w: Slice[U8] = append_into(z, 5, o);
    return w[0] + w[1] + w[2] + w[3] + w[4];
}
