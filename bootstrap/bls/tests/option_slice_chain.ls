// Stage 2: Option[Slice[U8]] + ? success path.
fn make(x: Int) -> Option[Slice[U8]] {
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = 4;
    buf[1] = 6;
    let v: Slice[U8] = slice(buf, 0, 2);
    if x == 0 { return Option.None; }
    return Option.Some(v);
}

fn use(x: Int) -> Option[Slice[U8]] {
    let v: Slice[U8] = make(x)?;
    return Option.Some(v);
}

fn main() -> Int {
    let o: Option[Slice[U8]] = use(1);
    match o {
        Option.Some(v) => { return v[0] + v[1]; },
        Option.None => { return 9; }
    }
    return 0;
}
