// B5-8: the lifetime of a call-returned ref follows its ref arguments, so a
// call cannot launder a local borrow into an outer field.
struct Holder { r: ref[Int] }
fn idref(ref x: Int) -> ref[Int] { return x; }

fn main() -> Int {
    let h: Holder;
    if 1 == 1 {
        let a = 5;
        h.r = idref(a);
    }
    return 7;
}
