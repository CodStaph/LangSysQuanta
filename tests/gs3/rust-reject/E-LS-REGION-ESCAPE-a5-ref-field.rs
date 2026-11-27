// EXPECT-RUSTC: E0597
// Rust counterpart of E-LS-REGION-ESCAPE-a5-ref-field:
// a struct carrying a reference to a local escapes the local's scope
// (rustc: E0597, borrowed value does not live long enough).
struct Header { id: u8 }
struct Packet { header: u8, payload: &'static Header }

fn leak() -> Packet {
    let h = Header { id: 1 };
    Packet { header: 1, payload: &h }
}
