// EXPECT-RUSTC: E0507
// Rust counterpart of E-LS-UNIQ-val-alias-field:
// a handle stored in an aggregate field cannot be moved out behind a
// shared reference the way the aliased copy assumes it can.
struct S { f: String }

fn bad(s: &S) -> String {
    s.f
}
