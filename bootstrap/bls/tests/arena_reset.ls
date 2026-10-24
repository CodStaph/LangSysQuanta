// Stage 2 / R4.3: explicit arena reset for Str temporaries (fallible concat).
fn main() -> Int {
    let s: Str = "a";
    let t: Str = "b";
    let u: Result[Str, AllocError] = str_try_concat(s, t);
    arena_reset();
    let v: Result[Str, AllocError] = str_try_concat(s, t);
    match v {
        Result.Ok(w) => { return w.len; },
        Result.Err(e) => { return 0 - 1; }
    }
}
