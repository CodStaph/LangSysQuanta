// B5-7: ref field requires a matching ref value.
struct R { s: ref[Str] }
fn main() -> Int { let h: R; let x = 1; h.s = x; return 0; }
