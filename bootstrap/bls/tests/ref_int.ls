// B5-1: read/write through `ref x: Int` temporary borrows.
fn bump(ref x: Int) -> Int {
    x = x + 1;
    return x;
}
fn sum_ref(ref a: Int, ref b: Int) -> Int {
    a = a + 2;
    b = b + 3;
    return a + b;
}
fn twice(ref x: Int) -> Int { return x * 2; }
fn inner(ref x: Int) -> Int { return x + 1; }
fn outer(ref y: Int) -> Int { return inner(y); }

fn main() -> Int {
    let a = 3;
    let b = 4;
    if twice(a) != 6 { return 1; }
    if bump(a) != 4 { return 2; }
    if a != 4 { return 3; }
    if sum_ref(a, b) != 13 { return 4; }   // 6 + 7
    if a != 6 { return 5; }
    if b != 7 { return 6; }
    if outer(a) != 7 { return 7; }   // 6 + 1, ref forwarding
    return 7;
}
