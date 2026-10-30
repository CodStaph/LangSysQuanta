// B5-10: unknown capability names are rejected.
fn bad(c: Cap[Bogus]) -> Int {
    return 1;
}
fn main() -> Int { return 7; }
