// Stage 2: Result[Int, Int] + ? propagation (error path).

fn fail(x: Int) -> Result[Int, Int] {
    return Result.Err(3 + x);
}

fn chain(x: Int) -> Result[Int, Int] {
    let y = fail(x)?;
    return Result.Ok(y);
}

fn main() -> Int {
    let r: Result[Int, Int] = chain(4);
    match r {
        Result.Ok(v) => { return v; },
        Result.Err(e) => { return e; }
    }
    return 0;
}
