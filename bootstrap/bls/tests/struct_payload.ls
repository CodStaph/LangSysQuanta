// B5-12: struct values as Option/Result payloads + built-in Error enum.
struct Code { n: Int }
struct Point { x: Int, y: Int }

fn mk_code(v: Int) -> Option[Code] {
    let c: Code;
    c.n = v;
    return Option.Some(c);
}

fn mk_point(a: Int, b: Int) -> Result[Point, Error] {
    let p: Point;
    p.x = a;
    p.y = b;
    if a < 0 { return Result.Err(Error.InvalidCap); }
    if b < 0 { return Result.Err(Error.NotFound); }
    return Result.Ok(p);
}

fn code_of() -> Int {
    let o: Option[Code] = mk_code(5);
    match o {
        Option.Some(c) => { return c.n; },
        Option.None => { return 1; }
    }
    return 0;
}

fn point_of(a: Int, b: Int) -> Int {
    let r: Result[Point, Error] = mk_point(a, b);
    match r {
        Result.Ok(v) => { return v.x * 10 + v.y; },
        Result.Err(e) => { return 100 + e; }
    }
    return 0;
}

fn none_path() -> Int {
    let o: Option[Code] = Option.None;
    match o {
        Option.Some(c) => { return c.n; },
        Option.None => { return 9; }
    }
    return 0;
}

fn main() -> Int {
    if code_of() != 5 { return 1; }
    if point_of(3, 4) != 34 { return 2; }
    if point_of(0 - 1, 2) != 103 { return 3; }   // Error.InvalidCap = 3
    if point_of(1, 0 - 1) != 102 { return 4; }   // Error.NotFound = 2
    if none_path() != 9 { return 5; }
    let full = Error.Full;
    if full != 1 { return 6; }
    return 7;
}
