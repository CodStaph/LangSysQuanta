// R2.6-B: unified generic struct constructor (`S.new(...)` with inferred
// type args) and single-type-arg enum variant construction under the frozen
// EBNF (explicit multi-tyarg `Pair[Int, Int].new` stays outside the grammar).
struct Pair[A, B] { f0: A, f1: B, hit: Int }
enum Box[T] { Box(T), Empty }

fn get_hit(p: Pair[Int, Int]) -> Int { return p.hit; }

fn make_pair(a: Int, b: Int) -> Pair[Int, Int] {
    let t: Pair[Int, Int];
    t.f0 = a; t.f1 = b; t.hit = 99;
    return t;
}

fn box_val() -> Int {
    let b = Box[Int].Box(21);
    match b {
        Box.Box(v) => { return v; },
        Box.Empty => { return 0; }
    }
    return 0;
}

fn main() -> Int {
    // inferred type args, let receiver
    let p = Pair.new(3, 4, 7);
    if p.f0 != 3 { return 1; }
    if p.f1 != 4 { return 2; }
    if p.hit != 7 { return 3; }
    // second instance of the same template (dedup row)
    let q = Pair.new(5, 6, 8);
    if q.f0 != 5 { return 4; }
    if q.f1 != 6 { return 5; }
    if q.hit != 8 { return 6; }
    // constructor in argument position (by-value ABI)
    if get_hit(Pair.new(9, 10, 11)) != 11 { return 7; }
    // constructor received from a function (R2.6-A path)
    let r = make_pair(1, 2);
    if r.hit != 99 { return 8; }
    if r.f0 != 1 { return 9; }
    // enum construction (inference form, unchanged baseline)
    if box_val() != 21 { return 10; }
    return 7;
}
