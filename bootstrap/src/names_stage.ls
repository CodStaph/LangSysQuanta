// stage1 arith (B-LS): let / arithmetic / return -> x86_64 ELF.
// M1c-3b-1 scope: single-letter vars, + - * / %, comparisons, parentheses.
// Usage: stage1-arith <input.ls> <output>

fn skip(src: Slice[U8], st: Slice[Int], n: Int) -> Int {
    while st[0] < n {
        let c = src[st[0]];
        if c == 32 || c == 9 || c == 10 || c == 13 {
            st[0] = st[0] + 1;
        } else if c == 47 && st[0] + 1 < n && src[st[0] + 1] == 47 {
            st[0] = st[0] + 2;
            while st[0] < n && src[st[0]] != 10 {
                st[0] = st[0] + 1;
            }
        } else {
            return 0;
        }
    }
    return 0;
}

fn expect_char(src: Slice[U8], st: Slice[Int], ch: Int, n: Int) -> Int {
    skip(src, st, n);
    if st[0] < n && src[st[0]] == ch {
        st[0] = st[0] + 1;
        return 1;
    }
    return 0;
}

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
//   post[12000] = name count
//   post[12001] = bytes used in pool
//   entry i at 10002 + i*2 = { byte_off, byte_len }
//   byte pool starts at word 12000; offsets are byte offsets.
fn name_id(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let start = st[0];
    let len = 0;
    while st[0] < st[1] {
        let cc = src[st[0]];
        if (cc >= 97 && cc <= 122) || (cc >= 65 && cc <= 90) || (cc >= 48 && cc <= 57) || cc == 95 || cc >= 128 {
            st[0] = st[0] + 1;
            len = len + 1;
        } else {
            break;
        }
    }
    let slen = len;
    if slen > 256 { slen = 256; }
    st[5] = slen;
    if slen == 0 { return 0; }

    let cnt = post[12000];
    let i = 0;
    while i < cnt {
        let eb = 12002 + i * 2;
        if post[eb + 1] == slen {
            let off = post[eb];
            let same = 1;
            let j = 0;
            while j < slen {
                let idx = off + j;
                let w = post[14000 + idx / 8];
                let ch = (w >> ((idx % 8) * 8)) & 255;
                if ch != src[start + j] { same = 0; break; }
                j = j + 1;
            }
            if same == 1 { return i; }
        }
        i = i + 1;
    }

    let used = post[12001];
    let eb = 12002 + cnt * 2;
    post[eb] = used;
    post[eb + 1] = slen;
    let j = 0;
    while j < slen {
        let idx = used + j;
        post[14000 + idx / 8] = post[14000 + idx / 8] | (src[start + j] << ((idx % 8) * 8));
        j = j + 1;
    }
    post[12000] = cnt + 1;
    post[12001] = used + slen;
    return cnt;
}

// Builtin name -> code: 1 argc, 2 arg_len, 3 arg_byte, 4 read_file, 5 write_file.
fn builtin_code(src: Slice[U8], start: Int, len: Int) -> Int {
    if len == 4 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 103 && src[start + 3] == 99 { return 1; }
    if len == 7 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 103 && src[start + 3] == 95 && src[start + 4] == 108 && src[start + 5] == 101 && src[start + 6] == 110 { return 2; }
    if len == 8 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 103 && src[start + 3] == 95 && src[start + 4] == 98 && src[start + 5] == 121 && src[start + 6] == 116 && src[start + 7] == 101 { return 3; }
    if len == 9 && src[start] == 114 && src[start + 1] == 101 && src[start + 2] == 97 && src[start + 3] == 100 && src[start + 4] == 95 && src[start + 5] == 102 && src[start + 6] == 105 && src[start + 7] == 108 && src[start + 8] == 101 { return 4; }
    if len == 10 && src[start] == 119 && src[start + 1] == 114 && src[start + 2] == 105 && src[start + 3] == 116 && src[start + 4] == 101 && src[start + 5] == 95 && src[start + 6] == 102 && src[start + 7] == 105 && src[start + 8] == 108 && src[start + 9] == 101 { return 5; }
    return 0;
}

