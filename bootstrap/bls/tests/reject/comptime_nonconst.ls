// B5-11: comptime blocks need constant expressions.
fn main() -> Int {
    let x = 3;
    comptime { x + 1 == 4; }
    return 7;
}
