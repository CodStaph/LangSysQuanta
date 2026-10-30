// B5-8: a ref local points at a local slot, so returning it is rejected.
fn bad() -> ref[Int] {
    let a = 5;
    let r: ref[Int] = a;
    return r;
}

fn main() -> Int {
    return 7;
}
