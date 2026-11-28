// DDC probe s6: 5 struct fields (widens the field table usage); expect 15.
struct Five { a: Int, b: Int, c: Int, d: Int, e: Int }

fn main() -> Int {
    let point: Five;
    point.a = 1;
    point.b = 2;
    point.c = 3;
    point.d = 4;
    point.e = 5;
    return point.a + point.b + point.c + point.d + point.e;
}
