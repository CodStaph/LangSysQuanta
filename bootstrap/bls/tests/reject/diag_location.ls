// R3.6: structured diagnostics - machine-readable location + fix-it.
// The diagnostic must land on a two-digit line number, and its column
// counts Unicode scalar values (not bytes): 4 spaces + "let " (4) +
// 4 CJK code points + " = " + "0" + "; " put `comptime` at column 19
// (a byte-based count would report 27: 12 bytes for the 4 CJK chars).
// s0..s7 exist only to push the statement below line 9.
fn s0() -> Int { return 0; }
fn s1() -> Int { return 1; }
fn s2() -> Int { return 2; }
fn s3() -> Int { return 3; }
fn s4() -> Int { return 4; }
fn s5() -> Int { return 5; }
fn s6() -> Int { return 6; }
fn s7() -> Int { return 7; }

fn main() -> Int {
    let 长变量名 = 0; comptime { 0; }
    return 0;
}
