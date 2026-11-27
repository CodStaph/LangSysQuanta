fn emit1(code: Slice[U8], st: Slice[Int], b: Int) -> Int {
    code[st[0]] = b;
    st[0] = st[0] + 1;
    return 0;
}

fn emit4(code: Slice[U8], st: Slice[Int], v: Int) -> Int {
    emit1(code, st, v & 255);
    emit1(code, st, (v >> 8) & 255);
    emit1(code, st, (v >> 16) & 255);
    emit1(code, st, (v >> 24) & 255);
    return 0;
}

fn put32(code: Slice[U8], off: Int, v: Int) -> Int {
    code[off] = v & 255;
    code[off + 1] = (v >> 8) & 255;
    code[off + 2] = (v >> 16) & 255;
    code[off + 3] = (v >> 24) & 255;
    return 0;
}

fn put16(out: Slice[U8], off: Int, v: Int) -> Int {
    out[off] = v & 255;
    out[off + 1] = (v >> 8) & 255;
    return 0;
}

fn put64(out: Slice[U8], off: Int, v: Int) -> Int {
    let i = 0;
    while i < 8 {
        out[off + i] = v & 255;
        v = v >> 8;
        i = i + 1;
    }
    return 0;
}

fn copy(dst: Slice[U8], src: Slice[U8], n: Int) -> Int {
    let i = 0;
    while i < n {
        dst[i] = src[i];
        i = i + 1;
    }
    return 0;
}

// Name table (variable-length byte pool):
//   post[16000] = name count
//   post[16001] = bytes used in pool
//   entry i at 10002 + i*2 = { byte_off, byte_len }
//   byte pool starts at word 12000; offsets are byte offsets.
