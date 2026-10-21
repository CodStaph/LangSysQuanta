// Stage 2: type-dispatched arithmetic on T (U8, wraps to 8 bits).
fn add[T](a: T, b: T) -> T { return a + b; }
fn main() -> Int {
    let buf: Array[U8, 4] = Array.zeroed();
    buf[0] = 250;
    buf[1] = 10;
    let x = add(buf[0], buf[1]);
    return x;
}
