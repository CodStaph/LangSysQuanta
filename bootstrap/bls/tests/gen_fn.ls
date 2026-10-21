// Stage 2: scalar generic function via boxed T.
fn id[T](x: T) -> T { return x; }
fn main() -> Int {
    let x = id(id(5));
    return x;
}
