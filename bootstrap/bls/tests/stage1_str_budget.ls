// R4.3: Str concat reports arena exhaustion as Result instead of trapping.
fn concat_ok(a: Str, b: Str) -> Int {
    let r: Result[Str, AllocError] = str_try_concat(a, b);
    match r {
        Result.Ok(s) => { return s.len; },
        Result.Err(e) => { return 0 - 1; }
    }
}

fn concat_err(a: Str, b: Str) -> Int {
    let r: Result[Str, AllocError] = str_try_concat(a, b);
    match r {
        Result.Ok(s) => { return 1; },
        Result.Err(e) => { return e + 1; }
    }
}

fn add[T](a: T, b: T) -> T { return a + b; }

fn main() -> Int {
    let a: Str = "ab";
    let b: Str = "cd";

    // Fill the arena exactly: concat fails with Err and does not advance it.
    let bud = arena_budget();
    arena_alloc(bud);
    let used = arena_used();
    if concat_err(a, b) != 0 { return 2; }
    if arena_used() != used { return 3; }

    // Generic `+` no longer traps: it degrades to an empty Str (tag 9 box).
    let g: Str = add(a, b);
    if g.len != 0 { return 5; }

    arena_reset();
    if concat_ok(a, b) != 4 { return 1; }
    let h: Str = add(a, b);
    if h.len != 4 { return 6; }
    return 7;
}
