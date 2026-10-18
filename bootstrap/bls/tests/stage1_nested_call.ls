// stage1: nested call arguments.
fn add(a: Int, b: Int) -> Int { return a + b; }
fn inc(a: Int) -> Int { return a + 1; }
fn main() -> Int {
    return add(inc(1), add(2, 3));
}
