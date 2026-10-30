// B7 reject: op traits keep to user structs (Eq/Ord/Copy), custom traits also
// take Int/U8; Num/Add impls are out.
impl Eq for Int {
    fn eq(ref a: Int, ref b: Int) -> Int { return 1; }
}
fn main() -> Int { return 0; }
