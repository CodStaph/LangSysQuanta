// B2: `val` parameter mode is an immutable by-value binding in B-LS.
fn add(val x: Int, val y: Int) -> Int {
    return x + y;
}

fn main() -> Int {
    return add(3, 4);
}
