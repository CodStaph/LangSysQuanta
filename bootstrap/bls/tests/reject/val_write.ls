// B5-10: `let val` binds a frozen local; assignment is rejected.
fn main() -> Int {
    let val k = 5;
    k = 6;
    return k;
}
