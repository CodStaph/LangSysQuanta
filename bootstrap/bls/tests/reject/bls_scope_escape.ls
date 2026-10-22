// B2-2: a block-local `let` is not visible after its block.
fn main() -> Int {
    if 1 == 1 { let x = 1; }
    return x;
}
