// Boundary positive (TM-0, spec/test-matrix.md §3.2): returning the owned
// value after a borrow has ended — one step from
// reject/E-LS-MODE-return-ref-direct.ls (which returns the ref itself).
// Rule: semantics.md §2.3.5 (owned values may move out; refs may not).
struct Header { id: U8 }

fn accept_mode_return_owned(h: Header) -> Header {
    let mut m: Header = h;
    borrow mut m as r {
        r.id += 1;
    }
    return m;                     // OK: owned value, not a `ref`
}
