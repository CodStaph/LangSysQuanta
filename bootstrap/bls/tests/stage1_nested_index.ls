// M1d-1b-0: nested index expressions as function arguments.
fn add(a: Int, b: Int) -> Int {
    return a + b;
}

fn main() -> Int {
    let a: Array[Int, 4] = Array.zeroed();
    let idx: Array[Int, 2] = Array.zeroed();
    a[0] = 70;
    a[1] = 77;
    idx[0] = 1;
    return add(a[idx[0]], 100);
}
