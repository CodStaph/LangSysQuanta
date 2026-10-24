// B-LS B3-4c: break out of a region block is not implemented.
fn main() -> Int {
    let i = 0;
    while i < 2 {
        i = i + 1;
        region R {
            break;
        }
    }
    return 0;
}
