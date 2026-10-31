// R2.2: generic struct S[A, B] declaration + typed-let instantiation.
struct S[A, B] { f0: A, f1: B, f2: Int }

fn main() -> Int {
    let p: S[Int, Str];
    let q: S[Str, Int];
    return 7;
}