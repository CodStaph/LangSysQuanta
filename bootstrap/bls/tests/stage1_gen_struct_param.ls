// R2.6-A: generic struct value passed by-value to a function and returned.
struct S[A, B] { f0: A, f1: B, f2: Int }

fn get_x(p: S[Int, Str]) -> Int {
    return p.f0;
}

fn make() -> S[Int, Str] {
    let q: S[Int, Str];
    q.f0 = 9;
    q.f2 = 20;
    return q;
}

fn main() -> Int {
    let p: S[Int, Str];
    p.f0 = 11;
    p.f2 = 22;
    if get_x(p) != 11 { return 1; }
    let r = make();
    if r.f0 != 9 { return 2; }
    return 7;
}