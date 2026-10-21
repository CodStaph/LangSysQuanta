// Stage 2: Option[Str] + ? None propagation.
fn find(x: Int) -> Option[Str] {
    if x == 0 { return Option.None; }
    let s: Str = "yes";
    return Option.Some(s);
}

fn use(x: Int) -> Option[Str] {
    let s: Str = find(x)?;
    return Option.Some(s);
}

fn main() -> Int {
    let o: Option[Str] = use(0);
    match o {
        Option.Some(v) => { return v.len; },
        Option.None => { return 9; }
    }
    return 0;
}
