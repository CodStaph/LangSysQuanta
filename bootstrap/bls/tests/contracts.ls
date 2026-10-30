// B5-11: requires/ensures contracts and non-empty comptime blocks.
fn pos(x: Int) -> Int requires x > 0 {
    return x + 1;
}

fn div_ok(a: Int, b: Int) -> Int requires b != 0 ensures result >= 0 {
    return a / b;
}

// Two returns: ensures is checked on each one; `result` is the return value.
fn bump(n: Int) -> Int ensures result > n {
    if n > 0 { return n + 1; }
    return 1;
}

fn main() -> Int {
    comptime { }
    comptime { 1 == 1; }
    comptime { 2 * 3 + 1 == 7; }
    comptime { (10 % 3) == 1; }
    if pos(5) != 6 { return 1; }
    if div_ok(8, 2) != 4 { return 2; }
    if div_ok(9, 3) != 3 { return 3; }
    if bump(3) != 4 { return 4; }
    if bump(0) != 1 { return 5; }
    return 7;
}
