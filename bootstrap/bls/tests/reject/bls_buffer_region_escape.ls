// B-LS B3-4c: Buffer handles must not be assigned (region escape).
fn main() -> Int {
    let outer: Buffer[Int] = Buffer.new[Int](2, heap);
    region R {
        let inner: Buffer[Int] = Buffer.new[Int](2, R);
        outer = inner;
    }
    return 0;
}
