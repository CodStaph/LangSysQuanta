// B5-2: ref argument type must match the parameter.
fn slen(ref s: Str) -> Int { return s.len; }
fn main() -> Int { let x = 1; return slen(x); }
