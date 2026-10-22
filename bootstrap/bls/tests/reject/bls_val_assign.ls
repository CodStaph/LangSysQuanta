// B2-2: assigning to a val parameter is rejected.
fn f(val x: Int) -> Int {
    x = 2;
    return x;
}
fn main() -> Int { return f(1); }
