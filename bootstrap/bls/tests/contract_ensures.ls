// B5-11: a violated `ensures` traps at run time (exit 74).
fn bad(n: Int) -> Int ensures result > n {
    return n;
}

fn main() -> Int {
    return bad(3);
}
