// Dossier A / reject — every item below must be rejected.
// Target: 00 §4.11, 03 §4.0, ADR-19.

struct Packet { header: U8, payload: val[Slice[U8]] }

// EXPECT: E-LS-REGION-ESCAPE
// ref field cannot be returned; it cannot outlive the borrow.
struct BadCursor { src: ref[Slice[U8]] }

fn bad(src: ref[Slice[U8]]) -> BadCursor {
    BadCursor { src }
}

// EXPECT: E-LS-STATIC
// A Packet borrows its source; it cannot be stored in static storage.
fn bad_store(p: Packet) {
    static S: Packet = p;
}

// EXPECT: E-LS-UNIQ
// recover must consume every alias; q is still live.
fn bad_recover(p: val[Packet]) -> Packet {
    let q = p;
    recover { p }
}
