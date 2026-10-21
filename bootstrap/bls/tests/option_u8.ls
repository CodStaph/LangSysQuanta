// Stage 2: Option[U8] monomorphic payload.
fn get() -> Option[U8] {
    return Option.Some(200);
}

fn main() -> Int {
    let o: Option[U8] = get();
    match o {
        Option.Some(v) => { return v; },
        Option.None => { return 9; }
    }
    return 0;
}
