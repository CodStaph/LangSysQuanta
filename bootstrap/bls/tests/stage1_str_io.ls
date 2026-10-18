// stage1: read_file/write_file accept a Str path.
fn main() -> Int {
    let inp: Str = "bootstrap/bls/tests/hello.ls";
    let out: Str = "bootstrap/build/str_io_out.txt";
    let buf: Array[U8, 512] = Array.zeroed();
    let n = read_file(inp, buf, 512);
    if n <= 0 { return 1; }
    let m = write_file(out, buf, n);
    if m != n { return 2; }
    return n;
}
