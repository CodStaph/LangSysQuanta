// Stage 2: Option[Int] + ? propagation (Some path).

fn pick(x: Int) -> Option[Int] {
    if x == 0 { return Option.None; }
    return Option.Some(x + 2);
}

fn opt(x: Int) -> Option[Int] {
    let y = pick(x)?;
    return Option.Some(y + 1);
}

fn main() -> Int {
    let a: Option[Int] = opt(3);
    match a {
        Option.Some(v) => { return v; },
        Option.None => { return 9; }
    }
    return 0;
}
