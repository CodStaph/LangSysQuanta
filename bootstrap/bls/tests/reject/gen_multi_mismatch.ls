// B4: the same generic parameter must unify to one concrete type.
fn same[A, B](a: A, b: A) -> A { return a; }
fn main() -> Int {
    let s: Str = "s";
    let x = same(1, s);
    return 0;
}
