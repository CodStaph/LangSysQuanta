// Stage 2: infer Option[Int] from a constructor payload.
fn main() -> Int {
    let o = Option.Some(1);
    match o {
        Option.Some(v) => { return v; },
        Option.None => { return 9; }
    }
    return 0;
}
