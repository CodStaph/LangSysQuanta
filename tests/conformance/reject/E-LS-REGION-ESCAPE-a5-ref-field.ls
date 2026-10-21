// EXPECT: E-LS-REGION-ESCAPE
// A-5: a struct with a `ref` field pointing into `region R` escapes R.
// Without `Rgn*` the outer region of `Packet` is the function ambient, so the
// embedded ref would be invisible; with the footprint, `R` is checked.
struct Header { id: U8 }
struct Packet { header: U8, payload: ref[Header] }

fn leak() -> Packet {
    region R {
        let mut h: Header = Header { id: 1 };
        borrow mut h as r {
            return Packet { header: 1, payload: r };
        }
    }
}
