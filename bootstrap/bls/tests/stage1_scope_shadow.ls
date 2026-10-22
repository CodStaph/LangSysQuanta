// B2-2: inner `let` shadows the outer binding and the outer value is restored
// after the block.
fn main() -> Int {
    let x = 1;
    if 1 == 1 {
        let x = 2;
        if x != 2 { return 1; }
    }
    if x != 1 { return 2; }
    return 7;
}
