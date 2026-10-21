// Stage 2: generic Str + (concat) and character-based comparison.
fn add[T](a: T, b: T) -> T { return a + b; }
fn eq[T](a: T, b: T) -> Int { if a == b { return 1; } return 0; }
fn lt[T](a: T, b: T) -> Int { if a < b { return 1; } return 0; }
fn main() -> Int {
    let s: Str = "a";
    let t: Str = "b";
    let ab: Str = "ab";
    let u: Str = add(s, t);
    let same = eq(u, ab);
    let less = lt(s, t);
    if same == 1 && less == 1 { return u.len; }
    return 9;
}
