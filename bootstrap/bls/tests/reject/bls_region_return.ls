// B-LS B3-4c: return inside a region block is not implemented.
fn f() -> Int {
    region R {
        return 1;
    }
    return 0;
}

fn main() -> Int {
    return f();
}
