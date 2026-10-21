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

// EXPECT: E-LS-REGION-ESCAPE
// A-5: a struct with a `ref` field pointing into `region R` escapes R.
struct A5Header { id: U8 }
struct A5Packet { header: U8, payload: ref[A5Header] }

fn bad_a5() -> A5Packet {
    region R {
        let mut h: A5Header = A5Header { id: 1 };
        borrow mut h as r {
            return A5Packet { header: 1, payload: r };
        }
    }
}
