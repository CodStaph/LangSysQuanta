// Stage 2 / R4.3: concat_into/append_into return Result[Slice[Int], AllocError].
fn append50(s: Slice[Int], o: Slice[Int]) -> Int {
    let w: Result[Slice[Int], AllocError] = append_into(s, 50, o);
    match w {
        Result.Ok(t) => { return t[0] + t[1] + t[2] + t[3]; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn main() -> Int {
    let a: Array[Int, 4] = Array.zeroed();
    let b: Array[Int, 4] = Array.zeroed();
    let out: Array[Int, 8] = Array.zeroed();
    a[0] = 10; a[1] = 20;
    b[0] = 30;
    let x: Slice[Int] = slice(a, 0, 2);
    let y: Slice[Int] = slice(b, 0, 1);
    let o: Slice[Int] = slice(out, 0, 8);
    let z: Result[Slice[Int], AllocError] = concat_into(x, y, o);
    match z {
        Result.Ok(s) => { return append50(s, o); },
        Result.Err(e) => { return 0 - 1; }
    }
}
