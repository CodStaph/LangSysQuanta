// B5-1: two ref parameters may not alias the same variable.
fn two(ref a: Int, ref b: Int) -> Int { return a + b; }
fn main() -> Int { let x = 1; return two(x, x); }
