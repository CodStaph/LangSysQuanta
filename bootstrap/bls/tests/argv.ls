// B-LS M1c-0d: argc / arg_len / arg_byte.
fn main() -> Int {
    let n = argc();
    if n < 2 { return 1; }
    if arg_len(n - 2) != 3 { return 2; }
    if arg_byte(n - 2, 0) != 102 { return 3; }  // 'f'
    if arg_byte(n - 1, 1) != 111 { return 4; }  // "boo"[1] = 'o'
    write("argv ok\n");
    return 0;
}
