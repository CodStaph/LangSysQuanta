// B5-11: a violated `requires` traps at run time (exit 73).
fn pos(x: Int) -> Int requires x > 0 {
    return x + 1;
}

fn main() -> Int {
    return pos(0);
}
