// Stage 2: type-dispatched arithmetic/comparison on T (Int).
fn add[T](a: T, b: T) -> T { return a + b; }
fn lt[T](a: T, b: T) -> Int {
    if a < b { return 1; }
    return 0;
}
fn main() -> Int {
    let x = add(1, 2);
    let y = add(x, 4);
    let c = lt(3, 5);
    if c == 1 { return y; }
    return 9;
}
