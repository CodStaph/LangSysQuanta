// B5-9: Slice of ref elements is not a supported type yet.
fn main() -> Int {
    let ai: Array[ref[Int], 2] = Array.zeroed();
    let s: Slice[Int] = slice(ai, 0, 2);
    return 7;
}
