// B3-3: Buffer.try_new -> Result[Buffer[Int], Int].
// Success: the Ok payload is a working Buffer[Int] handle (len/cap/push).
// Failure: the Err payload is the runtime code -1 and the arena is untouched.
fn ok_path() -> Int {
    let r: Result[Buffer[Int], Int] = Buffer.try_new[Int](4, heap);
    match r {
        Result.Ok(b) => { return b.len + b.cap + b.push(11); },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn err_path() -> Int {
    let big = arena_budget() + 1;
    let q: Result[Buffer[Int], Int] = Buffer.try_new[Int](big, heap);
    match q {
        Result.Ok(b) => { return 21; },
        Result.Err(e) => { return e + 1; }
    }
}

fn main() -> Int {
    if ok_path() != 5 { return 10; }
    let used = arena_used();
    if err_path() != 0 { return 11; }
    if arena_used() != used { return 12; }
    return 7;
}
