// Stage 2 / R4.3: concat_into returns Err (no trap) when the destination is
// too small, and writes nothing (out[0]/out[1] stay 0).
fn main() -> Int {
    let a: Array[U8, 4] = Array.zeroed();
    let b: Array[U8, 4] = Array.zeroed();
    let out: Array[U8, 2] = Array.zeroed();
    a[0] = 1; a[1] = 2;
    b[0] = 3; b[1] = 4;
    let x: Slice[U8] = slice(a, 0, 2);
    let y: Slice[U8] = slice(b, 0, 2);
    let o: Slice[U8] = slice(out, 0, 2);
    let z: Result[Slice[U8], AllocError] = concat_into(x, y, o);
    match z {
        Result.Ok(s) => { return 1; },
        Result.Err(e) => { return out[0] + out[1] + 7; }
    }
}
