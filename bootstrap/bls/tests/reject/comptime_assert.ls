// B5-11: a false comptime assertion is a compile-time error.
fn main() -> Int {
    comptime { 2 + 2 == 5; }
    return 7;
}
