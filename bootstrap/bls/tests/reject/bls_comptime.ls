// B-LS B1: comptime blocks are recognized but not implemented yet.
fn main() -> Int {
    comptime { let x = 1; }
    return 0;
}
