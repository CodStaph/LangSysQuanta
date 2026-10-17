// B-LS M1a: let / arithmetic / if / while.
fn main() -> Int {
    let x = 2 + 3 * 4;
    let i = 0;
    while i < x {
        i = i + 1;
    }
    if i == 14 {
        write("calc ok\n");
    } else {
        write("calc bad\n");
    }
    return i;
}
