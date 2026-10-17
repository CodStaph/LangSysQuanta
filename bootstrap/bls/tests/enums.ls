// B-LS M1b-3a: monomorphic tag-only enums.
enum Color { Red, Green, Blue }

fn main() -> Int {
    let c = Color.Green;
    if c == Color.Green {
        write("enum ok\n");
    }
    return c;
}
