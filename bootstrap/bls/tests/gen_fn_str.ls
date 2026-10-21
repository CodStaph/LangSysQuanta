// Stage 2: generic function with boxed Str.
fn id[T](x: T) -> T { return x; }
fn main() -> Int {
    let s: Str = "ok";
    let y = id(s);
    return y.len;
}
