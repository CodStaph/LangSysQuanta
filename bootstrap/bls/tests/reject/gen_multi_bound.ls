// B4: Eq does not permit ordering operations.
fn bad[T: Eq](a: T, b: T) -> T {
    if a < b { return a; }
    return b;
}
fn main() -> Int { let x = bad(1, 2); return 0; }
