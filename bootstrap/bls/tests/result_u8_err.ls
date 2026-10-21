// Stage 2: Result[U8, Int] monomorphic Err payload.
fn fail() -> Result[U8, Int] {
    return Result.Err(5);
}

fn main() -> Int {
    let r: Result[U8, Int] = fail();
    match r {
        Result.Ok(v) => { return v; },
        Result.Err(e) => { return e; }
    }
    return 0;
}
