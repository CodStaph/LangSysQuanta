// B5-10: unknown effect names are rejected.
fn bad() -> Int eff(bogus) {
    return 1;
}
fn main() -> Int { return 7; }
