// B4: Add does not accept Slice, even though the body only uses `+`.
fn add[T: Add](a: T, b: T) -> T { return a + b; }
fn main() -> Int {
    let arr: Array[U8, 2] = Array.zeroed();
    let s: Slice[U8] = slice(arr, 0, 2);
    let x = add(s, s);
    return 0;
}
