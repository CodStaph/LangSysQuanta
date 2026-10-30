// B5-9: ref payloads for Option[T] / Result[T, E] (borrow stored in a value).
fn take(ref x: Int) -> Result[ref[Int], Int] {
    let r: Result[ref[Int], Int] = Result.Ok(x);
    let q: ref[Int] = r?;
    q = 21;
    return Result.Ok(x);
}

fn pick(ref x: Int) -> Option[ref[Int]] {
    let o: Option[ref[Int]] = Option.Some(x);
    let q: ref[Int] = o?;
    q = 33;
    return Option.Some(x);
}

fn payload_none() -> Int {
    let a = 5;
    let o: Option[ref[Int]] = Option.None;
    match o {
        Option.Some(v) => { return v; },
        Option.None => { return 0; }
    }
    return 0;
}

fn run_result() -> Int {
    let a = 5;
    let ra: Result[ref[Int], Int] = take(a);
    match ra {
        Result.Ok(v) => { return v; },
        Result.Err(e) => { return e; }
    }
    return 0;
}

fn run_option() -> Int {
    let b = 7;
    let ob: Option[ref[Int]] = pick(b);
    match ob {
        Option.Some(w) => { return w; },
        Option.None => { return 0; }
    }
    return 0;
}

fn main() -> Int {
    if run_result() != 21 { return 1; }
    if run_option() != 33 { return 2; }
    if payload_none() != 0 { return 3; }
    return 7;
}
