// Stage 2: Result[Int, Int] + ? propagation (success path).

fn inc(x: Int) -> Result[Int, Int] {
    if x < 0 { return Result.Err(7); }
    return Result.Ok(x + 1);
}

fn twice(x: Int) -> Result[Int, Int] {
    let a = inc(x)?;
    let b = inc(a)?;
    return Result.Ok(b + 10);
}

fn main() -> Int {
    let r: Result[Int, Int] = twice(1);
    match r {
        Result.Ok(v) => { return v; },
        Result.Err(e) => { return 200 + e; }
    }
    return 0;
}
