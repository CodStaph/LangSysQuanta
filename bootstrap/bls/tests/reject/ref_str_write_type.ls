// B5-4: ref Str assignment requires a Str value.
fn set(ref s: Str) -> Int { s = 1; return 0; }
fn main() -> Int { let s: Str = "x"; return set(s); }
