// B-LS R4.3: direct Str `+` must use the fallible builtins.
fn main() -> Int {
    let a: Str = "x";
    let b: Str = "y";
    let c: Str = a + b;
    return c.len;
}
