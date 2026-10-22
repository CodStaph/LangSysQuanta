// B2-2: a `let` may shadow a `val` parameter; assignment then targets the let.
fn f(val x: Int) -> Int {
    let x = 2;
    x = 3;
    return x;
}
fn main() -> Int { return f(1); }
