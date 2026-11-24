// R2.6-A: generic struct value passed by-value to a function (param side).
struct S[A, B] { f0: A, f1: B, f2: Int }

fn get_x(p: S[Int, Str]) -> Int {
    return p.f0;
}

fn main() -> Int {
    let p: S[Int, Str];
    p.f0 = 11;
    p.f2 = 22;
    if get_x(p) != 11 { return 1; }
    return 7;
}