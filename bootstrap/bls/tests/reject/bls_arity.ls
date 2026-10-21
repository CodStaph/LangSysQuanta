// B-LS B0: function signature side table checks call arity before codegen.
fn f(a: Int, b: Int) -> Int { return a + b; }
fn main() -> Int { return f(1); }
