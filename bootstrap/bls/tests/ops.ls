// B-LS M1c-0b: logical/bitwise ops, break/continue.
fn main() -> Int {
    let x = 0;
    let i = 0;
    while i < 10 {
        i = i + 1;
        if i == 3 { continue; }
        if i == 6 { break; }
        x = x + i;
    }
    let a = (1 && 0) || (3 & 1);
    let b = (1 << 3) | 2;
    let c = (7 ^ 1) + (8 >> 1);
    if a == 1 && b == 10 && c == 10 {
        write("ops ok\n");
    }
    return x;
}
