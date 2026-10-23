// B-LS B3-3: Buffer.try_new requires a `Result[Buffer[Int], Int]` annotation.
fn main() -> Int {
    let x = Buffer.try_new[Int](4, heap);
    return 0;
}
