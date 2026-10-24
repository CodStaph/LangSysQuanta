// B4: only Ord/Eq/Num/Add bounds are implemented.
fn f[T: Funny](a: T) -> T { return a; }
fn main() -> Int { let x = f(1); return 0; }
