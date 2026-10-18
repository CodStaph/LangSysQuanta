// Regression: division and modulo must emit cqo/idiv exactly once.
fn main() -> Int {
    let j = 8;
    let d = j / 8;
    let r = j % 8;
    let a = 17 / 5;
    let b = 17 % 5;
    return d * 100 + r * 10 + a * 10 + b;
}
