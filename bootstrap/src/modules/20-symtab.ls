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

    let cnt = post[16000];
    let i = 0;
    while i < cnt {
        let eb = 16002 + i * 2;
        if post[eb + 1] == slen {
            let off = post[eb];
            let same = 1;
            let j = 0;
            while j < slen {
                let idx = off + j;
                let w = post[18000 + idx / 8];
                let ch = (w >> ((idx % 8) * 8)) & 255;
                if ch != src[start + j] { same = 0; break; }
                j = j + 1;
            }
            if same == 1 { return i; }
        }
        i = i + 1;
    }

    let used = post[16001];
    let eb = 16002 + cnt * 2;
    post[eb] = used;
    post[eb + 1] = slen;
    let j = 0;
    while j < slen {
        let idx = used + j;
        post[18000 + idx / 8] = post[18000 + idx / 8] | (src[start + j] << ((idx % 8) * 8));
        j = j + 1;
    }
    post[16000] = cnt + 1;
    post[16001] = used + slen;
    return cnt;
}

// Builtin name -> code: 1 argc, 2 arg_len, 3 arg_byte, 4 read_file, 5 write_file.
fn builtin_code(src: Slice[U8], start: Int, len: Int) -> Int {
    if len == 4 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 103 && src[start + 3] == 99 { return 1; }
    if len == 7 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 103 && src[start + 3] == 95 && src[start + 4] == 108 && src[start + 5] == 101 && src[start + 6] == 110 { return 2; }
    if len == 8 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 103 && src[start + 3] == 95 && src[start + 4] == 98 && src[start + 5] == 121 && src[start + 6] == 116 && src[start + 7] == 101 { return 3; }
    if len == 9 && src[start] == 114 && src[start + 1] == 101 && src[start + 2] == 97 && src[start + 3] == 100 && src[start + 4] == 95 && src[start + 5] == 102 && src[start + 6] == 105 && src[start + 7] == 108 && src[start + 8] == 101 { return 4; }
    if len == 10 && src[start] == 119 && src[start + 1] == 114 && src[start + 2] == 105 && src[start + 3] == 116 && src[start + 4] == 101 && src[start + 5] == 95 && src[start + 6] == 102 && src[start + 7] == 105 && src[start + 8] == 108 && src[start + 9] == 101 { return 5; }
    if len == 11 && src[start] == 99 && src[start + 1] == 111 && src[start + 2] == 110 && src[start + 3] == 99 && src[start + 4] == 97 && src[start + 5] == 116 && src[start + 6] == 95 && src[start + 7] == 105 && src[start + 8] == 110 && src[start + 9] == 116 && src[start + 10] == 111 { return 6; }
    if len == 11 && src[start] == 97 && src[start + 1] == 112 && src[start + 2] == 112 && src[start + 3] == 101 && src[start + 4] == 110 && src[start + 5] == 100 && src[start + 6] == 95 && src[start + 7] == 105 && src[start + 8] == 110 && src[start + 9] == 116 && src[start + 10] == 111 { return 7; }
    if len == 11 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 114 && src[start + 7] == 101 && src[start + 8] == 115 && src[start + 9] == 101 && src[start + 10] == 116 { return 8; }
    if len == 11 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 97 && src[start + 7] == 108 && src[start + 8] == 108 && src[start + 9] == 111 && src[start + 10] == 99 { return 9; }
    if len == 10 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 117 && src[start + 7] == 115 && src[start + 8] == 101 && src[start + 9] == 100 { return 10; }
    if len == 12 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 98 && src[start + 7] == 117 && src[start + 8] == 100 && src[start + 9] == 103 && src[start + 10] == 101 && src[start + 11] == 116 { return 11; }
    if len == 10 && src[start] == 98 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 && src[start + 6] == 95 && src[start + 7] == 110 && src[start + 8] == 101 && src[start + 9] == 119 { return 12; }
    if len == 10 && src[start] == 98 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 && src[start + 6] == 95 && src[start + 7] == 108 && src[start + 8] == 101 && src[start + 9] == 110 { return 13; }
    if len == 10 && src[start] == 98 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 && src[start + 6] == 95 && src[start + 7] == 99 && src[start + 8] == 97 && src[start + 9] == 112 { return 14; }
    if len == 11 && src[start] == 98 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 && src[start + 6] == 95 && src[start + 7] == 112 && src[start + 8] == 117 && src[start + 9] == 115 && src[start + 10] == 104 { return 15; }
    if len == 10 && src[start] == 98 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 && src[start + 6] == 95 && src[start + 7] == 103 && src[start + 8] == 101 && src[start + 9] == 116 { return 16; }
    if len == 14 && src[start] == 115 && src[start + 1] == 116 && src[start + 2] == 114 && src[start + 3] == 95 && src[start + 4] == 116 && src[start + 5] == 114 && src[start + 6] == 121 && src[start + 7] == 95 && src[start + 8] == 99 && src[start + 9] == 111 && src[start + 10] == 110 && src[start + 11] == 99 && src[start + 12] == 97 && src[start + 13] == 116 { return 17; }
    if len == 10 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 115 && src[start + 7] == 116 && src[start + 8] == 97 && src[start + 9] == 116 { return 18; }
    if len == 11 && src[start] == 114 && src[start + 1] == 101 && src[start + 2] == 103 && src[start + 3] == 105 && src[start + 4] == 111 && src[start + 5] == 110 && src[start + 6] == 95 && src[start + 7] == 117 && src[start + 8] == 115 && src[start + 9] == 101 && src[start + 10] == 100 { return 19; }
    if len == 10 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 109 && src[start + 7] == 97 && src[start + 8] == 114 && src[start + 9] == 107 { return 20; }
    if len == 12 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 114 && src[start + 7] == 101 && src[start + 8] == 119 && src[start + 9] == 105 && src[start + 10] == 110 && src[start + 11] == 100 { return 21; }
    if len == 10 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 102 && src[start + 7] == 114 && src[start + 8] == 101 && src[start + 9] == 101 { return 22; }
    if len == 14 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 99 && src[start + 7] == 111 && src[start + 8] == 97 && src[start + 9] == 108 && src[start + 10] == 101 && src[start + 11] == 115 && src[start + 12] == 99 && src[start + 13] == 101 { return 23; }
    // R4.7: region_limit() and arena_compact().
    if len == 12 && src[start] == 114 && src[start + 1] == 101 && src[start + 2] == 103 && src[start + 3] == 105 && src[start + 4] == 111 && src[start + 5] == 110 && src[start + 6] == 95 && src[start + 7] == 108 && src[start + 8] == 105 && src[start + 9] == 109 && src[start + 10] == 105 && src[start + 11] == 116 { return 24; }
    if len == 13 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 && src[start + 6] == 99 && src[start + 7] == 111 && src[start + 8] == 109 && src[start + 9] == 112 && src[start + 10] == 97 && src[start + 11] == 99 && src[start + 12] == 116 { return 25; }
    return 0;
}

