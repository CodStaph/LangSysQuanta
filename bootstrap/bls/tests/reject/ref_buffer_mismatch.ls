// B5-3: ref Buffer requires a Buffer argument.
fn use_buf(ref b: Buffer[Int]) -> Int { return b.len; }
fn main() -> Int { let s: Str = "x"; return use_buf(s); }
