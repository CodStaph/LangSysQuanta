// B5-7: ref array elements are Int-only in B-LS.
fn main() -> Int {
    let a: Array[U8, 2] = Array.zeroed();
    let r: ref[Int] = a[0];
    return 0;
}
