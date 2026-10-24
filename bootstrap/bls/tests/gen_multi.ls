// B4: multi-parameter generics, bounds and bound forwarding.
enum Either[A, B] { Left(A), Right(B), Neither }

fn first[A, B](a: A, b: B) -> A { return a; }
fn second[A, B](a: A, b: B) -> B { return b; }
fn larger[T: Ord](a: T, b: T) -> T {
    if a > b { return a; }
    return b;
}
fn max_forward[T: Ord](a: T, b: T) -> T {
    return larger(a, b);
}
fn add2[T: Add](a: T, b: T) -> T { return a + b; }
fn sub2[T: Num](a: T, b: T) -> T { return a - b; }
fn left_int() -> Int {
    let e: Either[Int, Str] = Either.Left(7);
    match e {
        Either.Left(v) => { return v; },
        Either.Right(s) => { return 0 - 1; },
        Either.Neither => { return 0 - 1; }
    }
}
fn right_len() -> Int {
    let x: Str = "xyz";
    let e: Either[Int, Str] = Either.Right(x);
    match e {
        Either.Left(v) => { return 0 - 1; },
        Either.Right(s) => { return s.len; },
        Either.Neither => { return 0 - 1; }
    }
}

fn main() -> Int {
    let s: Str = "abc";
    let t: Str = "ab";
    let a = first(9, s);
    if a != 9 { return 1; }
    let b = second(9, s);
    if b.len != 3 { return 2; }
    let m = larger(3, 5);
    if m != 5 { return 3; }
    let ls = larger(s, t);
    if ls.len != 3 { return 4; }
    let fs = first(s, 5);
    if fs.len != 3 { return 4; }
    let si = second(s, 5);
    if si != 5 { return 4; }
    if left_int() != 7 { return 5; }
    if right_len() != 3 { return 6; }
    if max_forward(11, 4) != 11 { return 7; }
    if add2(1, 2) != 3 { return 8; }
    let cat = add2(s, t);
    if cat.len != 5 { return 9; }
    if sub2(9, 2) != 7 { return 10; }
    return 7;
}
