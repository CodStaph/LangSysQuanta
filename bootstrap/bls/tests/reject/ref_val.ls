// B5-1: a `val` binding cannot be borrowed mutably.
fn use_ref(ref x: Int) -> Int { return x; }
fn caller(val y: Int) -> Int { return use_ref(y); }
fn main() -> Int { return caller(1); }
