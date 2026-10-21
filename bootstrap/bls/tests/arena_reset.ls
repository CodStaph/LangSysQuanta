// Stage 2: explicit arena reset for Str temporaries.
fn main() -> Int {
    let s: Str = "a";
    let t: Str = "b";
    let u: Str = s + t;
    arena_reset();
    let v: Str = s + t;
    return v.len;
}
