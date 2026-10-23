// B-LS B3-4b: drop is only implemented for Buffer[Int].
fn main() -> Int {
    let x = 1;
    drop x;
    return 0;
}
