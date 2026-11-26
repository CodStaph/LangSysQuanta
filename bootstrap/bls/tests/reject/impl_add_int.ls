// R2.6-C reject: Add is an operator trait and targets user structs only.
impl Add for Int { fn add(ref a: Int, ref b: Int) -> Int { return a + b; } }
fn main() -> Int {
    return 7;
}