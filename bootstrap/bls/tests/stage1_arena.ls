// B3-1: runtime arena metadata and bump allocation.
fn main() -> Int {
    let b = arena_budget();
    let u0 = arena_used();
    let p = arena_alloc(16);
    let u1 = arena_used();
    if p < 0 { return 1; }
    if u1 != u0 + 16 { return 2; }
    let q = arena_alloc(b);
    if q >= 0 { return 3; }
    arena_reset();
    if arena_used() != 0 { return 4; }
    return 7;
}
