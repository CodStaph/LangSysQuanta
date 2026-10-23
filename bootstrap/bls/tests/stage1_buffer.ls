// B3-2: Buffer[Int] runtime layout (header + arena data), push/get/len/cap.
fn main() -> Int {
    let b = buffer_new(4);
    if b < 0 { return 1; }
    if buffer_len(b) != 0 { return 2; }
    if buffer_cap(b) != 4 { return 3; }
    if buffer_push(b, 11) != 1 { return 4; }
    if buffer_push(b, 22) != 2 { return 5; }
    if buffer_get(b, 0) != 11 { return 6; }
    if buffer_get(b, 1) != 22 { return 7; }
    if buffer_len(b) != 2 { return 8; }
    if buffer_push(b, 33) != 3 { return 9; }
    if buffer_push(b, 44) != 4 { return 10; }
    if buffer_push(b, 55) >= 0 { return 11; }
    if buffer_get(b, 4) >= 0 { return 12; }
    return 7;
}
