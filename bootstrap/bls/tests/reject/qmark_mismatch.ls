fn make(x: Int) -> Option[Str] {
    if x == 0 { return Option.None; }
    let s: Str = "ok";
    return Option.Some(s);
}
fn use(x: Int) -> Option[Int] {
    let s: Str = make(x)?;
    return Option.Some(s.len);
}
fn main() -> Int { return 0; }
