// Dossier A / accept — zero-copy packet parser and cursor.
// Target: 00 §4.11, 03 §4.0, ADR-19.
// Status: draft; not yet accepted by a checker.

// prelude audited primitive (budget: 1)
fn view[T](s: val[Slice[T]], off: USize, len: USize) -> Result[val[Slice[T]], Error]
    requires off + len <= s.len
    ensures  Ok(v) => v.len == len

struct Header { version: U8, len: U16, proto: U8 }

// val field: region is inferred from src; no 'a in source
struct Packet {
    header: Header,
    payload: val[Slice[U8]],
}

fn parse(src: val[Slice[U8]]) -> Result[Packet, Error]
    requires src.len >= 4
    ensures  Ok(p) => p.payload.len == p.header.len as USize
{
    if src.len < 4 { return Err(Error.Truncated); }
    let h = Header {
        version: src[0],
        len: u16_be(src[1], src[2]),
        proto: src[3],
    };
    let n = h.len as USize;
    if src.len < 4 + n { return Err(Error.Truncated); }
    Ok(Packet { header: h, payload: src.view(4, n)? })
}

// Cursor: val + position, returnable; mutation via ref[Cursor]
struct Cursor {
    src: val[Slice[U8]],
    pos: USize,
}

fn cursor(src: val[Slice[U8]]) -> Cursor {
    Cursor { src, pos: 0 }
}

fn next_u8(c: ref[Cursor]) -> Result[U8, Error] {
    if c.pos >= c.src.len { return Err(Error.Eof); }
    let b = c.src[c.pos];
    c.pos += 1;
    Ok(b)
}

// scatter-gather: views only, no payload copy
struct Seg { base: val[Slice[U8]] }

struct IoVec {
    segs: Array[Seg, 4],
    n: USize,
}

fn scatter(p: val[Packet]) -> IoVec {
    let mut v = IoVec { segs: Array.zeroed(), n: 0 };
    v.segs[0] = Seg { base: p.payload };
    v.n = 1;
    v
}
