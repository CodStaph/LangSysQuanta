// EXPECT: E-LS-MODE
// MODE negative (TM-0): a borrow value (ref parameter) returned by move.
//
// Equivalence class: ref-valued local escaping via `return r;` in direct
// form.  The current checker reports this at the mode gate FIRST (cannot
// move a `ref`), before region constraints are even solved — so the direct
// escape form lands on E-LS-MODE, while the struct-field carrier form
// (A-5, tests/conformance/reject/E-LS-REGION-ESCAPE-a5-ref-field.ls) lands
// on E-LS-REGION-ESCAPE.  Both files together cover the escape space.
// Rule: semantics.md §2.3.5; diagnostic precedence notes in
// spec/feature-coverage.md §4.
struct Header { id: U8 }

fn leak_ref_direct(h: Header) -> ref[Header] {
    borrow mut h as r {
        return r;                  // E-LS-MODE: cannot move a `ref` out
    }
}
