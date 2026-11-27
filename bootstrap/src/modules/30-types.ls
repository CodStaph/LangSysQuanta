fn utf8_count(s: Slice[U8], start: Int, len: Int) -> Int {
    let n = 0;
    let i = 0;
    while i < len {
        let b = s[start + i];
        if (b & 192) != 128 { n = n + 1; }
        i = i + 1;
    }
    return n;
}

// Parse a "..." literal at st[0] into data. st[6] is the data cursor;
// st[7] receives the literal start. Returns byte length.
fn parse_str_lit(src: Slice[U8], st: Slice[Int], data: Slice[U8]) -> Int {
    if expect_char(src, st, 34, st[1]) == 0 { st[3] = 1; return 0; }
    let start = st[6];
    let len = 0;
    while st[0] < st[1] && src[st[0]] != 34 {
        let cc = src[st[0]];
        if cc == 92 && st[0] + 1 < st[1] {
            st[0] = st[0] + 1;
            cc = src[st[0]];
            if cc == 110 { cc = 10; }
            else if cc == 116 { cc = 9; }
            else if cc == 114 { cc = 13; }
        }
        data[st[6]] = cc;
        st[6] = st[6] + 1;
        len = len + 1;
        st[0] = st[0] + 1;
    }
    if expect_char(src, st, 34, st[1]) == 0 { st[3] = 1; return 0; }
    data[st[6]] = 0;
    st[6] = st[6] + 1;
    st[7] = start;
    return len;
}

