// B5-6: ref local initializer must match the ref element type.
fn main() -> Int { let s: Str = "x"; let r: ref[Int] = s; return 0; }