// Int variable table: [9000] count, entry i at 9001 + i*4 { name, fn, off, spare }
fn var_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[9000];
    let i = 0;
    while i < cnt {
        if post[9001 + i * 4] == nm && post[9002 + i * 4] == fnidx { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn var_add(post: Slice[Int], nm: Int, fnidx: Int, off: Int) -> Int {
    let c = post[9000];
    post[9001 + c * 4] = nm;
    post[9002 + c * 4] = fnidx;
    post[9003 + c * 4] = off;
    post[9004 + c * 4] = 0;
    post[9000] = c + 1;
    return c;
}

// Metadata tables live in the high half of `post`:
//   [4096] array count, entries at 4097 + i*2 { name, meta }
//   [4608] slice count, entries at 4609 + i*2 { name, meta }
// meta: off (bits 0..19) | elem << 20 | fn << 24 | len << 32
fn arr_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[4096];
    let i = 0;
    while i < cnt {
        let meta = post[4098 + i * 2];
        if post[4097 + i * 2] == nm && ((meta >> 24) & 255) == fnidx {
            return i;
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn sl_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[4608];
    let i = 0;
    while i < cnt {
        let meta = post[4610 + i * 2];
        if post[4609 + i * 2] == nm && ((meta >> 24) & 255) == fnidx {
            return i;
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn add_arr(post: Slice[Int], nm: Int, meta: Int) -> Int {
    let c = post[4096];
    post[4097 + c * 2] = nm;
    post[4098 + c * 2] = meta;
    post[4096] = c + 1;
    return c;
}

fn add_sl(post: Slice[Int], nm: Int, meta: Int) -> Int {
    let c = post[4608];
    post[4609 + c * 2] = nm;
    post[4610 + c * 2] = meta;
    post[4608] = c + 1;
    return c;
}

// Struct table: [5120] count, entry i at 5121 + i*18 { name, nfields,
//   then 8 * { field_name, meta } }; meta = off | elem << 20.
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
        let off = meta & 1048575;
        let elem = (meta >> 20) & 15;
        if off + elem > mx { mx = off + elem; }
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

fn sv_add(post: Slice[Int], nm: Int, fnidx: Int, off: Int, sidx: Int) -> Int {
    let c = post[6400];
    post[6401 + c * 4] = nm;
    post[6402 + c * 4] = fnidx;
    post[6403 + c * 4] = off;
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

fn prec(op: Int) -> Int {
    if op == 12 { return 1; }
    if op == 13 { return 2; }
    if op == 14 { return 3; }
    if op == 15 { return 4; }
    if op == 16 { return 5; }
    if op == 6 || op == 7 { return 6; }
    if op >= 8 && op <= 11 { return 7; }
    if op == 17 || op == 18 { return 8; }
    if op == 1 || op == 2 { return 9; }
    if op >= 3 && op <= 5 { return 10; }
    if op == 20 { return 11; }
    return 0;
}

fn push_post(post: Slice[Int], st: Slice[Int], kind: Int, val: Int) -> Int {
    post[st[2] * 2] = kind;
    post[st[2] * 2 + 1] = val;
    st[2] = st[2] + 1;
    return 0;
}

// Index sub-expression parser.  Kept separate (not recursive) because the
// stage1 interpreter gives every function call its own global local slots.
fn parse_index0(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let top = 0;
    let paren = 0;
    let expect = 1;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 123 || c == 44 || c == 93 { break; }
        if c == 41 && paren == 0 { break; }
        if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nid = name_id(src, st, post);
            let vi = var_find(post, nid, st[4]);
            if vi < 0 { st[3] = 1; return 0; }
            push_post(post, st, 1, vi);
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            paren = paren + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            if top > 0 { top = top - 1; }
            paren = paren - 1;
            st[0] = st[0] + 1;
            expect = 0;
        } else {
            let op = 0;
            let len = 1;
            if c == 61 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 6; len = 2; }
            else if c == 33 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 7; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 9; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 11; len = 2; }
            else if c == 38 && st[0] + 1 < n && src[st[0] + 1] == 38 { op = 13; len = 2; }
            else if c == 124 && st[0] + 1 < n && src[st[0] + 1] == 124 { op = 12; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 60 { op = 17; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 62 { op = 18; len = 2; }
            else if c == 43 { op = 1; }
            else if c == 45 { if expect == 1 { op = 20; } else { op = 2; } }
            else if c == 42 { op = 3; }
            else if c == 47 { op = 4; }
            else if c == 37 { op = 5; }
            else if c == 60 { op = 8; }
            else if c == 62 { op = 10; }
            else if c == 38 { op = 16; }
            else if c == 124 { op = 14; }
            else if c == 94 { op = 15; }
            else { st[3] = 1; return 0; }
            while top > 0 && ops[top - 1] != 99 && prec(ops[top - 1]) >= prec(op) {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_post(post, st, 2, ops[top - 1]); }
        top = top - 1;
    }
    return 0;
}


fn parse_index1(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let top = 0;
    let paren = 0;
    let expect = 1;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 123 || c == 44 || c == 93 { break; }
        if c == 41 && paren == 0 { break; }
        if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nid = name_id(src, st, post);
            skip(src, st, n);
            if st[0] < n && src[st[0]] == 91 {
                st[0] = st[0] + 1;
                parse_index0(src, st, post);
                if st[3] != 0 { return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                let ai = arr_find(post, nid, st[4]);
                if ai >= 0 {
                    push_post(post, st, 10, ai);
                } else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 { push_post(post, st, 11, si); }
                    else { st[3] = 1; return 0; }
                }
            } else {
                let vi = var_find(post, nid, st[4]);
                if vi < 0 { st[3] = 1; return 0; }
                push_post(post, st, 1, vi);
            }
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            paren = paren + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            if top > 0 { top = top - 1; }
            paren = paren - 1;
            st[0] = st[0] + 1;
            expect = 0;
        } else {
            let op = 0;
            let len = 1;
            if c == 61 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 6; len = 2; }
            else if c == 33 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 7; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 9; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 11; len = 2; }
            else if c == 38 && st[0] + 1 < n && src[st[0] + 1] == 38 { op = 13; len = 2; }
            else if c == 124 && st[0] + 1 < n && src[st[0] + 1] == 124 { op = 12; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 60 { op = 17; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 62 { op = 18; len = 2; }
            else if c == 43 { op = 1; }
            else if c == 45 { if expect == 1 { op = 20; } else { op = 2; } }
            else if c == 42 { op = 3; }
            else if c == 47 { op = 4; }
            else if c == 37 { op = 5; }
            else if c == 60 { op = 8; }
            else if c == 62 { op = 10; }
            else if c == 38 { op = 16; }
            else if c == 124 { op = 14; }
            else if c == 94 { op = 15; }
            else { st[3] = 1; return 0; }
            while top > 0 && ops[top - 1] != 99 && prec(ops[top - 1]) >= prec(op) {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_post(post, st, 2, ops[top - 1]); }
        top = top - 1;
    }
    return 0;
}


fn parse_index(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let top = 0;
    let paren = 0;
    let expect = 1;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 123 || c == 44 || c == 93 { break; }
        if c == 41 && paren == 0 { break; }
        if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nid = name_id(src, st, post);
            skip(src, st, n);
            if st[0] < n && src[st[0]] == 91 {
                st[0] = st[0] + 1;
                parse_index1(src, st, post);
                if st[3] != 0 { return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                let ai = arr_find(post, nid, st[4]);
                if ai >= 0 {
                    push_post(post, st, 10, ai);
                } else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 { push_post(post, st, 11, si); }
                    else { st[3] = 1; return 0; }
                }
            } else {
                let vi = var_find(post, nid, st[4]);
                if vi < 0 { st[3] = 1; return 0; }
                push_post(post, st, 1, vi);
            }
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            paren = paren + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            if top > 0 { top = top - 1; }
            paren = paren - 1;
            st[0] = st[0] + 1;
            expect = 0;
        } else {
            let op = 0;
            let len = 1;
            if c == 61 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 6; len = 2; }
            else if c == 33 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 7; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 9; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 11; len = 2; }
            else if c == 38 && st[0] + 1 < n && src[st[0] + 1] == 38 { op = 13; len = 2; }
            else if c == 124 && st[0] + 1 < n && src[st[0] + 1] == 124 { op = 12; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 60 { op = 17; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 62 { op = 18; len = 2; }
            else if c == 43 { op = 1; }
            else if c == 45 { if expect == 1 { op = 20; } else { op = 2; } }
            else if c == 42 { op = 3; }
            else if c == 47 { op = 4; }
            else if c == 37 { op = 5; }
            else if c == 60 { op = 8; }
            else if c == 62 { op = 10; }
            else if c == 38 { op = 16; }
            else if c == 124 { op = 14; }
            else if c == 94 { op = 15; }
            else { st[3] = 1; return 0; }
            while top > 0 && ops[top - 1] != 99 && prec(ops[top - 1]) >= prec(op) {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_post(post, st, 2, ops[top - 1]); }
        top = top - 1;
    }
    return 0;
}

fn parse_expr(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let top = 0;
    let paren = 0;
    let expect = 1;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 123 || c == 44 || c == 93 { break; }
        if c == 41 && paren == 0 { break; }
        if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nstart = st[0];
            let name = name_id(src, st, post);
            let bcode = builtin_code(src, nstart, st[5]);
            skip(src, st, n);
            if st[0] < n && src[st[0]] == 40 && bcode != 0 {
                st[0] = st[0] + 1;
                if bcode == 1 {
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 41, 0);
                } else if bcode == 2 || bcode == 3 {
                    let aslots = 0;
                    while 1 {
                        skip(src, st, n);
                        if st[0] < n && src[st[0]] == 41 { st[0] = st[0] + 1; break; }
                        if st[0] >= n { st[3] = 1; return 0; }
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        aslots = aslots + 1;
                        skip(src, st, n);
                        if st[0] < n && src[st[0]] == 44 { st[0] = st[0] + 1; }
                        else if st[0] < n && src[st[0]] == 41 { st[0] = st[0] + 1; break; }
                        else { st[3] = 1; return 0; }
                    }
                    push_post(post, st, 40 + bcode, aslots);
                } else {
                    skip(src, st, n);
                    let pn = name_id(src, st, post);
                    if st[5] == 0 { st[3] = 1; return 0; }
                    let psi = sl_find(post, pn, st[4]);
                    if psi < 0 { st[3] = 1; return 0; }
                    push_post(post, st, 13, psi);
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    skip(src, st, n);
                    let bn = name_id(src, st, post);
                    if st[5] == 0 { st[3] = 1; return 0; }
                    let bai = arr_find(post, bn, st[4]);
                    if bai < 0 { st[3] = 1; return 0; }
                    push_post(post, st, 18, bai);
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 40 + bcode, 4);
                }
            } else if st[0] < n && src[st[0]] == 40 {
                st[0] = st[0] + 1;
                let slots = 0;
                while 1 {
                    skip(src, st, n);
                    if st[0] < n && src[st[0]] == 41 { st[0] = st[0] + 1; break; }
                    if st[0] >= n { st[3] = 1; return 0; }
                    let ac = src[st[0]];
                    if (ac >= 97 && ac <= 122) || (ac >= 65 && ac <= 90) || ac == 95 || ac >= 128 {
                        let save0 = st[0];
                        let anid = name_id(src, st, post);
                        skip(src, st, n);
                        let nxt = 0;
                        if st[0] < n { nxt = src[st[0]]; }
                        if nxt == 44 || nxt == 41 {
                            let si = sl_find(post, anid, st[4]);
                            if si >= 0 {
                                push_post(post, st, 13, si);
                                slots = slots + 2;
                            } else {
                                let vi = var_find(post, anid, st[4]);
                                if vi < 0 { st[3] = 1; return 0; }
                                push_post(post, st, 1, vi);
                                slots = slots + 1;
                            }
                        } else {
                            st[0] = save0;
                            parse_index(src, st, post);
                            if st[3] != 0 { return 0; }
                            slots = slots + 1;
                        }
                    } else {
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        slots = slots + 1;
                    }
                    skip(src, st, n);
                    if st[0] < n && src[st[0]] == 44 { st[0] = st[0] + 1; }
                    else if st[0] < n && src[st[0]] == 41 { st[0] = st[0] + 1; break; }
                    else { st[3] = 1; return 0; }
                }
                push_post(post, st, 3 + slots, name);
            } else if st[0] < n && src[st[0]] == 91 {
                st[0] = st[0] + 1;
                parse_index(src, st, post);
                if st[3] != 0 { return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                let ai = arr_find(post, name, st[4]);
                if ai >= 0 {
                    push_post(post, st, 10, ai);
                } else {
                    let si = sl_find(post, name, st[4]);
                    if si >= 0 { push_post(post, st, 11, si); }
                    else { st[3] = 1; return 0; }
                }
            } else if st[0] < n && src[st[0]] == 46 {
                st[0] = st[0] + 1;
                skip(src, st, n);
                let vf = name_id(src, st, post);
                if st[5] == 0 { st[3] = 1; return 0; }
                let svi = sv_find(post, name, st[4]);
                if svi >= 0 {
                    let sidx = post[6404 + svi * 4];
                    let fi = st_field_find(post, sidx, vf);
                    if fi < 0 { st[3] = 1; return 0; }
                    let fb = 5121 + sidx * 18;
                    let fmeta = post[fb + 3 + fi * 2];
                    let off = post[6403 + svi * 4] + (fmeta & 1048575);
                    let elem = (fmeta >> 20) & 15;
                    if elem == 8 { push_post(post, st, 12, off); }
                    else { push_post(post, st, 15, off); }
                } else {
                    let ei = en_find(post, name);
                    if ei < 0 { st[3] = 1; return 0; }
                    let tag = en_var_find(post, ei, vf);
                    if tag < 0 { st[3] = 1; return 0; }
                    push_post(post, st, 0, tag);
                }
            } else {
                let si = sl_find(post, name, st[4]);
                if si >= 0 { push_post(post, st, 13, si); }
                else {
                    let vi = var_find(post, name, st[4]);
                    if vi < 0 { st[3] = 1; return 0; }
                    push_post(post, st, 1, vi);
                }
            }
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            paren = paren + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            if top > 0 { top = top - 1; }
            paren = paren - 1;
            st[0] = st[0] + 1;
            expect = 0;
        } else {
            let op = 0;
            let len = 1;
            if c == 61 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 6; len = 2; }
            else if c == 33 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 7; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 9; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 61 { op = 11; len = 2; }
            else if c == 38 && st[0] + 1 < n && src[st[0] + 1] == 38 { op = 13; len = 2; }
            else if c == 124 && st[0] + 1 < n && src[st[0] + 1] == 124 { op = 12; len = 2; }
            else if c == 60 && st[0] + 1 < n && src[st[0] + 1] == 60 { op = 17; len = 2; }
            else if c == 62 && st[0] + 1 < n && src[st[0] + 1] == 62 { op = 18; len = 2; }
            else if c == 43 { op = 1; }
            else if c == 45 { if expect == 1 { op = 20; } else { op = 2; } }
            else if c == 42 { op = 3; }
            else if c == 47 { op = 4; }
            else if c == 37 { op = 5; }
            else if c == 60 { op = 8; }
            else if c == 62 { op = 10; }
            else if c == 38 { op = 16; }
            else if c == 124 { op = 14; }
            else if c == 94 { op = 15; }
            else { st[3] = 1; return 0; }
            while top > 0 && ops[top - 1] != 99 && prec(ops[top - 1]) >= prec(op) {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_post(post, st, 2, ops[top - 1]); }
        top = top - 1;
    }
    return 0;
}

fn emit_expr(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let i = 0;
    while i < cst[1] {
        let kind = post[i * 2];
        let val = post[i * 2 + 1];
        if kind == 0 {
            emit1(code, cst, 72); emit1(code, cst, 184);
            let k = 0;
            while k < 8 {
                emit1(code, cst, (val >> (k * 8)) & 255);
                k = k + 1;
            }
            emit1(code, cst, 80);
        } else if kind == 1 {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = post[9003 + val * 4];
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 80);
        } else if kind == 10 || kind == 11 {
            // rax = element load; stack top holds the index
            let meta = 0;
            if kind == 10 { meta = post[4098 + val * 2]; }
            else { meta = post[4610 + val * 2]; }
            let off = meta & 1048575;
            let elem = (meta >> 20) & 15;
            emit1(code, cst, 89); // pop rcx = index
            if kind == 10 { emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 21); }
            else { emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 21); }
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = off;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            if elem == 8 {
                emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 202);
            } else {
                emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 209);
                emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 1);
            }
            emit1(code, cst, 80);
        } else if kind == 13 {
            // Slice argument: push base, then len
            let meta = post[4610 + val * 2];
            let off = meta & 1048575;
            let k = 0;
            while k < 2 {
                emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
                post[cst[3] + cst[2] * 2] = cst[0];
                post[cst[3] + cst[2] * 2 + 1] = off + k * 8;
                cst[2] = cst[2] + 1;
                emit4(code, cst, 0);
                emit1(code, cst, 80);
                k = k + 1;
            }
        } else if kind == 12 || kind == 15 {
            // struct field load; val is the absolute data offset
            if kind == 12 { emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5); }
            else { emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 5); }
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = val;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 80);
        } else if kind == 18 {
            // Array argument: push its data address.
            let meta = post[4098 + val * 2];
            let off = meta & 1048575;
            emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = off;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 80);
        } else if kind == 41 {
            // argc()
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = cst[7];
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 80);
        } else if kind == 42 {
            // arg_len(i)
            emit1(code, cst, 89); // rcx = i
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = cst[7] + 8;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 200);
            emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 210); // xor rdx,rdx
            emit1(code, cst, 72); emit1(code, cst, 133); emit1(code, cst, 192); // test rax,rax
            emit1(code, cst, 15); emit1(code, cst, 132);
            let p0 = cst[0];
            emit4(code, cst, 0);
            let loop0 = cst[0];
            emit1(code, cst, 128); emit1(code, cst, 60); emit1(code, cst, 16); emit1(code, cst, 0);
            emit1(code, cst, 15); emit1(code, cst, 132);
            let p1 = cst[0];
            emit4(code, cst, 0);
            emit1(code, cst, 72); emit1(code, cst, 255); emit1(code, cst, 194); // inc rdx
            emit1(code, cst, 233);
            let p2 = cst[0];
            emit4(code, cst, 0);
            let end0 = cst[0];
            put32(code, p0, end0 - (p0 + 4));
            put32(code, p1, end0 - (p1 + 4));
            put32(code, p2, loop0 - (p2 + 4));
            emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 208); // mov rax,rdx
            emit1(code, cst, 80);
        } else if kind == 43 {
            // arg_byte(i, pos): args on stack (i, pos); call fixed helper
            emit1(code, cst, 94); // rsi = pos
            emit1(code, cst, 95); // rdi = i
            emit1(code, cst, 232);
            emit4(code, cst, cst[8] - (cst[0] + 4));
            emit1(code, cst, 80);
        } else if kind == 44 || kind == 45 {
            // read_file(path, buf, cap) / write_file(path, buf, len)
            emit1(code, cst, 90); // rdx = cap/len
            emit1(code, cst, 94); // rsi = buffer
            emit1(code, cst, 89); // rcx = path len
            emit1(code, cst, 95); // rdi = path base
            emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 240); // r8 = rsi
            emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 209); // r9 = rdx
            emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 254); // rsi = rdi
            emit1(code, cst, 184); emit4(code, cst, 257); // openat
            emit1(code, cst, 72); emit1(code, cst, 199); emit1(code, cst, 199); emit4(code, cst, 4294967196);
            if kind == 44 {
                emit1(code, cst, 49); emit1(code, cst, 210); // xor edx,edx
                emit1(code, cst, 69); emit1(code, cst, 49); emit1(code, cst, 210); // xor r10d,r10d
            } else {
                emit1(code, cst, 186); emit4(code, cst, 577); // rdx = 0x241
                emit1(code, cst, 65); emit1(code, cst, 186); emit4(code, cst, 420); // r10d = 0644
            }
            emit1(code, cst, 15); emit1(code, cst, 5); // syscall
            emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 199); // rdi = fd
            emit1(code, cst, 184); emit4(code, cst, 0 + (kind - 44)); // read=0 / write=1
            emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 198); // rsi = r8
            emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 202); // rdx = r9
            emit1(code, cst, 15); emit1(code, cst, 5);
            emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 192); // r8 = rax
            emit1(code, cst, 184); emit4(code, cst, 3); // close
            emit1(code, cst, 15); emit1(code, cst, 5);
            emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 192); // rax = r8
            emit1(code, cst, 80);
        } else if kind >= 3 {
            let nargs = kind - 3;
            let ai = nargs - 1;
            while ai >= 0 {
                if ai == 0 { emit1(code, cst, 95); }
                else if ai == 1 { emit1(code, cst, 94); }
                else if ai == 2 { emit1(code, cst, 90); }
                else if ai == 3 { emit1(code, cst, 89); }
                else if ai == 4 { emit1(code, cst, 65); emit1(code, cst, 88); }
                else { emit1(code, cst, 65); emit1(code, cst, 89); }
                ai = ai - 1;
            }
            emit1(code, cst, 232);
            post[cst[6] + cst[5] * 2] = cst[0];
            post[cst[6] + cst[5] * 2 + 1] = val;
            cst[5] = cst[5] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 80); // push call result
        } else {
            if val == 20 {
                emit1(code, cst, 88); // pop rax
                emit1(code, cst, 72); emit1(code, cst, 247); emit1(code, cst, 216); // neg
                emit1(code, cst, 80);
            } else {
                emit1(code, cst, 89); // pop rcx
                emit1(code, cst, 88); // pop rax
                if val == 1 { emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); }
                else if val == 2 { emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200); }
                else if val == 3 { emit1(code, cst, 72); emit1(code, cst, 15); emit1(code, cst, 175); emit1(code, cst, 193); }
                else if val == 4 {
                    emit1(code, cst, 72); emit1(code, cst, 153);
                    emit1(code, cst, 72); emit1(code, cst, 247); emit1(code, cst, 249);
                } else if val == 5 {
                    emit1(code, cst, 72); emit1(code, cst, 153);
                    emit1(code, cst, 72); emit1(code, cst, 247); emit1(code, cst, 249);
                    emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 208);
                } else if val >= 6 && val <= 11 {
                    emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 200);
                    if val == 6 { emit1(code, cst, 15); emit1(code, cst, 148); }
                    else if val == 7 { emit1(code, cst, 15); emit1(code, cst, 149); }
                    else if val == 8 { emit1(code, cst, 15); emit1(code, cst, 156); }
                    else if val == 9 { emit1(code, cst, 15); emit1(code, cst, 158); }
                    else if val == 10 { emit1(code, cst, 15); emit1(code, cst, 159); }
                    else { emit1(code, cst, 15); emit1(code, cst, 157); }
                    emit1(code, cst, 192);
                    emit1(code, cst, 72); emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 192);
                } else if val == 12 || val == 13 {
                    // non-short-circuit in this version: normalize right, combine
                    emit1(code, cst, 72); emit1(code, cst, 133); emit1(code, cst, 192);
                    emit1(code, cst, 15); emit1(code, cst, 149); emit1(code, cst, 192);
                    emit1(code, cst, 72); emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 192);
                } else if val == 14 { emit1(code, cst, 72); emit1(code, cst, 9); emit1(code, cst, 200); }
                else if val == 15 { emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 200); }
                else if val == 16 { emit1(code, cst, 72); emit1(code, cst, 33); emit1(code, cst, 200); }
                else if val == 17 { emit1(code, cst, 72); emit1(code, cst, 211); emit1(code, cst, 224); }
                else if val == 18 { emit1(code, cst, 72); emit1(code, cst, 211); emit1(code, cst, 248); }
                emit1(code, cst, 80);
            }
        }
        i = i + 1;
    }
    emit1(code, cst, 88); // pop rax
    return 0;
}

