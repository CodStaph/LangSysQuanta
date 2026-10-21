// B-LS B0 preflight: Buffer nested in Array is rejected before codegen.
fn main() -> Int {
    let a: Array[Buffer[Int], 2] = 0;
    return 0;
}
