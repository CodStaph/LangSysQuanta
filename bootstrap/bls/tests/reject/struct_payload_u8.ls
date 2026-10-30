// B5-12: struct payloads must be 8-byte aligned (no U8 fields).
struct Mixed { a: Int, b: U8 }
fn main() -> Int {
    let o: Option[Mixed] = Option.None;
    return 7;
}