fn emit_je(code: Slice[U8], cst: Slice[Int]) -> Int {
    emit1(code, cst, 15); emit1(code, cst, 132);
    let p = cst[0];
    emit4(code, cst, 0);
    return p;
}

fn emit_jmp(code: Slice[U8], cst: Slice[Int]) -> Int {
    emit1(code, cst, 233);
    let p = cst[0];
    emit4(code, cst, 0);
    return p;
}

fn patch_jump(code: Slice[U8], pos: Int, target: Int) -> Int {
    put32(code, pos, target - (pos + 4));
    return 0;
}

fn main() -> Int {
    let src: Array[U8, 262144] = Array.zeroed();
    let code: Array[U8, 131072] = Array.zeroed();
    let data: Array[U8, 65536] = Array.zeroed();
    let out: Array[U8, 262144] = Array.zeroed();
    let path: Array[U8, 256] = Array.zeroed();
    let opath: Array[U8, 256] = Array.zeroed();
    let post: Array[Int, 65536] = Array.zeroed();
    let st: Array[Int, 16] = Array.zeroed();
    let cs: Array[Int, 16] = Array.zeroed();
    let fname: Array[Int, 64] = Array.zeroed();
    let flabel: Array[Int, 64] = Array.zeroed();
    let fparams: Array[Int, 16] = Array.zeroed();
    let fpelem: Array[Int, 16] = Array.zeroed();
    let ck: Array[Int, 64] = Array.zeroed();
    let cje: Array[Int, 64] = Array.zeroed();
    let cstart: Array[Int, 64] = Array.zeroed();
    let cjmp: Array[Int, 64] = Array.zeroed();
    let bpos: Array[Int, 64] = Array.zeroed();
    let bloop: Array[Int, 64] = Array.zeroed();
    let nbrk = 0;
    let cd = 0;
    let mkbuf: Array[U8, 8] = Array.zeroed();
    let mkst: Array[Int, 8] = Array.zeroed();
    let nf = 0;
    let dlen = 65536;
    let litlen = 0;

    if argc() < 2 { write("slice: usage: stage1-slice <in> <out>\n"); return 2; }
    let plen = arg_len(0);
    let i = 0;
    while i < plen { path[i] = arg_byte(0, i); i = i + 1; }
    let inp: Slice[U8] = slice(path, 0, plen);
    let n = read_file(inp, src, 262144);
    if n <= 0 { write("slice: read failed\n"); return 3; }
    let olen = arg_len(1);
    i = 0;
    while i < olen { opath[i] = arg_byte(1, i); i = i + 1; }
    let oup: Slice[U8] = slice(opath, 0, olen);

    let srcs: Slice[U8] = slice(src, 0, n);
    let sts: Slice[Int] = slice(st, 0, 16);
    st[0] = 0; st[1] = n; st[3] = 0; st[4] = 0; 

    let c: Slice[U8] = slice(code, 0, 131072);
    let ps: Slice[Int] = slice(post, 0, 65536);
    let css: Slice[Int] = slice(cs, 0, 16);
    cs[0] = 0; cs[2] = 0; cs[3] = 60000; cs[5] = 0; cs[6] = 40000;

    // Runtime block: argc, argv, path buffer.
    let runtime_off = dlen;
    dlen = dlen + 16 + 256;
    cs[7] = runtime_off;

    // arg_byte(i, pos) helper: rdi=i, rsi=pos -> rax=byte. One fixed call target.
    let argb_helper = cs[0];
    emit1(c, css, 72); emit1(c, css, 139); emit1(c, css, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = runtime_off + 8;
    cs[2] = cs[2] + 1;
    emit4(c, css, 0);
    emit1(c, css, 72); emit1(c, css, 139); emit1(c, css, 4); emit1(c, css, 248);
    emit1(c, css, 15); emit1(c, css, 182); emit1(c, css, 4); emit1(c, css, 48);
    emit1(c, css, 195);
    cs[8] = argb_helper;

    // Intern "main" so the final trampoline can find it by name id.
    mkbuf[0] = 109; mkbuf[1] = 97; mkbuf[2] = 105; mkbuf[3] = 110;
    mkst[0] = 0; mkst[1] = 4;
    let mks: Slice[U8] = slice(mkbuf, 0, 4);
    let mksts: Slice[Int] = slice(mkst, 0, 8);
    let main_nid = name_id(mks, mksts, ps);

    let done = 0;
    while done == 0 {
        skip(srcs, sts, n);
        if st[0] >= n { done = 1; }
        else {
            if st[0] + 1 < n && srcs[st[0]] == 115 && srcs[st[0] + 1] == 116 {
                // struct Name { field: Int/U8, ... }
                if expect_char(srcs, sts, 115, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 116, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 114, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 117, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 99, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 116, n) == 0 { write("struct: bad keyword\n"); return 4; }
                skip(srcs, sts, n);
                let snm = name_id(srcs, sts, ps);
                if st[5] == 0 { write("struct: bad name\n"); return 4; }
                let si = st_add(ps, snm);
                if expect_char(srcs, sts, 123, n) == 0 { write("struct: expected {\n"); return 4; }
                let foff = 0;
                while 1 {
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 125 { break; }
                    let fname = name_id(srcs, sts, ps);
                    if st[5] == 0 { write("struct: bad field\n"); return 4; }
                    if expect_char(srcs, sts, 58, n) == 0 { write("struct: expected :\n"); return 4; }
                    skip(srcs, sts, n);
                    let elem = 0;
                    if st[0] < n && srcs[st[0]] == 85 {
                        if expect_char(srcs, sts, 85, n) == 0 { write("struct: expected U8\n"); return 4; }
                        if expect_char(srcs, sts, 56, n) == 0 { write("struct: expected U8\n"); return 4; }
                        elem = 1;
                    } else {
                        if expect_char(srcs, sts, 73, n) == 0 { write("struct: expected Int\n"); return 4; }
                        if expect_char(srcs, sts, 110, n) == 0 { write("struct: expected Int\n"); return 4; }
                        if expect_char(srcs, sts, 116, n) == 0 { write("struct: expected Int\n"); return 4; }
                        elem = 8;
                    }
                    st_field_add(ps, si, fname, foff | (elem << 20));
                    foff = foff + elem;
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                }
                if expect_char(srcs, sts, 125, n) == 0 { write("struct: expected }\n"); return 4; }
            } else if st[0] + 1 < n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 110 {
                // enum Name { A, B, C }
                if expect_char(srcs, sts, 101, n) == 0 { write("enum: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 110, n) == 0 { write("enum: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 117, n) == 0 { write("enum: bad keyword\n"); return 4; }
                if expect_char(srcs, sts, 109, n) == 0 { write("enum: bad keyword\n"); return 4; }
                skip(srcs, sts, n);
                let enm = name_id(srcs, sts, ps);
                if st[5] == 0 { write("enum: bad name\n"); return 4; }
                let ei = en_add(ps, enm);
                if expect_char(srcs, sts, 123, n) == 0 { write("enum: expected {\n"); return 4; }
                let tag = 0;
                while 1 {
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 125 { break; }
                    let vname = name_id(srcs, sts, ps);
                    if st[5] == 0 { write("enum: bad variant\n"); return 4; }
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 40 {
                        if expect_char(srcs, sts, 40, n) == 0 { write("enum: payload\n"); return 4; }
                        if expect_char(srcs, sts, 73, n) == 0 { write("enum: payload\n"); return 4; }
                        if expect_char(srcs, sts, 110, n) == 0 { write("enum: payload\n"); return 4; }
                        if expect_char(srcs, sts, 116, n) == 0 { write("enum: payload\n"); return 4; }
                        if expect_char(srcs, sts, 41, n) == 0 { write("enum: payload\n"); return 4; }
                    }
                    en_var_add(ps, ei, vname, tag);
                    tag = tag + 1;
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                }
                if expect_char(srcs, sts, 125, n) == 0 { write("enum: expected }\n"); return 4; }
            } else {
            if expect_char(srcs, sts, 102, n) == 0 { write("slice: expected fn\n"); return 4; }
            if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected fn\n"); return 4; }
            skip(srcs, sts, n);
            let fnm = name_id(srcs, sts, ps);
            if st[5] == 0 { write("slice: bad name\n"); return 4; }
            if expect_char(srcs, sts, 40, n) == 0 { write("slice: expected (\n"); return 4; }
            let pc = 0;
            while 1 {
                skip(srcs, sts, n);
                if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                if pc >= 6 { write("names: too many params\n"); return 4; }
                let pid = name_id(srcs, sts, ps);
                if st[5] == 0 { write("names: bad param\n"); return 4; }
                fparams[pc] = pid;
                if expect_char(srcs, sts, 58, n) == 0 { write("names: expected :\n"); return 4; }
                skip(srcs, sts, n);
                let pe = 0;
                if st[0] < n && srcs[st[0]] == 73 {
                    if expect_char(srcs, sts, 73, n) == 0 { write("names: expected Int\n"); return 4; }
                    if expect_char(srcs, sts, 110, n) == 0 { write("names: expected Int\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("names: expected Int\n"); return 4; }
                    pe = 0;
                } else if st[0] < n && srcs[st[0]] == 83 {
                    if expect_char(srcs, sts, 83, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 108, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 105, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 99, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 91, n) == 0 { write("names: expected [\n"); return 4; }
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 85 {
                        if expect_char(srcs, sts, 85, n) == 0 { write("names: expected U8\n"); return 4; }
                        if expect_char(srcs, sts, 56, n) == 0 { write("names: expected U8\n"); return 4; }
                        pe = 1;
                    } else {
                        if expect_char(srcs, sts, 73, n) == 0 { write("names: expected Int\n"); return 4; }
                        if expect_char(srcs, sts, 110, n) == 0 { write("names: expected Int\n"); return 4; }
                        if expect_char(srcs, sts, 116, n) == 0 { write("names: expected Int\n"); return 4; }
                        pe = 8;
                    }
                    if expect_char(srcs, sts, 93, n) == 0 { write("names: expected ]\n"); return 4; }
                } else {
                    write("names: unsupported param type\n"); return 4;
                }
                fpelem[pc] = pe;
                pc = pc + 1;
                skip(srcs, sts, n);
                if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                else if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                else { write("names: bad params\n"); return 4; }
            }
            if expect_char(srcs, sts, 45, n) == 0 { write("slice: expected ->\n"); return 4; }
            if expect_char(srcs, sts, 62, n) == 0 { write("slice: expected ->\n"); return 4; }
            if expect_char(srcs, sts, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
            if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
            if expect_char(srcs, sts, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
            if expect_char(srcs, sts, 123, n) == 0 { write("slice: expected {\n"); return 4; }

            if nf >= 64 { write("slice: too many functions\n"); return 4; }
            fname[nf] = fnm;
            flabel[nf] = cs[0];
            cs[4] = nf;
            st[4] = nf;

            // param stores, Slice uses two consecutive registers
            let reg = 0;
            i = 0;
            while i < pc {
                let pid = fparams[i];
                let pe = fpelem[i];
                if pe == 0 {
                    let vi = var_find(ps, pid, nf);
                    let off = 0;
                    if vi >= 0 { off = ps[9003 + vi * 4]; }
                    else {
                        off = dlen;
                        dlen = dlen + 8;
                        var_add(ps, pid, nf, off);
                    }
                    if reg == 0 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 61); }
                    else if reg == 1 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 53); }
                    else if reg == 2 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 21); }
                    else if reg == 3 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 13); }
                    else if reg == 4 { emit1(c, css, 76); emit1(c, css, 137); emit1(c, css, 5); }
                    else { emit1(c, css, 76); emit1(c, css, 137); emit1(c, css, 13); }
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = off;
                    cs[2] = cs[2] + 1;
                    emit4(c, css, 0);
                    reg = reg + 1;
                } else {
                    let soff = dlen;
                    dlen = dlen + 16;
                    add_sl(ps, pid, soff | (pe << 20) | (nf << 24));
                    let k = 0;
                    while k < 2 {
                        if reg == 0 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 61); }
                        else if reg == 1 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 53); }
                        else if reg == 2 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 21); }
                        else if reg == 3 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 13); }
                        else if reg == 4 { emit1(c, css, 76); emit1(c, css, 137); emit1(c, css, 5); }
                        else { emit1(c, css, 76); emit1(c, css, 137); emit1(c, css, 13); }
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff + k * 8;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                        reg = reg + 1;
                        k = k + 1;
                    }
                }
                i = i + 1;
            }

            let have_ret = 0;
            cd = 0;
            nbrk = 0;
            while 1 {
                skip(srcs, sts, n);
                if st[0] >= n { write("slice: eof in body\n"); return 4; }
                if srcs[st[0]] == 125 {
                    st[0] = st[0] + 1;
                    if cd == 0 { break; }
                    let kind = ck[cd - 1];
                    let finished = 0;
                    if kind == 1 {
                        skip(srcs, sts, n);
                        let is_else = st[0] + 4 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 115 && srcs[st[0] + 3] == 101;
                        if is_else {
                            st[0] = st[0] + 4;
                            skip(srcs, sts, n);
                            let is_eif = st[0] + 1 < n && srcs[st[0]] == 105 && srcs[st[0] + 1] == 102;
                            let jp = emit_jmp(c, css);
                            patch_jump(c, cje[cd - 1], cs[0]);
                            cd = cd - 1;
                            if is_eif {
                                if cd >= 64 { write("slice: too deep\n"); return 4; }
                                ck[cd] = 4; cjmp[cd] = jp; cd = cd + 1;
                            } else {
                                if cd >= 64 { write("slice: too deep\n"); return 4; }
                                ck[cd] = 2; cjmp[cd] = jp; cd = cd + 1;
                                if expect_char(srcs, sts, 123, n) == 0 { write("slice: expected {\n"); return 4; }
                            }
                        } else {
                            patch_jump(c, cje[cd - 1], cs[0]);
                            cd = cd - 1;
                            finished = 1;
                        }
                    } else if kind == 2 {
                        patch_jump(c, cjmp[cd - 1], cs[0]);
                        cd = cd - 1;
                        finished = 1;
                    } else if kind == 3 {
                        let jp = emit_jmp(c, css);
                        patch_jump(c, jp, cstart[cd - 1]);
                        patch_jump(c, cje[cd - 1], cs[0]);
                        let k = 0;
                        while k < nbrk {
                            if bloop[k] == cd - 1 { patch_jump(c, bpos[k], cs[0]); }
                            k = k + 1;
                        }
                        cd = cd - 1;
                    } else {
                        patch_jump(c, cjmp[cd - 1], cs[0]);
                        cd = cd - 1;
                        finished = 1;
                    }
                    if finished == 1 {
                        while cd > 0 && ck[cd - 1] == 4 {
                            patch_jump(c, cjmp[cd - 1], cs[0]);
                            cd = cd - 1;
                        }
                    }
                    continue;
                }
                if srcs[st[0]] == 114 && st[0] + 1 < n && srcs[st[0] + 1] == 101 {
                    if expect_char(srcs, sts, 114, n) == 0 { write("slice: bad return\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("slice: bad return\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("slice: bad return\n"); return 4; }
                    if expect_char(srcs, sts, 117, n) == 0 { write("slice: bad return\n"); return 4; }
                    if expect_char(srcs, sts, 114, n) == 0 { write("slice: bad return\n"); return 4; }
                    if expect_char(srcs, sts, 110, n) == 0 { write("slice: bad return\n"); return 4; }
                    st[2] = 0;
                    parse_expr(srcs, sts, ps);
                    if st[3] != 0 { write("slice: bad expr\n"); return 4; }
                    if expect_char(srcs, sts, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, css, ps);
                    emit1(c, css, 195);
                    have_ret = 1;
                } else if srcs[st[0]] == 105 && st[0] + 1 < n && srcs[st[0] + 1] == 102 {
                    if expect_char(srcs, sts, 105, n) == 0 { write("ctl: bad if\n"); return 4; }
                    if expect_char(srcs, sts, 102, n) == 0 { write("ctl: bad if\n"); return 4; }
                    st[2] = 0;
                    parse_expr(srcs, sts, ps);
                    if st[3] != 0 { write("ctl: bad if expr\n"); return 4; }
                    if expect_char(srcs, sts, 123, n) == 0 { write("ctl: expected {\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, css, ps);
                    emit1(c, css, 72); emit1(c, css, 133); emit1(c, css, 192);
                    let jp = emit_je(c, css);
                    if cd >= 64 { write("ctl: too deep\n"); return 4; }
                    ck[cd] = 1; cje[cd] = jp; cd = cd + 1;
                } else if srcs[st[0]] == 119 && st[0] + 1 < n && srcs[st[0] + 1] == 104 {
                    if expect_char(srcs, sts, 119, n) == 0 { write("ctl: bad while\n"); return 4; }
                    if expect_char(srcs, sts, 104, n) == 0 { write("ctl: bad while\n"); return 4; }
                    if expect_char(srcs, sts, 105, n) == 0 { write("ctl: bad while\n"); return 4; }
                    if expect_char(srcs, sts, 108, n) == 0 { write("ctl: bad while\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("ctl: bad while\n"); return 4; }
                    let wstart = cs[0];
                    st[2] = 0;
                    parse_expr(srcs, sts, ps);
                    if st[3] != 0 { write("ctl: bad while expr\n"); return 4; }
                    if expect_char(srcs, sts, 123, n) == 0 { write("ctl: expected {\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, css, ps);
                    emit1(c, css, 72); emit1(c, css, 133); emit1(c, css, 192);
                    let jp = emit_je(c, css);
                    if cd >= 64 { write("ctl: too deep\n"); return 4; }
                    ck[cd] = 3; cstart[cd] = wstart; cje[cd] = jp; cd = cd + 1;
                } else if srcs[st[0]] == 98 && st[0] + 1 < n && srcs[st[0] + 1] == 114 {
                    if expect_char(srcs, sts, 98, n) == 0 { write("ctl: bad break\n"); return 4; }
                    if expect_char(srcs, sts, 114, n) == 0 { write("ctl: bad break\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("ctl: bad break\n"); return 4; }
                    if expect_char(srcs, sts, 97, n) == 0 { write("ctl: bad break\n"); return 4; }
                    if expect_char(srcs, sts, 107, n) == 0 { write("ctl: bad break\n"); return 4; }
                    if expect_char(srcs, sts, 59, n) == 0 { write("ctl: expected ;\n"); return 4; }
                    let li = cd - 1;
                    while li >= 0 && ck[li] != 3 { li = li - 1; }
                    if li < 0 { write("ctl: break outside loop\n"); return 4; }
                    let jp = emit_jmp(c, css);
                    if nbrk >= 64 { write("ctl: too many breaks\n"); return 4; }
                    bpos[nbrk] = jp; bloop[nbrk] = li; nbrk = nbrk + 1;
                } else if srcs[st[0]] == 99 && st[0] + 7 < n && srcs[st[0] + 1] == 111 && srcs[st[0] + 2] == 110 && srcs[st[0] + 3] == 116 && srcs[st[0] + 4] == 105 && srcs[st[0] + 5] == 110 && srcs[st[0] + 6] == 117 && srcs[st[0] + 7] == 101 {
                    if expect_char(srcs, sts, 99, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 111, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 110, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 105, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 110, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 117, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("ctl: bad continue\n"); return 4; }
                    if expect_char(srcs, sts, 59, n) == 0 { write("ctl: expected ;\n"); return 4; }
                    let li = cd - 1;
                    while li >= 0 && ck[li] != 3 { li = li - 1; }
                    if li < 0 { write("ctl: continue outside loop\n"); return 4; }
                    let jp = emit_jmp(c, css);
                    patch_jump(c, jp, cstart[li]);
                } else if srcs[st[0]] == 119 && st[0] + 1 < n && srcs[st[0] + 1] == 114 {
                    if expect_char(srcs, sts, 119, n) == 0 { write("io: bad write\n"); return 4; }
                    if expect_char(srcs, sts, 114, n) == 0 { write("io: bad write\n"); return 4; }
                    if expect_char(srcs, sts, 105, n) == 0 { write("io: bad write\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("io: bad write\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("io: bad write\n"); return 4; }
                    if expect_char(srcs, sts, 40, n) == 0 { write("io: expected (\n"); return 4; }
                    if expect_char(srcs, sts, 34, n) == 0 { write("io: expected string\n"); return 4; }
                    let soff = litlen;
                    let ssz = 0;
                    while st[0] < n && srcs[st[0]] != 34 {
                        let cc = srcs[st[0]];
                        if cc == 92 && st[0] + 1 < n {
                            st[0] = st[0] + 1;
                            cc = srcs[st[0]];
                            if cc == 110 { cc = 10; }
                            else if cc == 116 { cc = 9; }
                        }
                        data[litlen] = cc;
                        litlen = litlen + 1;
                        ssz = ssz + 1;
                        st[0] = st[0] + 1;
                    }
                    if expect_char(srcs, sts, 34, n) == 0 { write("io: bad string\n"); return 4; }
                    if expect_char(srcs, sts, 41, n) == 0 { write("io: expected )\n"); return 4; }
                    if expect_char(srcs, sts, 59, n) == 0 { write("io: expected ;\n"); return 4; }
                    emit1(c, css, 184); emit4(c, css, 1);
                    emit1(c, css, 191); emit4(c, css, 1);
                    emit1(c, css, 72); emit1(c, css, 141); emit1(c, css, 53);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff;
                    cs[2] = cs[2] + 1;
                    emit4(c, css, 0);
                    emit1(c, css, 186); emit4(c, css, ssz);
                    emit1(c, css, 15); emit1(c, css, 5);
                } else if srcs[st[0]] == 108 && st[0] + 2 < n && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 116 {
                    if expect_char(srcs, sts, 108, n) == 0 { write("slice: bad let\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("slice: bad let\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("slice: bad let\n"); return 4; }
                    skip(srcs, sts, n);
                    let vnm = name_id(srcs, sts, ps);
                    if st[5] == 0 { write("slice: bad let name\n"); return 4; }
                    skip(srcs, sts, n);
                    if st[0] >= n || srcs[st[0]] != 58 {
                        // untyped let: let c = Enum.Variant; (stored as an Int slot)
                        if expect_char(srcs, sts, 61, n) == 0 { write("struct: expected =\n"); return 4; }
                        st[2] = 0;
                        parse_expr(srcs, sts, ps);
                        if st[3] != 0 { write("struct: bad let expr\n"); return 4; }
                        if expect_char(srcs, sts, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, css, ps);
                        emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        let vi = var_find(ps, vnm, nf);
                        let voff = 0;
                        if vi >= 0 { voff = ps[9003 + vi * 4]; }
                        else { voff = dlen; dlen = dlen + 8; var_add(ps, vnm, nf, voff); }
                        ps[cs[3] + cs[2] * 2 + 1] = voff;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                    } else {
                    if expect_char(srcs, sts, 58, n) == 0 { write("slice: expected :\n"); return 4; }
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 65 {
                        if expect_char(srcs, sts, 65, n) == 0 { write("slice: expected Array\n"); return 4; }
                        if expect_char(srcs, sts, 114, n) == 0 { write("slice: expected Array\n"); return 4; }
                        if expect_char(srcs, sts, 114, n) == 0 { write("slice: expected Array\n"); return 4; }
                        if expect_char(srcs, sts, 97, n) == 0 { write("slice: expected Array\n"); return 4; }
                        if expect_char(srcs, sts, 121, n) == 0 { write("slice: expected Array\n"); return 4; }
                        if expect_char(srcs, sts, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                        skip(srcs, sts, n);
                        let elem = 0;
                        if st[0] < n && srcs[st[0]] == 85 {
                            if expect_char(srcs, sts, 85, n) == 0 { write("slice: expected U8\n"); return 4; }
                            if expect_char(srcs, sts, 56, n) == 0 { write("slice: expected U8\n"); return 4; }
                            elem = 1;
                        } else {
                            if expect_char(srcs, sts, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                            if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                            if expect_char(srcs, sts, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
                            elem = 8;
                        }
                        if expect_char(srcs, sts, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                        skip(srcs, sts, n);
                        let cnt = 0;
                        while st[0] < n && srcs[st[0]] >= 48 && srcs[st[0]] <= 57 {
                            cnt = cnt * 10 + (srcs[st[0]] - 48);
                            st[0] = st[0] + 1;
                        }
                        if expect_char(srcs, sts, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                        if expect_char(srcs, sts, 61, n) == 0 { write("slice: expected =\n"); return 4; }
                        if expect_char(srcs, sts, 65, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 114, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 114, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 97, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 121, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 46, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 122, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 101, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 114, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 111, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 101, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 100, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                        if expect_char(srcs, sts, 40, n) == 0 { write("slice: expected (\n"); return 4; }
                        if expect_char(srcs, sts, 41, n) == 0 { write("slice: expected )\n"); return 4; }
                        if expect_char(srcs, sts, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                        let aoff = dlen;
                        dlen = dlen + elem * cnt;
                        add_arr(ps, vnm, aoff | (elem << 20) | (nf << 24) | (cnt << 32));
                    } else if st[0] < n && srcs[st[0]] == 83 {
                        if expect_char(srcs, sts, 83, n) == 0 { write("slice: expected Slice\n"); return 4; }
                        if expect_char(srcs, sts, 108, n) == 0 { write("slice: expected Slice\n"); return 4; }
                        if expect_char(srcs, sts, 105, n) == 0 { write("slice: expected Slice\n"); return 4; }
                        if expect_char(srcs, sts, 99, n) == 0 { write("slice: expected Slice\n"); return 4; }
                        if expect_char(srcs, sts, 101, n) == 0 { write("slice: expected Slice\n"); return 4; }
                        if expect_char(srcs, sts, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                        skip(srcs, sts, n);
                        let elem = 0;
                        if st[0] < n && srcs[st[0]] == 85 {
                            if expect_char(srcs, sts, 85, n) == 0 { write("slice: expected U8\n"); return 4; }
                            if expect_char(srcs, sts, 56, n) == 0 { write("slice: expected U8\n"); return 4; }
                            elem = 1;
                        } else {
                            if expect_char(srcs, sts, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                            if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                            if expect_char(srcs, sts, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
                            elem = 8;
                        }
                        if expect_char(srcs, sts, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                        if expect_char(srcs, sts, 61, n) == 0 { write("slice: expected =\n"); return 4; }
                        if expect_char(srcs, sts, 115, n) == 0 { write("slice: expected slice\n"); return 4; }
                        if expect_char(srcs, sts, 108, n) == 0 { write("slice: expected slice\n"); return 4; }
                        if expect_char(srcs, sts, 105, n) == 0 { write("slice: expected slice\n"); return 4; }
                        if expect_char(srcs, sts, 99, n) == 0 { write("slice: expected slice\n"); return 4; }
                        if expect_char(srcs, sts, 101, n) == 0 { write("slice: expected slice\n"); return 4; }
                        if expect_char(srcs, sts, 40, n) == 0 { write("slice: expected (\n"); return 4; }
                        skip(srcs, sts, n);
                        let anm = name_id(srcs, sts, ps);
                        if st[5] == 0 { write("slice: bad array name\n"); return 4; }
                        if expect_char(srcs, sts, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                        let ai = arr_find(ps, anm, nf);
                        if ai < 0 { write("slice: unknown array\n"); return 4; }
                        let ameta = ps[4098 + ai * 2];
                        let aoff = ameta & 1048575;
                        let soff = dlen;
                        dlen = dlen + 16;
                        add_sl(ps, vnm, soff | (elem << 20) | (nf << 24));
                        st[2] = 0;
                        parse_expr(srcs, sts, ps);
                        if st[3] != 0 { write("slice: bad slice start\n"); return 4; }
                        if expect_char(srcs, sts, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, css, ps);
                        emit1(c, css, 80); // start
                        emit1(c, css, 72); emit1(c, css, 141); emit1(c, css, 21);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = aoff;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                        emit1(c, css, 88); // start -> rax
                        emit1(c, css, 72); emit1(c, css, 1); emit1(c, css, 208); // add rax,rdx
                        emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                        st[2] = 0;
                        parse_expr(srcs, sts, ps);
                        if st[3] != 0 { write("slice: bad slice len\n"); return 4; }
                        if expect_char(srcs, sts, 41, n) == 0 { write("slice: expected )\n"); return 4; }
                        if expect_char(srcs, sts, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, css, ps);
                        emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff + 8;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                    } else {
                        let tnm = name_id(srcs, sts, ps);
                        if st[5] == 0 { write("struct: bad type\n"); return 4; }
                        let si = st_find(ps, tnm);
                        if si < 0 { write("struct: unknown type\n"); return 4; }
                        let sz = st_size(ps, si);
                        let soff = dlen;
                        dlen = dlen + sz;
                        sv_add(ps, vnm, nf, soff, si);
                        if expect_char(srcs, sts, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
                    }
                    }
                } else if srcs[st[0]] == 109 && st[0] + 1 < n && srcs[st[0] + 1] == 97 {
                    // match (tag-only); each arm is `Variant => { return expr; }`
                    if expect_char(srcs, sts, 109, n) == 0 { write("match: bad keyword\n"); return 4; }
                    if expect_char(srcs, sts, 97, n) == 0 { write("match: bad keyword\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("match: bad keyword\n"); return 4; }
                    if expect_char(srcs, sts, 99, n) == 0 { write("match: bad keyword\n"); return 4; }
                    if expect_char(srcs, sts, 104, n) == 0 { write("match: bad keyword\n"); return 4; }
                    skip(srcs, sts, n);
                    let mnm = name_id(srcs, sts, ps);
                    if st[5] == 0 { write("match: bad subject\n"); return 4; }
                    let mvi = var_find(ps, mnm, nf);
                    if mvi < 0 { write("match: unknown subject\n"); return 4; }
                    let moff = ps[9003 + mvi * 4];
                    if expect_char(srcs, sts, 123, n) == 0 { write("match: expected {\n"); return 4; }
                    while 1 {
                        skip(srcs, sts, n);
                        if st[0] < n && srcs[st[0]] == 125 { break; }
                        let enm = name_id(srcs, sts, ps);
                        if st[5] == 0 { write("match: bad enum\n"); return 4; }
                        if expect_char(srcs, sts, 46, n) == 0 { write("match: expected .\n"); return 4; }
                        let vn = name_id(srcs, sts, ps);
                        if st[5] == 0 { write("match: bad variant\n"); return 4; }
                        let ei = en_find(ps, enm);
                        if ei < 0 { write("match: unknown enum\n"); return 4; }
                        let tag = en_var_find(ps, ei, vn);
                        if tag < 0 { write("match: unknown variant\n"); return 4; }
                        if expect_char(srcs, sts, 61, n) == 0 { write("match: expected =>\n"); return 4; }
                        if expect_char(srcs, sts, 62, n) == 0 { write("match: expected =>\n"); return 4; }
                        if expect_char(srcs, sts, 123, n) == 0 { write("match: expected {\n"); return 4; }
                        if expect_char(srcs, sts, 114, n) == 0 { write("match: expected return\n"); return 4; }
                        if expect_char(srcs, sts, 101, n) == 0 { write("match: expected return\n"); return 4; }
                        if expect_char(srcs, sts, 116, n) == 0 { write("match: expected return\n"); return 4; }
                        if expect_char(srcs, sts, 117, n) == 0 { write("match: expected return\n"); return 4; }
                        if expect_char(srcs, sts, 114, n) == 0 { write("match: expected return\n"); return 4; }
                        if expect_char(srcs, sts, 110, n) == 0 { write("match: expected return\n"); return 4; }
                        st[2] = 0;
                        parse_expr(srcs, sts, ps);
                        if st[3] != 0 { write("match: bad expr\n"); return 4; }
                        if expect_char(srcs, sts, 59, n) == 0 { write("match: expected ;\n"); return 4; }
                        if expect_char(srcs, sts, 125, n) == 0 { write("match: expected }\n"); return 4; }
                        emit1(c, css, 72); emit1(c, css, 139); emit1(c, css, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = moff;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                        emit1(c, css, 72); emit1(c, css, 61); emit4(c, css, tag);
                        emit1(c, css, 15); emit1(c, css, 133);
                        let jp = cs[0];
                        emit4(c, css, 0);
                        cs[1] = st[2];
                        emit_expr(c, css, ps);
                        emit1(c, css, 195);
                        put32(c, jp, cs[0] - (jp + 4));
                        skip(srcs, sts, n);
                        if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                    }
                    if expect_char(srcs, sts, 125, n) == 0 { write("match: expected }\n"); return 4; }
                } else {
                    let nstart = st[0];
                    let vnm = name_id(srcs, sts, ps);
                    if st[5] == 0 { write("slice: bad statement\n"); return 4; }
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 40 {
                        st[0] = nstart;
                        st[2] = 0;
                        parse_expr(srcs, sts, ps);
                        if st[3] != 0 { write("slice: bad expr statement\n"); return 4; }
                        if expect_char(srcs, sts, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, css, ps);
                    } else if st[0] < n && srcs[st[0]] == 91 {
                    st[0] = st[0] + 1;
                    st[2] = 0;
                    parse_index(srcs, sts, ps);
                    if st[3] != 0 { write("slice: bad index\n"); return 4; }
                    if expect_char(srcs, sts, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                    if expect_char(srcs, sts, 61, n) == 0 { write("slice: expected =\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, css, ps);
                    emit1(c, css, 80); // index
                    st[2] = 0;
                    parse_expr(srcs, sts, ps);
                    if st[3] != 0 { write("slice: bad value\n"); return 4; }
                    if expect_char(srcs, sts, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, css, ps);
                    emit1(c, css, 89); // pop rcx = index
                    let ai = arr_find(ps, vnm, nf);
                    if ai >= 0 {
                        let meta = ps[4098 + ai * 2];
                        let off = meta & 1048575;
                        let elem = (meta >> 20) & 15;
                        emit1(c, css, 72); emit1(c, css, 141); emit1(c, css, 21);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = off;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                        if elem == 8 {
                            emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 4); emit1(c, css, 202);
                        } else {
                            emit1(c, css, 72); emit1(c, css, 1); emit1(c, css, 209);
                            emit1(c, css, 136); emit1(c, css, 1);
                        }
                    } else {
                        let si = sl_find(ps, vnm, nf);
                        if si < 0 { write("slice: unknown index target\n"); return 4; }
                        let meta = ps[4610 + si * 2];
                        let off = meta & 1048575;
                        let elem = (meta >> 20) & 15;
                        emit1(c, css, 72); emit1(c, css, 139); emit1(c, css, 21);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = off;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                        if elem == 8 {
                            emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 4); emit1(c, css, 202);
                        } else {
                            emit1(c, css, 72); emit1(c, css, 1); emit1(c, css, 209);
                            emit1(c, css, 136); emit1(c, css, 1);
                        }
                    }
                    } else if st[0] < n && srcs[st[0]] == 46 {
                        st[0] = st[0] + 1;
                        skip(srcs, sts, n);
                        let fld = name_id(srcs, sts, ps);
                        if st[5] == 0 { write("struct: bad field\n"); return 4; }
                        let svi = sv_find(ps, vnm, nf);
                        if svi < 0 { write("struct: unknown variable\n"); return 4; }
                        let sidx = ps[6404 + svi * 4];
                        let fi = st_field_find(ps, sidx, fld);
                        if fi < 0 { write("struct: unknown field\n"); return 4; }
                        let fb = 5121 + sidx * 18;
                        let fmeta = ps[fb + 3 + fi * 2];
                        let off = ps[6403 + svi * 4] + (fmeta & 1048575);
                        let elem = (fmeta >> 20) & 15;
                        if expect_char(srcs, sts, 61, n) == 0 { write("struct: expected =\n"); return 4; }
                        st[2] = 0;
                        parse_expr(srcs, sts, ps);
                        if st[3] != 0 { write("struct: bad field value\n"); return 4; }
                        if expect_char(srcs, sts, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, css, ps);
                        if elem == 8 { emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5); }
                        else { emit1(c, css, 136); emit1(c, css, 5); }
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = off;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                    } else {
                        if expect_char(srcs, sts, 61, n) == 0 { write("assign: expected =\n"); return 4; }
                        st[2] = 0;
                        parse_expr(srcs, sts, ps);
                        if st[3] != 0 { write("assign: bad expr\n"); return 4; }
                        if expect_char(srcs, sts, 59, n) == 0 { write("assign: expected ;\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, css, ps);
                        emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        let vi = var_find(ps, vnm, nf);
                        let voff = 0;
                        if vi >= 0 { voff = ps[9003 + vi * 4]; }
                        else { voff = dlen; dlen = dlen + 8; var_add(ps, vnm, nf, voff); }
                        ps[cs[3] + cs[2] * 2 + 1] = voff;
                        cs[2] = cs[2] + 1;
                        emit4(c, css, 0);
                    }
                }
            }
            if have_ret == 0 {
                emit1(c, css, 72); emit1(c, css, 49); emit1(c, css, 192);
                emit1(c, css, 195);
            }
            nf = nf + 1;
            }
        }
    }

    // resolve call patches
    i = 0;
    while i < cs[5] {
        let pos = ps[cs[6] + i * 2];
        let nm = ps[cs[6] + i * 2 + 1];
        let fi = 0;
        let found = 0;
        while fi < nf {
            if fname[fi] == nm { found = 1; break; }
            fi = fi + 1;
        }
        if found == 0 { write("slice: unknown function\n"); return 4; }
        put32(c, pos, flabel[fi] - (pos + 4));
        i = i + 1;
    }

    // find main and emit trampoline at the end
    let main_i = 0;
    let main_found = 0;
    i = 0;
    while i < nf {
        if fname[i] == main_nid { main_found = 1; main_i = i; }
        i = i + 1;
    }
    if main_found == 0 { write("slice: missing main\n"); return 4; }
    let entry_off = cs[0];
    // Save argc/argv before calling main.
    emit1(c, css, 72); emit1(c, css, 139); emit1(c, css, 4); emit1(c, css, 36); // rax=[rsp]
    emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = cs[7];
    cs[2] = cs[2] + 1;
    emit4(c, css, 0);
    emit1(c, css, 72); emit1(c, css, 141); emit1(c, css, 68); emit1(c, css, 36); emit1(c, css, 8); // lea rax,[rsp+8]
    emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = cs[7] + 8;
    cs[2] = cs[2] + 1;
    emit4(c, css, 0);
    emit1(c, css, 232);
    let callpos = cs[0];
    emit4(c, css, flabel[main_i] - (callpos + 4));
    emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 199);
    emit1(c, css, 184); emit4(c, css, 60);
    emit1(c, css, 15); emit1(c, css, 5);

    let clen = cs[0];
    let code_vaddr = 4194424;
    let data_vaddr = code_vaddr + clen;
    i = 0;
    while i < cs[2] {
        let pos = ps[cs[3] + i * 2];
        let off = ps[cs[3] + i * 2 + 1];
        put32(c, pos, data_vaddr + off - (code_vaddr + pos + 4));
        i = i + 1;
    }
    let total = 120 + clen + dlen;
    let filetotal = 120 + clen + litlen;
    let o: Slice[U8] = slice(out, 0, 262144);
    o[0] = 127; o[1] = 69; o[2] = 76; o[3] = 70;
    o[4] = 2; o[5] = 1; o[6] = 1;
    put16(o, 16, 2); put16(o, 18, 62); put32(o, 20, 1);
    put64(o, 24, code_vaddr + entry_off); put64(o, 32, 64); put64(o, 40, 0);
    put32(o, 48, 0); put16(o, 52, 64); put16(o, 54, 56);
    put16(o, 56, 1); put16(o, 58, 0); put16(o, 60, 0); put16(o, 62, 0);
    put32(o, 64, 1); put32(o, 68, 7); put64(o, 72, 0);
    put64(o, 80, 4194304); put64(o, 88, 4194304);
    put64(o, 96, filetotal); put64(o, 104, total); put64(o, 112, 4096);
    let dst_code: Slice[U8] = slice(out, 120, clen);
    let src_code: Slice[U8] = slice(code, 0, clen);
    copy(dst_code, src_code, clen);
    let dst_data: Slice[U8] = slice(out, 120 + clen, litlen);
    let src_data: Slice[U8] = slice(data, 0, litlen);
    copy(dst_data, src_data, litlen);
    if write_file(oup, out, filetotal) != 0 { write("slice: write failed\n"); return 5; }
    write("slice ok\n");
    return 0;
}
