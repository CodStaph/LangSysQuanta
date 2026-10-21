// Stage 2: Result[Str, Int] + ? Err propagation.
fn parse(x: Int) -> Result[Str, Int] {
    if x == 0 { return Result.Err(7); }
    let s: Str = "ok";
    return Result.Ok(s);
}

fn use(x: Int) -> Result[Str, Int] {
    let s: Str = parse(x)?;
    return Result.Ok(s);
}

fn main() -> Int {
    let r: Result[Str, Int] = use(0);
    match r {
        Result.Ok(v) => { return v.len; },
        Result.Err(e) => { return 200 + e; }
    }
    return 0;
}
