// Stage 2 / R4.3: concat_into/append_into return Result[Slice[U8], AllocError].
fn append5(s: Slice[U8], o: Slice[U8]) -> Int {
    let w: Result[Slice[U8], AllocError] = append_into(s, 5, o);
    match w {
        Result.Ok(t) => { return t[0] + t[1] + t[2] + t[3] + t[4]; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn main() -> Int {
    let a: Array[U8, 4] = Array.zeroed();
    let b: Array[U8, 4] = Array.zeroed();
    let out: Array[U8, 8] = Array.zeroed();
    a[0] = 1; a[1] = 2;
    b[0] = 3; b[1] = 4;
    let x: Slice[U8] = slice(a, 0, 2);
    let y: Slice[U8] = slice(b, 0, 2);
    let o: Slice[U8] = slice(out, 0, 8);
    let z: Result[Slice[U8], AllocError] = concat_into(x, y, o);
    match z {
        Result.Ok(s) => { return append5(s, o); },
        Result.Err(e) => { return 0 - 1; }
    }
}
