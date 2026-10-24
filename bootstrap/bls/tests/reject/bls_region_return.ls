// B-LS B3-5c: return inside a region is only implemented for -> Int functions.
fn f() -> Result[Buffer[Int], AllocError] {
    region R {
        let r: Result[Buffer[Int], AllocError] = Buffer.try_new[Int](2, R);
        return r;
    }
}

fn main() -> Int {
    return 0;
}
