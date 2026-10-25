// B5-6: ref return type must match the returned ref.
fn bad(ref x: Int) -> ref[Str] { return x; }
fn main() -> Int { let a = 1; return 0; }
