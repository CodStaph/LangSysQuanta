// B7 reject: user trait names may not clash with the predefined Eq/Ord/Num/
// Add/Copy set.
trait Eq[A] {
    fn eq(ref a: A, ref b: A) -> Int;
}
fn main() -> Int { return 0; }
