// B-LS M1b-4: read_file / write_file (string-literal paths).
fn main() -> Int {
    let buf: Array[U8, 8192] = Array.zeroed();
    let n = read_file("bootstrap/bls/tests/hello.ls", buf, 8192);
    write_file("bootstrap/build/copy.ls", buf, n);
    write("io ok\n");
    return 0;
}
