// Dossier B / reject — every item below must be rejected.
// Target: 00 §6.7, 03 §4.1.

struct Node { first_child: Option[USize], next_sibling: Option[USize] }

// EXPECT: E-LS-RECURSION
// kernel forbids recursion unless #[recursion(bound = N)] is present.
fn no_bound(n: ref[Node]) -> USize {
    let mut c = n.first_child;
    while c.is_some() {
        return no_bound(n);
    }
    0
}

// EXPECT: E-LS-STACK
// 64 frames exceed the 8KB stack budget for this frame size.
#[recursion(bound = 64)]
fn too_deep(n: ref[Node]) -> USize {
    let mut c = n.first_child;
    while c.is_some() {
        return too_deep(n);
    }
    0
}

// EXPECT: E-LS-DIAL
// Disabling bounds checks requires a contract; here it is missing.
const DT_MAX_DEPTH: USize = 64;
#[bounds(off)]
fn unchecked_push(stack: ref[Array[USize, DT_MAX_DEPTH]], sp: USize, v: USize) {
    stack[sp] = v;
}
