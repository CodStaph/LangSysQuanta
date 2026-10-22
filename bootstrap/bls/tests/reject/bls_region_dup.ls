// B2: duplicate active region names are rejected.
fn main() -> Int {
    region R {
        region R { }
    }
    return 0;
}
