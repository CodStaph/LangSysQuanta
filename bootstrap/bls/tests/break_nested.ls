// Regression: a break inside a nested loop must not be re-patched by a
// later loop at the same nesting depth.
fn main() -> Int {
    let total = 0;
    let i = 0;
    while i < 3 {
        let j = 0;
        while j < 3 {
            if j == 1 { break; }
            total = total + 1;
            j = j + 1;
        }
        i = i + 1;
    }
    return total + 100;
}