// Int variable table: [50000] count, entry i at 50001 + i*4 { name, fn, off, meta }
// meta layout:
//   bits 0..7    type (1 Int, 2 U8, 3 Str, 4 Slice[U8], 5 Slice[Int], 100 generic T)
//   bit 8        val (immutable binding)
//   bits 10..29  declaration position (dpos)
//   bits 30..49  scope end (send)
// `var_find` chooses the visible declaration with the largest dpos, so later
// `let` declarations shadow earlier ones without changing slot layout.
fn var_find(post: Slice[Int], nm: Int, fnidx: Int, pos: Int) -> Int {
    let cnt = post[50000];
    let best = 0 - 1;
    let best_dpos = 0 - 1;
    let i = 0;
    while i < cnt {
        if post[50001 + i * 4] == nm && post[50002 + i * 4] == fnidx {
            let meta = post[50004 + i * 4];
            let dpos = (meta >> 10) & 1048575;
            let send = (meta >> 30) & 1048575;
            if dpos <= pos && pos < send && dpos >= best_dpos {
                best = i;
                best_dpos = dpos;
            }
        }
        i = i + 1;
    }
    return best;
}

fn var_find_any(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[50000];
    let i = 0;
    while i < cnt {
        if post[50001 + i * 4] == nm && post[50002 + i * 4] == fnidx { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn var_add(post: Slice[Int], nm: Int, fnidx: Int, off: Int, span: Int) -> Int {
    let c = post[50000];
    post[50001 + c * 4] = nm;
    post[50002 + c * 4] = fnidx;
    post[50003 + c * 4] = off;
    post[50004 + c * 4] = span;
    post[50000] = c + 1;
    return c;
}

fn var_is_buffer(post: Slice[Int], nm: Int, fnidx: Int, pos: Int) -> Int {
    let vi = var_find(post, nm, fnidx, pos);
    if vi >= 0 && ((post[50004 + vi * 4] & 255) == 9 || (post[50004 + vi * 4] & 255) == 15) { return 1; }
    return 0;
}

fn var_span(dpos: Int, send: Int, pval: Int) -> Int {
    return (dpos << 10) | (send << 30) | (pval << 8);
}

fn var_set_ty(post: Slice[Int], vi: Int, ty: Int) -> Int {
    let meta = post[50004 + vi * 4];
    post[50004 + vi * 4] = (meta - (meta & 255)) | ty;
    return 0;
}

// B5-8: lightweight lifetime/escape tracking for `ref` values.
//   post[136000 + vi] = (send << 1) | origin, where 0 means "unknown".
//   origin 0: reborrow of a `ref` parameter (outlives the callee);
//   origin 1: address of a local slot (dies at scope end `send`).
//   Unknown entries are treated as origin 1 / send 0, i.e. maximally local,
//   so a missing record can only cause a rejection, never a false accept.
//   post[135802] carries the lifetime of the ref returned by the call that is
//   currently being parsed (see parse_expr / make_ref_arg).
// Join one ref-argument lifetime into the pending call-result lifetime.
// A ref parameter (origin 0) contributes no upper bound.
fn rl_join(post: Slice[Int], life: Int) -> Int {
    // cur == 0 means "no ref argument seen yet", i.e. no upper bound.
    let cur = post[135802];
    let oc = cur & 1;
    let ol = life & 1;
    let sc = cur >> 1;
    let sl = life >> 1;
    if oc == 0 { sc = 1048575; }
    if ol == 0 { sl = 1048575; }
    if sl < sc { sc = sl; }
    post[135802] = (sc << 1) | (oc | ol);
    return 0;
}

// B5: load a Buffer handle; Ref Buffer (type 15) stores a pointer to the handle.
fn push_handle(post: Slice[Int], st: Slice[Int], vi: Int) -> Int {
    push_post(post, st, 1, vi);
    if (post[50004 + vi * 4] & 255) == 15 { push_post(post, st, 76, 0); }
    set_ty(post, st, 9);
    return 0;
}

// B5-9: when an enclosing payload expects a `ref` type (st[10]) and the
// variable itself has that ref type, read the pointer instead of dereferencing.
fn push_var_expect(post: Slice[Int], st: Slice[Int], vi: Int) -> Int {
    let want = st[10];
    if want >= 11 && want <= 15 {
        if (post[50004 + vi * 4] & 255) == want {
            push_post(post, st, 75, vi);
            set_ty(post, st, want);
            return 0;
        }
    }
    push_var(post, st, vi);
    return 0;
}

// B5-1: load a variable. Ref Int (type 11) stores a pointer; dereference it.
fn push_var(post: Slice[Int], st: Slice[Int], vi: Int) -> Int {
    let vty = post[50004 + vi * 4] & 255;
    if vty == 0 { vty = 1; }
    if vty == 11 {
        push_post(post, st, 1, vi);
        push_post(post, st, 76, 0);
        set_ty(post, st, 1);
    } else if vty == 12 {
        push_post(post, st, 77, vi);
        set_ty(post, st, 3);
    } else if vty == 13 {
        push_post(post, st, 78, vi);
        set_ty(post, st, 4);
    } else if vty == 14 {
        push_post(post, st, 78, vi);
        set_ty(post, st, 5);
    } else if vty == 15 {
        push_post(post, st, 1, vi);
        push_post(post, st, 76, 0);
        set_ty(post, st, 9);
    } else {
        push_post(post, st, 1, vi);
        set_ty(post, st, vty);
    }
    return 0;
}

// Metadata tables live in the high half of `post`:
//   [4096] array count, entries at 4097 + i*3 { name, meta, send }
//   [66400] slice count, entries at 66401 + i*2 { name, meta }
// meta: off (bits 0..30) | elem << 31 | fn << 35 (7 bits) | len << 42
// B5-9: `send` is the array's declaration scope end (used by escape checks).
fn arr_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[4096];
    let i = 0;
    while i < cnt {
        let meta = post[4098 + i * 3];
        if post[4097 + i * 3] == nm && ((meta >> 35) & 127) == fnidx {
            return i;
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn sl_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[66400];
    let i = 0;
    while i < cnt {
        let meta = post[66402 + i * 2];
        if post[66401 + i * 2] == nm && ((meta >> 35) & 127) == fnidx {
            return i;
        }
        i = i + 1;
    }
    return 0 - 1;
}

fn add_arr(post: Slice[Int], nm: Int, meta: Int, send: Int) -> Int {
    let c = post[4096];
    post[4097 + c * 3] = nm;
    post[4098 + c * 3] = meta;
    post[4099 + c * 3] = send;
    post[4096] = c + 1;
    return c;
}

fn add_sl(post: Slice[Int], nm: Int, meta: Int) -> Int {
    let c = post[66400];
    post[66401 + c * 2] = nm;
    post[66402 + c * 2] = meta;
    post[66400] = c + 1;
    return c;
}

// Str variable table: [15000] count, entry i at 15001 + i*4 { name, fn, off }
// Each Str slot is 24 bytes: base, byte_len, char_len.
fn str_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[15000];
    let i = 0;
    while i < cnt {
        if post[15001 + i * 4] == nm && post[15002 + i * 4] == fnidx { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn str_add(post: Slice[Int], nm: Int, fnidx: Int, off: Int) -> Int {
    let c = post[15000];
    post[15001 + c * 4] = nm;
    post[15002 + c * 4] = fnidx;
    post[15003 + c * 4] = off;
    post[15004 + c * 4] = 0;
    post[15000] = c + 1;
    return c;
}

