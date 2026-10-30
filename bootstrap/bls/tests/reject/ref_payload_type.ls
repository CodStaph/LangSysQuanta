// B5-9: Option[ref[Int]] needs a ref payload, not an Int literal.
fn main() -> Int {
    let o: Option[ref[Int]] = Option.Some(5);
    return 7;
}
