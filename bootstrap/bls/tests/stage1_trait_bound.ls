// B7: user-declared traits as generic bounds ([A: Show]); the bound is
// satisfied only when an impl row exists for the actual type.
trait Show[A] {
    fn show(ref a: A) -> Int;
}
impl Show for Int {
    fn show(ref a: Int) -> Int { return 7; }
}
fn report[A: Show](v: A) -> A { return v; }
fn mk[A: Copy](v: A) -> A { return v; }
fn main() -> Int {
    let x = 3;
    let s: Str = "s";
    if report(x) != 3 { return 1; }
    if mk(x) != 3 { return 3; }
    if mk(s) != s { return 4; }
    return 7;
}
