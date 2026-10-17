// B-LS Str: general string variables, copy, Str parameters and .len.
fn str_len(s: Str) -> Int {
    return s.len;
}

fn main() -> Int {
    let s = "你好, Str ✅\n";
    let t: Str = s;
    write(t);

    let u: Str = "x";
    u = s;
    return str_len(u);
}
