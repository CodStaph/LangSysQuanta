// Stage 2: generic Str comparison must use Unicode scalar values, not bytes.
fn lt[T](a: T, b: T) -> Int { if a < b { return 1; } return 0; }
fn main() -> Int {
    let z: Str = "z";
    let e: Str = "é";
    let a = lt(z, e);
    let b = lt(e, z);
    if a == 1 && b == 0 { return 2; }
    return 9;
}
