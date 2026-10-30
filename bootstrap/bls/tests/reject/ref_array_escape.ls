// B5-9: a local ref must not be stored into a longer-lived array element.
fn idref(ref x: Int) -> ref[Int] { return x; }

fn main() -> Int {
    let ai: Array[ref[Int], 2] = Array.zeroed();
    if 1 == 1 {
        let a = 5;
        ai[0] = idref(a);
    }
    return 7;
}
