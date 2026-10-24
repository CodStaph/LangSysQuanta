// B5-1: ref arguments must be variables.
fn use_ref(ref x: Int) -> Int { return x; }
fn main() -> Int { return use_ref(1); }
