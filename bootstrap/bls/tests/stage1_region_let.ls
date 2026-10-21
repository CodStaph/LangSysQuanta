// B-LS B2: non-empty region block is accepted as a lexical grouping.
fn main() -> Int {
    region R {
        let x = 1;
    }
    return 0;
}
