// B-LS M1c-0c: tag-only match on enums.
enum Color { Red, Green, Blue }

fn main() -> Int {
    let c = Color.Green;
    match c {
        Color.Red => { write("red\n"); },
        Color.Green => { write("green\n"); },
        Color.Blue => { write("blue\n"); }
    }
    return 1;
}
