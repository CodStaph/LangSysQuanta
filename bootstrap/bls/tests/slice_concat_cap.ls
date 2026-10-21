// Stage 2: concat_into must trap on insufficient destination capacity.
fn main() -> Int {
    let a: Array[U8, 4] = Array.zeroed();
    let b: Array[U8, 4] = Array.zeroed();
    let out: Array[U8, 2] = Array.zeroed();
    let x: Slice[U8] = slice(a, 0, 2);
    let y: Slice[U8] = slice(b, 0, 2);
    let o: Slice[U8] = slice(out, 0, 2);
    let z: Slice[U8] = concat_into(x, y, o);
    return 0;
}
