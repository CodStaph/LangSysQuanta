// B-LS B0: function signature side table rejects duplicate names before codegen.
fn same() -> Int { return 1; }
fn same() -> Int { return 2; }
fn main() -> Int { return same(); }
