// R2.2: generic struct S[A, B]: declaration, typed-let instantiation,
// field write and field read through the shared template/instance tables.
// Scope: Int-valued fields (generic parameter position and concrete Int);
// Str fields inside generic structs stay out of this milestone (same
// boundary as non-generic structs: no Str-literal field stores).
struct S[A, B] { f0: A, f2: Int }

fn main() -> Int {
    let p: S[Int, Str];
    p.f0 = 11;
    p.f2 = 22;
    if p.f0 != 11 { return 1; }
    if p.f2 != 22 { return 2; }
    let q: S[Str, Int];
    q.f2 = 33;
    if q.f2 != 33 { return 3; }
    let a = p.f0;
    if a != 11 { return 4; }
    return 7;
}