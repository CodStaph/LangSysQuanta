// B5-8: a short-lived local ref must not be stored into a longer-lived field.
struct Holder { r: ref[Int] }

fn main() -> Int {
    let h: Holder;
    if 1 == 1 {
        let a = 5;
        h.r = a;
    }
    return 7;
}
