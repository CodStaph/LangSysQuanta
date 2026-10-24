// B3-5c: `return` inside a region unwinds the region frames (-> Int functions).
fn early(n: Int) -> Int {
    region R {
        let b: Buffer[Int] = Buffer.new[Int](2, R);
        b.push(n);
        if b.len == 1 { return b[0]; }
    }
    return 0 - 1;
}

fn main() -> Int {
    if arena_used() != 0 { return 1; }
    if early(42) != 42 { return 2; }
    if arena_used() != 0 { return 3; }
    if early(7) != 7 { return 4; }
    if arena_used() != 0 { return 5; }
    return 7;
}