// Struct table: [5120] count, entry i at 5121 + i*18 { name, nfields,
//   then 8 * { field_name, meta } }; meta = off (bits 0..30) | elem << 31.
fn st_find(post: Slice[Int], nm: Int) -> Int {
    let cnt = post[5120];
    let i = 0;
    while i < cnt {
        if post[5121 + i * 18] == nm { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn st_add(post: Slice[Int], nm: Int) -> Int {
    let c = post[5120];
    let base = 5121 + c * 18;
    post[base] = nm;
    post[base + 1] = 0;
    post[5120] = c + 1;
    return c;
}

fn st_field_add(post: Slice[Int], si: Int, fname: Int, meta: Int) -> Int {
    let base = 5121 + si * 18;
    let n = post[base + 1];
    post[base + 2 + n * 2] = fname;
    post[base + 3 + n * 2] = meta;
    post[base + 1] = n + 1;
    return n;
}

fn st_field_find(post: Slice[Int], si: Int, fname: Int) -> Int {
    let base = 5121 + si * 18;
    let cnt = post[base + 1];
    let i = 0;
    while i < cnt {
        if post[base + 2 + i * 2] == fname { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn st_size(post: Slice[Int], si: Int) -> Int {
    let base = 5121 + si * 18;
    let cnt = post[base + 1];
    let i = 0;
    let mx = 0;
    while i < cnt {
        let meta = post[base + 3 + i * 2];
        let off = meta & 2147483647;
        let elem = (meta >> 31) & 15;
        let esz = elem;
        if elem >= 11 { esz = 8; }
        if off + esz > mx { mx = off + esz; }
        i = i + 1;
    }
    return mx;
}

// Struct variables: [6400] count, entry i at 6401 + i*4 { name, fn, off, sidx }
fn sv_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[6400];
    let i = 0;
    while i < cnt {
        if post[6401 + i * 4] == nm && post[6402 + i * 4] == fnidx { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

// B5-8: the declaration scope end (send) is packed above the 31-bit offset so
// escape checks can compare the lifetime of a struct variable with a ref.
// `packed` = off | (send << 31); the 6-slot ABI forbids a 7th argument.
fn sv_add(post: Slice[Int], nm: Int, fnidx: Int, packed: Int, sidx: Int) -> Int {
    let c = post[6400];
    post[6401 + c * 4] = nm;
    post[6402 + c * 4] = fnidx;
    post[6403 + c * 4] = packed;
    post[6404 + c * 4] = sidx;
    post[6400] = c + 1;
    return c;
}

// Enum table: [7000] count, entry i at 7001 + i*18 { name, nvariants,
//   then 8 * { variant_name, tag } }
fn en_find(post: Slice[Int], nm: Int) -> Int {
    let cnt = post[7000];
    let i = 0;
    while i < cnt {
        if post[7001 + i * 18] == nm { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn en_add(post: Slice[Int], nm: Int) -> Int {
    let c = post[7000];
    let base = 7001 + c * 18;
    post[base] = nm;
    post[base + 1] = 0;
    post[7000] = c + 1;
    return c;
}

fn en_var_add(post: Slice[Int], ei: Int, vname: Int, tag: Int) -> Int {
    let base = 7001 + ei * 18;
    let n = post[base + 1];
    post[base + 2 + n * 2] = vname;
    post[base + 3 + n * 2] = tag;
    post[base + 1] = n + 1;
    return n;
}

fn en_var_find(post: Slice[Int], ei: Int, vname: Int) -> Int {
    let base = 7001 + ei * 18;
    let cnt = post[base + 1];
    let i = 0;
    while i < cnt {
        if post[base + 2 + i * 2] == vname { return post[base + 3 + i * 2]; }
        i = i + 1;
    }
    return 0 - 1;
}

// Option/Result variable table: [90000] count, entry i at 90001 + i*6
//   { name, fn, kind, t1, t2, off }   kind: 1 Option, 2 Result
// type codes: 1 Int, 2 U8, 3 Str, 4 Slice[U8], 5 Slice[Int]
fn opt_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[90000];
    let i = 0;
    while i < cnt {
        if post[90001 + i * 6] == nm && post[90002 + i * 6] == fnidx { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn opt_add(post: Slice[Int], nm: Int, fnidx: Int, meta: Int, off: Int) -> Int {
    let c = post[90000];
    let base = 90001 + c * 6;
    post[base] = nm;
    post[base + 1] = fnidx;
    post[base + 2] = meta;
    post[base + 3] = 0;
    post[base + 4] = 0;
    post[base + 5] = off;
    post[90000] = c + 1;
    return c;
}

fn ty_width(ty: Int) -> Int {
    if ty == 3 { return 3; }
    if ty == 4 || ty == 5 { return 2; }
    return 1;
}

fn ty_size(ty: Int) -> Int {
    return 8 + ty_width(ty) * 8;
}

// Expression type encoding (post[110000 + i] holds the type of post entry i):
//   scalar: 1 Int, 2 U8, 3 Str, 4 Slice[U8], 5 Slice[Int]
//   generic: 6 Option | t1 << 8, 7 Result | t1 << 8 | t2 << 16
fn elem_ty(elem: Int) -> Int {
    if elem == 1 { return 2; }
    if elem >= 11 { return elem; }
    return 1;
}

fn slice_ty(elem: Int) -> Int {
    if elem == 1 { return 4; }
    return 5;
}

fn ty_kind(ty: Int) -> Int { return ty & 255; }
fn ty_t1(ty: Int) -> Int { return (ty >> 8) & 255; }
fn ty_t2(ty: Int) -> Int { return (ty >> 16) & 255; }
fn mk_opt_ty(t1: Int) -> Int { return 6 | (t1 << 8); }
fn mk_res_ty(t1: Int, t2: Int) -> Int { return 7 | (t1 << 8) | (t2 << 16); }

// B4: generic parameter table for the signature/body currently being parsed.
//   post[135900] = count (0..2), post[135901 + i] = name id
fn gen_find(post: Slice[Int], nm: Int) -> Int {
    let c = post[135900];
    let i = 0;
    while i < c {
        if post[135901 + i] == nm { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

// Peek an identifier; if it names a current generic parameter, return 100+idx
// and consume it, otherwise rewind and return -1.
fn gen_peek(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let save = st[0];
    skip(src, st, st[1]);
    if st[0] >= st[1] || is_ident_byte(src[st[0]]) == 0 { st[0] = save; return 0 - 1; }
    let nid = name_id(src, st, post);
    if st[5] == 0 { st[0] = save; return 0 - 1; }
    let gi = gen_find(post, nid);
    if gi >= 0 { return 100 + gi; }
    st[0] = save;
    return 0 - 1;
}

// Parse a concrete payload type: Int, U8, Str, Slice[U8], Slice[Int],
// Buffer[Int] (type 9; handle-sized, used by Buffer.try_new's Result).
// B4: a current generic parameter name yields 100 + index.
fn parse_ty(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let n = st[1];
    skip(src, st, n);
    if st[0] >= n { st[3] = 1; return 0; }
    let gt = gen_peek(src, st, post);
    if gt >= 0 { return gt; }
    let c = src[st[0]];
    if c == 114 && kw_end(src, st[0] + 3, n) == 1 {
        // B5-9: `ref[T]` is a pointer-sized payload (borrow stored in a value).
        let rvt = parse_ref_ty(src, st, n);
        if rvt == 0 { st[3] = 1; return 0; }
        return rvt;
    }
    if c == 66 && st[0] + 6 <= n && src[st[0] + 1] == 117 && src[st[0] + 2] == 102 && src[st[0] + 3] == 102 && src[st[0] + 4] == 101 && src[st[0] + 5] == 114 && kw_end(src, st[0] + 6, n) == 1 {
        // B3-3: Buffer[Int] is the only Buffer payload type; the value is the
        // arena handle (same representation as a Buffer[Int] let).
        if expect_char(src, st, 66, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 117, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 102, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 102, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 101, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 91, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 73, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 110, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 116, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
        return 9;
    }
    if c == 73 {
        if expect_char(src, st, 73, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 110, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 116, n) == 0 { st[3] = 1; return 0; }
        return 1;
    }
    if c == 85 {
        if expect_char(src, st, 85, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 56, n) == 0 { st[3] = 1; return 0; }
        return 2;
    }
    if c == 83 && st[0] + 2 < n && src[st[0] + 1] == 116 && src[st[0] + 2] == 114 {
        if expect_char(src, st, 83, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 116, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        return 3;
    }
    if c == 83 {
        if expect_char(src, st, 83, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 108, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 105, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 99, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 101, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 91, n) == 0 { st[3] = 1; return 0; }
        skip(src, st, n);
        let elem = 0;
        if st[0] + 6 <= n && src[st[0]] == 66 && src[st[0] + 1] == 117 && src[st[0] + 2] == 102 && src[st[0] + 3] == 102 && src[st[0] + 4] == 101 && src[st[0] + 5] == 114 && kw_end(src, st[0] + 6, n) == 1 {
            write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
            st[3] = 1;
            return 0;
        }
        if st[0] < n && src[st[0]] == 85 {
            if expect_char(src, st, 85, n) == 0 { st[3] = 1; return 0; }
            if expect_char(src, st, 56, n) == 0 { st[3] = 1; return 0; }
            elem = 4;
        } else {
            if expect_char(src, st, 73, n) == 0 { st[3] = 1; return 0; }
            if expect_char(src, st, 110, n) == 0 { st[3] = 1; return 0; }
            if expect_char(src, st, 116, n) == 0 { st[3] = 1; return 0; }
            elem = 5;
        }
        if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
        return elem;
    }
    if c == 69 && st[0] + 5 <= n && src[st[0] + 1] == 114 && src[st[0] + 2] == 114 && src[st[0] + 3] == 111 && src[st[0] + 4] == 114 && kw_end(src, st[0] + 5, n) == 1 {
        // B5-12: `Error` is the compact Copy error enum (8-byte tag).
        if expect_char(src, st, 69, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 111, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        return 20;
    }
    if c == 65 && st[0] + 10 <= n && src[st[0] + 1] == 108 && src[st[0] + 2] == 108 && src[st[0] + 3] == 111 && src[st[0] + 4] == 99 && src[st[0] + 5] == 69 && src[st[0] + 6] == 114 && src[st[0] + 7] == 114 && src[st[0] + 8] == 111 && src[st[0] + 9] == 114 && kw_end(src, st[0] + 10, n) == 1 {
        // B3-5b: AllocError is the named allocation-failure type (Int-sized;
        // the runtime code is -1). It only appears as a Result error payload.
        if expect_char(src, st, 65, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 108, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 108, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 111, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 99, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 69, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 111, n) == 0 { st[3] = 1; return 0; }
        if expect_char(src, st, 114, n) == 0 { st[3] = 1; return 0; }
        return 10;
    }
    // B5-12: a user struct with 8-byte-aligned fields is a value payload (30+si).
    if is_ident_byte(src[st[0]]) == 1 {
        let ssave = st[0];
        let snid = name_id(src, st, post);
        if st[5] != 0 {
            let ssi = st_find(post, snid);
            let sgi = tmpl_find(post, snid);
            let sgen = 0;
            if sgi >= 0 {
                if (post[123001 + sgi * 12 + 1] & 128) != 0 { sgen = 1; }
            }
            if ssi >= 0 && ssi < 70 {
                let ssz = st_size(post, ssi);
                if ssz > 0 && (ssz & 7) == 0 { return 30 + ssi; }
                if sgen == 1 {
                    // R2.2: `S[Int, Str]` resolves a generic struct instance
                    // (120+ii).  The name also has a scan_funcs-registered
                    // `st` row, so this shared branch parses the instance.
                    let tsave = st[0];
                    skip(src, st, st[1]);
                    if st[0] < st[1] && src[st[0]] == 91 {
                        st[0] = st[0] + 1;
                        let it1 = parse_ty(src, st, post);
                        if st[3] != 0 || it1 == 0 { st[0] = tsave; st[3] = 1; return 0; }
                        let it2 = 0;
                        skip(src, st, st[1]);
                        if st[0] < st[1] && src[st[0]] == 44 {
                            st[0] = st[0] + 1;
                            it2 = parse_ty(src, st, post);
                            if st[3] != 0 || it2 == 0 { st[0] = tsave; st[3] = 1; return 0; }
                        }
                        if expect_char(src, st, 93, st[1]) == 0 { st[3] = 1; return 0; }
                        let ii = mk_inst(post, sgi, it1, it2);
                        if ii < 0 { st[3] = 1; return 0; }
                        return 120 + ii;
                    }
                    st[0] = tsave;
                }
            }
        }
        st[0] = ssave;
    }
    st[3] = 1;
    return 0;
}

// Generic enum templates / instances (scalar payloads only).
// templates: [123000] count, entry 123001 + i*12
//   { name, nparams, nvariants, vname0, pty0, ..., vname3, pty3 }
// instances: [124000] count, entry 124001 + i*12
//   { tmpl, t1, t2, enidx, ... }
