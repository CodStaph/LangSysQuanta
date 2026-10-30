// B5-8: escape through a ref local (variable path of the field store).
struct Holder { r: ref[Int] }

fn main() -> Int {
    let h: Holder;
    if 1 == 1 {
        let a = 5;
        let p: ref[Int] = a;
        h.r = p;
    }
    return 7;
}
