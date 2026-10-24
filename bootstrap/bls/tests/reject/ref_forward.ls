// B5-1: ref-to-ref forwarding is not implemented (no pointer value in B-LS).
fn inner(ref x: Int) -> Int { return x; }
fn outer(ref y: Int) -> Int { return inner(y); }
fn main() -> Int { let a = 1; return outer(a); }
