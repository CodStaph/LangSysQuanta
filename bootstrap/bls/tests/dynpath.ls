// B-LS M1c-0d-2: read_file with a Slice path built from argv.
fn main() -> Int {
    if argc() < 1 { return 1; }
    let n = arg_len(0);
    let pbuf: Array[U8, 256] = Array.zeroed();
    let i = 0;
    while i < n {
        pbuf[i] = arg_byte(0, i);
        i = i + 1;
    }
    let p: Slice[U8] = slice(pbuf, 0, n);
    let buf: Array[U8, 8192] = Array.zeroed();
    let r = read_file(p, buf, 8192);
    if r > 0 {
        write("dynpath ok\n");
        return 0;
    }
    return 2;
}
