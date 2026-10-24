// B5-1: ref parameters in generic functions are not implemented.
fn use_ref[T](ref x: Int, y: T) -> T { return y; }
fn main() -> Int { let x = 1; let y = 2; return use_ref(x, y); }
