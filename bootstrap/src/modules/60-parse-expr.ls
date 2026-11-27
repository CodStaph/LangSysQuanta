fn parse_expr(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let cname: Array[Int, 32] = Array.zeroed();
    let cnargs: Array[Int, 32] = Array.zeroed();
    let cargs: Array[Int, 32] = Array.zeroed();
    let cargstart: Array[Int, 32] = Array.zeroed();
    let ctypes: Array[Int, 256] = Array.zeroed();
    let cref: Array[Int, 32] = Array.zeroed();
    let cdepth = 0;
    let top = 0;
    let paren = 0;
    let expect = 1;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 123 || c == 93 { break; }
        if c == 44 && cdepth == 0 { break; }
        if c == 41 && paren == 0 { break; }
        if c == 44 {
            while top > 0 && ops[top - 1] != 98 {
                if ops[top - 1] != 99 { st[8] = ops[top - 1]; push_binop(src, post, st); }
                top = top - 1;
            }
            let rfi = cref[cdepth - 1];
            let rm = 0;
            let rt = 0;
            let rai = cnargs[cdepth - 1];
            if rfi >= 0 {
                rm = post[130000 + rfi];
                if rai < 8 { rt = post[130600 + rfi * 8 + rai]; }
            }
            if (rm & (1 << rai)) != 0 {
                post[130700] = rt;
                let rr = make_ref_arg(post, st, cargstart[cdepth - 1], rai);
                if rr == 0 - 1 { write("ref argument must be a mutable Int variable\n"); st[3] = 1; return 0; }
                if rr == 0 - 2 { write("ref argument cannot be a val binding\n"); st[3] = 1; return 0; }
                if rr == 0 - 3 { write("ref arguments alias the same variable\n"); st[3] = 1; return 0; }
            }
            if (post[120000 + cname[cdepth - 1]] & 1073741824) != 0 {
                if st[2] > cargstart[cdepth - 1] { box_last_arg(post, st); }
                if cnargs[cdepth - 1] < 7 {
                    ctypes[(cdepth - 1) * 8 + cnargs[cdepth - 1]] = post[110000 + st[2] - 1];
                }
            }
            cnargs[cdepth - 1] = cnargs[cdepth - 1] + 1;
            let w = arg_width(post, cargstart[cdepth - 1], st[2]);
            cargs[cdepth - 1] = cargs[cdepth - 1] + w;
            cargstart[cdepth - 1] = st[2];
            st[0] = st[0] + 1;
            expect = 1;
        } else if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v); set_ty(post, st, 1);
            expect = 0;
        } else if c == 114 && st[0] + 6 <= n && post[135745] != 0 && src[st[0] + 1] == 101 && src[st[0] + 2] == 115 && src[st[0] + 3] == 117 && src[st[0] + 4] == 108 && src[st[0] + 5] == 116 && is_ident_byte(src[st[0] + 6]) == 0 {
            // B5-11: `result` inside an ensures clause.
            st[0] = st[0] + 6;
            push_post(post, st, 87, post[135746]);
            set_ty(post, st, 1);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nstart = st[0];
            let name = name_id(src, st, post);
            let bcode = builtin_code(src, nstart, st[5]);
            // B5-10: builtin effects feed the current function's produced set.
            if bcode == 1 || bcode == 2 || bcode == 3 || bcode == 4 || bcode == 5 { post[131960] = post[131960] | 8; }
            if bcode == 6 || bcode == 7 || bcode == 9 || bcode == 12 || bcode == 17 || bcode == 23 || bcode == 25 { post[131960] = post[131960] | 4; }
            if bcode == 15 { post[131960] = post[131960] | 2; }
            if bcode == 10 || bcode == 11 || bcode == 13 || bcode == 14 || bcode == 16 || bcode == 18 || bcode == 19 || bcode == 24 { post[131960] = post[131960] | 1; }
            if st[5] == 5 && src[nstart] == 69 && src[nstart + 1] == 114 && src[nstart + 2] == 114 && src[nstart + 3] == 111 && src[nstart + 4] == 114 && st[0] < n && src[st[0]] == 46 {
                // B5-12: `Error.Full` / `Error.NotFound` / `Error.InvalidCap` /
                // `Error.OutOfMemory` are compact tags of the built-in Error enum.
                st[0] = st[0] + 1;
                skip(src, st, n);
                let vstart = st[0];
                let vn = name_id(src, st, post);
                if st[5] == 0 { write("error: bad Error variant
"); st[3] = 1; return 0; }
                let etag = 0;
                if st[5] == 4 && src[vstart] == 70 && src[vstart + 1] == 117 && src[vstart + 2] == 108 && src[vstart + 3] == 108 { etag = 1; }
                else if st[5] == 8 && src[vstart] == 78 && src[vstart + 1] == 111 && src[vstart + 2] == 116 && src[vstart + 3] == 70 && src[vstart + 4] == 111 && src[vstart + 5] == 117 && src[vstart + 6] == 110 && src[vstart + 7] == 100 { etag = 2; }
                else if st[5] == 10 && src[vstart] == 73 && src[vstart + 1] == 110 && src[vstart + 2] == 118 && src[vstart + 3] == 97 && src[vstart + 4] == 108 && src[vstart + 5] == 105 && src[vstart + 6] == 100 && src[vstart + 7] == 67 && src[vstart + 8] == 97 && src[vstart + 9] == 112 { etag = 3; }
                else if st[5] == 11 && src[vstart] == 79 && src[vstart + 1] == 117 && src[vstart + 2] == 116 && src[vstart + 3] == 79 && src[vstart + 4] == 102 && src[vstart + 5] == 77 && src[vstart + 6] == 101 && src[vstart + 7] == 109 && src[vstart + 8] == 111 && src[vstart + 9] == 114 && src[vstart + 10] == 121 { etag = 4; }
                else { write("error: unknown Error variant
"); st[3] = 1; return 0; }
                push_post(post, st, 0, etag);
                set_ty(post, st, 20);
                expect = 0;
            } else if st[5] == 6 && src[nstart] == 66 && src[nstart + 1] == 117 && src[nstart + 2] == 102 && src[nstart + 3] == 102 && src[nstart + 4] == 101 && src[nstart + 5] == 114 {
                // B3-2b/B3-3: Buffer.new[Int](cap, region) -> Buffer[Int] handle;
                // Buffer.try_new[Int](cap, region) -> Result[Buffer[Int], Int].
                if st[0] < n && src[st[0]] == 46 {
                    st[0] = st[0] + 1;
                    skip(src, st, n);
                    let cstart = st[0];
                    let ctor = name_id(src, st, post);
                    if st[5] == 3 && src[cstart] == 110 && src[cstart + 1] == 101 && src[cstart + 2] == 119 {
                        if st[13] == 0 { write("stage1: E-LS-UNSUPPORTED: Buffer.new is only allowed in a Buffer let initializer\n"); st[3] = 1; return 0; }
                        post[131960] = post[131960] | 4;
                        if expect_char(src, st, 91, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 73, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 110, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 116, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 40, n) == 0 { st[3] = 1; return 0; }
                        skip(src, st, n);
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        let aty = post[110000 + st[2] - 1];
                        if aty != 1 && aty != 2 { st[3] = 1; return 0; }
                        if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                        skip(src, st, n);
                        let rgn = name_id(src, st, post);
                        if st[5] == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                        push_post(post, st, 56, 0);
                        set_ty(post, st, 9);
                        expect = 0;
                    } else if st[5] == 7 && src[cstart] == 116 && src[cstart + 1] == 114 && src[cstart + 2] == 121 && src[cstart + 3] == 95 && src[cstart + 4] == 110 && src[cstart + 5] == 101 && src[cstart + 6] == 119 {
                        // B3-3/B3-5b: Buffer.try_new[Int](cap, rgn) -> Result[Buffer[Int], Int|AllocError].
                        // The error payload is the runtime failure code -1.
                        if st[9] == 0 || ty_kind(st[9]) != 7 || ty_t1(st[9]) != 9 || (ty_t2(st[9]) != 1 && ty_t2(st[9]) != 10) {
                            write("stage1: E-LS-UNSUPPORTED: Buffer.try_new needs a Result[Buffer[Int], Int] or Result[Buffer[Int], AllocError] annotation\n");
                            st[3] = 1;
                            return 0;
                        }
                        if expect_char(src, st, 91, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 73, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 110, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 116, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 40, n) == 0 { st[3] = 1; return 0; }
                        skip(src, st, n);
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        let aty = post[110000 + st[2] - 1];
                        if aty != 1 && aty != 2 { st[3] = 1; return 0; }
                        if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                        skip(src, st, n);
                        let rgn = name_id(src, st, post);
                        if st[5] == 0 { st[3] = 1; return 0; }
                        if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                        let blk = st[12];
                        st[12] = st[12] + 16;
                        push_post(post, st, 61, blk);
                        set_ty(post, st, st[9]);
                        expect = 0;
                    } else { st[3] = 1; return 0; }
                } else { st[3] = 1; return 0; }
            } else if st[0] < n && src[st[0]] == 40 && bcode != 0 {
                st[0] = st[0] + 1;
                if bcode == 1 {
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 41, 0); set_ty(post, st, 1);
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
                    push_post(post, st, 40 + bcode, aslots); set_ty(post, st, 1);
                } else if bcode == 6 || bcode == 7 {
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let ty1 = post[110000 + st[2] - 1];
                    if ty1 != 4 && ty1 != 5 { write("slice: concat_into/append_into needs Slice\n"); st[3] = 1; return 0; }
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let ty2 = post[110000 + st[2] - 1];
                    if bcode == 6 {
                        if ty2 != ty1 { write("slice: concat_into type mismatch\n"); st[3] = 1; return 0; }
                    } else {
                        if ty1 == 4 { if ty2 != 1 && ty2 != 2 { write("slice: append_into element type\n"); st[3] = 1; return 0; } }
                        else if ty2 != 1 { write("slice: append_into element type\n"); st[3] = 1; return 0; }
                    }
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let ty3 = post[110000 + st[2] - 1];
                    if ty3 != ty1 { write("slice: output Slice type mismatch\n"); st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    let boxA = st[12];
                    st[12] = st[12] + 24;
                    let boxB = st[12];
                    if bcode == 6 { st[12] = st[12] + 24; }
                    else { st[12] = st[12] + 16; }
                    let boxOut = st[12];
                    st[12] = st[12] + 24;
                    // R4.3: result block {tag, base, len}
                    let rblk = st[12];
                    st[12] = st[12] + 24;
                    let mi = st[2];
                    push_post(post, st, 31, 0);
                    post[100200 + mi] = boxA;
                    post[100201 + mi] = boxB;
                    post[100203 + mi] = boxOut;
                    post[100204 + mi] = rblk;
                    post[100202 + mi] = ty1 | (bcode << 8);
                    set_ty(post, st, mk_res_ty(ty1, 10));
                } else if bcode == 8 {
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 32, 0);
                    set_ty(post, st, 1);
                } else if bcode == 9 {
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let aty = post[110000 + st[2] - 1];
                    if aty != 1 && aty != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 48, 0);
                    set_ty(post, st, 1);
                } else if bcode == 10 || bcode == 11 {
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 44 + bcode, 0);
                    set_ty(post, st, 1);
                } else if bcode == 12 || bcode == 13 || bcode == 14 {
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let aty = post[110000 + st[2] - 1];
                    if aty != 1 && aty != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 44 + bcode, 0);
                    set_ty(post, st, 1);
                } else if bcode == 15 {
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let aty1 = post[110000 + st[2] - 1];
                    if aty1 != 1 && aty1 != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let aty2 = post[110000 + st[2] - 1];
                    if aty2 != 1 && aty2 != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 59, 0);
                    set_ty(post, st, 1);
                } else if bcode == 16 {
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let aty1 = post[110000 + st[2] - 1];
                    if aty1 != 1 && aty1 != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let aty2 = post[110000 + st[2] - 1];
                    if aty2 != 1 && aty2 != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 60, 0);
                    set_ty(post, st, 1);
                } else if bcode == 17 {
                    // R4.3: str_try_concat(a, b) -> Result[Str, AllocError].
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let saty1 = post[110000 + st[2] - 1];
                    if saty1 != 3 { st[3] = 1; return 0; }
                    box_last_arg(post, st);
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let saty2 = post[110000 + st[2] - 1];
                    if saty2 != 3 { st[3] = 1; return 0; }
                    box_last_arg(post, st);
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    let sblk = st[12];
                    st[12] = st[12] + 64;
                    push_post(post, st, 64, sblk);
                    set_ty(post, st, mk_res_ty(3, 10));
                } else if bcode == 18 {
                    // R4.2: arena_stat(0..3) -> high_water/allocs/rejects/reclaims.
                    skip(src, st, n);
                    let asel = 0 - 1;
                    if st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 51 { asel = src[st[0]] - 48; st[0] = st[0] + 1; }
                    if asel < 0 { write("arena_stat: selector must be 0..3\n"); st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 65, asel);
                    set_ty(post, st, 1);
                } else if bcode == 19 {
                    // R4.4: region_used() = current - innermost region mark (or base).
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 66, 0);
                    set_ty(post, st, 1);
                } else if bcode == 20 {
                    // R4.4: arena_mark() -> current offset (rewind token).
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 67, 0);
                    set_ty(post, st, 1);
                } else if bcode == 21 {
                    // R4.4: arena_rewind(m) -> 0, or -1 when m is out of range
                    // or below the innermost region mark.
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let rwy = post[110000 + st[2] - 1];
                    if rwy != 1 && rwy != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 68, 0);
                    set_ty(post, st, 1);
                } else if bcode == 22 {
                    // R4.6: arena_free(off, size) -> 0 or -1.
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let fty1 = post[110000 + st[2] - 1];
                    if fty1 != 1 && fty1 != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 44, n) == 0 { st[3] = 1; return 0; }
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let fty2 = post[110000 + st[2] - 1];
                    if fty2 != 1 && fty2 != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 70, 0);
                    set_ty(post, st, 1);
                } else if bcode == 23 {
                    // R4.6: arena_coalesce() -> 0 (merge adjacent free holes).
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 71, 0);
                    set_ty(post, st, 1);
                } else if bcode == 24 {
                    // R4.7: region_limit() = effective end - innermost mark.
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 72, 0);
                    set_ty(post, st, 1);
                } else if bcode == 25 {
                    // R4.7: arena_compact() -> number of moved blocks.
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 73, 0);
                    set_ty(post, st, 1);
                } else {
                    skip(src, st, n);
                    let pn = name_id(src, st, post);
                    if st[5] == 0 { st[3] = 1; return 0; }
                    let psi = sl_find(post, pn, st[4]);
                    let spath = str_find(post, pn, st[4]);
                    if spath >= 0 { push_post(post, st, 23, spath); }
                    else if psi >= 0 { push_post(post, st, 13, psi); }
                    else { st[3] = 1; return 0; }
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
                    push_post(post, st, 40 + bcode, 4); set_ty(post, st, 1);
                }
            } else if st[0] < n && src[st[0]] == 40 {
                st[0] = st[0] + 1;
                if cdepth >= 32 { st[3] = 1; return 0; }
                cname[cdepth] = name;
                cnargs[cdepth] = 0;
                cargs[cdepth] = 0;
                cargstart[cdepth] = st[2];
                // B5-8: the ref returned by this call inherits the most
                // conservative lifetime of its ref arguments (see make_ref_arg).
                post[135802] = 0;
                // B5-1: resolve the callee's ref mask by its source span (the
                // name-id table and source spans are both stable at this point).
                let csel = 0 - 1;
                let cfi = 0;
                let cfd = post[140000];
                while cfi < cfd {
                    let cb = 140001 + cfi * 8;
                    if post[cb + 1] == st[5] {
                        let same = 1;
                        let cj = 0;
                        while cj < st[5] {
                            if src[nstart + cj] != src[post[cb] + cj] { same = 0; break; }
                            cj = cj + 1;
                        }
                        if same == 1 { csel = cfi; break; }
                    }
                    cfi = cfi + 1;
                }
                cref[cdepth] = csel;
                cdepth = cdepth + 1;
                ops[top] = 98;
                top = top + 1;
                paren = paren + 1;
                expect = 1;
            } else if st[0] < n && src[st[0]] == 91 && var_is_buffer(post, name, st[4], st[0]) == 1 {
                // B3-4a: b[i] reads element i through buffer_get; out of range is -1.
                st[0] = st[0] + 1;
                skip(src, st, n);
                let bvi = var_find(post, name, st[4], st[0]);
                push_handle(post, st, bvi);
                parse_index(src, st, post);
                if st[3] != 0 { return 0; }
                let ity = post[110000 + st[2] - 1];
                if ity != 1 && ity != 2 { st[3] = 1; return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                push_post(post, st, 60, 0);
                set_ty(post, st, 1);
                expect = 0;
            } else if st[0] < n && src[st[0]] == 91 && tmpl_find(post, name) >= 0 {
                // R2.6-B: explicit single type argument on a generic enum
                // variant in expression position: `Box[Int].Box(1)`.  Only
                // the one-tyarg form fits the frozen EBNF v2.3 expression
                // grammar (its postfix `[expr]`); struct explicit tyargs are
                // not supported (`S.new(...)` inference is the constructor)
                // and comma lists are rejected.
                let eti = tmpl_find(post, name);
                if (post[123001 + eti * 12 + 1] & 128) != 0 { write("ctor: explicit type arguments on a generic struct are not supported; use S.new(...)\n"); st[3] = 1; return 0; }
                st[0] = st[0] + 1;
                skip(src, st, n);
                let et1 = parse_ty(src, st, post);
                if st[3] != 0 || et1 == 0 { write("ctor: bad explicit type argument\n"); st[3] = 1; return 0; }
                skip(src, st, n);
                if st[0] < n && src[st[0]] == 44 { write("ctor: explicit type-argument lists do not fit the frozen grammar\n"); st[3] = 1; return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                skip(src, st, n);
                if st[0] >= n || src[st[0]] != 46 { write("ctor: expected .variant\n"); st[3] = 1; return 0; }
                st[0] = st[0] + 1;
                skip(src, st, n);
                let vf2 = name_id(src, st, post);
                if st[5] == 0 { write("ctor: expected .variant\n"); st[3] = 1; return 0; }
                let nv2 = tmpl_nvariants(post, eti);
                let vk2 = 0 - 1;
                let k2 = 0;
                while k2 < nv2 {
                    if tmpl_var_name(post, eti, k2) == vf2 { vk2 = k2; }
                    k2 = k2 + 1;
                }
                if vk2 < 0 { write("ctor: unknown generic variant\n"); st[3] = 1; return 0; }
                let pc2 = tmpl_var_pty(post, eti, vk2);
                let pr2 = pc2;
                if pr2 == 100 { pr2 = et1; }
                else if pr2 == 101 { pr2 = 1; }
                let ii3 = mk_inst(post, eti, et1, 1);
                if ii3 < 0 { write("ctor: cannot instantiate generic enum\n"); st[3] = 1; return 0; }
                if pc2 != 0 {
                    if st[0] >= n || src[st[0]] != 40 { write("ctor: expected (\n"); st[3] = 1; return 0; }
                    st[0] = st[0] + 1;
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let at3 = post[110000 + st[2] - 1];
                    if at3 == 0 { write("ctor: unknown payload type\n"); st[3] = 1; return 0; }
                    if pr2 != at3 && ((pr2 != 1 && pr2 != 2) || (at3 != 1 && at3 != 2)) { write("ctor: generic payload mismatch\n"); st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                }
                let blk3 = st[12];
                if pr2 == 0 { st[12] = st[12] + 8; }
                else { st[12] = st[12] + ty_size(pr2); }
                let mi3 = st[2];
                push_post(post, st, 27, blk3);
                set_ty(post, st, 8 | (ii3 << 8));
                post[100000 + mi3] = vk2 | (pr2 << 8);
            } else if st[0] < n && src[st[0]] == 91 {
                st[0] = st[0] + 1;
                parse_index(src, st, post);
                if st[3] != 0 { return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                let rvi = var_find(post, name, st[4], st[0]);
                let rvt = 0;
                if rvi >= 0 { rvt = post[50004 + rvi * 4] & 255; }
                if rvt == 12 {
                    push_post(post, st, 85, rvi); set_ty(post, st, 2);
                } else if rvt == 13 || rvt == 14 {
                    if rvt == 13 { push_post(post, st, 83, rvi); set_ty(post, st, 2); }
                    else { push_post(post, st, 84, rvi); set_ty(post, st, 1); }
                } else {
                let ai = arr_find(post, name, st[4]);
                if ai >= 0 {
                    push_post(post, st, 10, ai);
                    set_ty(post, st, elem_ty((post[4098 + ai * 3] >> 31) & 15));
                } else {
                    let si = sl_find(post, name, st[4]);
                    if si >= 0 {
                        push_post(post, st, 11, si);
                        set_ty(post, st, elem_ty((post[66402 + si * 2] >> 31) & 15));
                    }
                    else { st[3] = 1; return 0; }
                }
                            }
} else if st[0] < n && src[st[0]] == 46 && var_is_buffer(post, name, st[4], st[0]) == 1 {
                st[0] = st[0] + 1;
                skip(src, st, n);
                let fstart = st[0];
                let vf = name_id(src, st, post);
                if st[5] == 0 { st[3] = 1; return 0; }
                let bvi = var_find(post, name, st[4], st[0]);
                if st[5] == 3 || st[5] == 4 { post[131960] = post[131960] | 1; }
                if st[5] == 4 || st[5] == 7 { post[131960] = post[131960] | 2; }
                if st[5] == 3 && src[fstart] == 108 && src[fstart + 1] == 101 && src[fstart + 2] == 110 {
                    push_handle(post, st, bvi);
                    push_post(post, st, 57, 0);
                    set_ty(post, st, 1);
                    expect = 0;
                } else if st[5] == 3 && src[fstart] == 99 && src[fstart + 1] == 97 && src[fstart + 2] == 112 {
                    push_handle(post, st, bvi);
                    push_post(post, st, 58, 0);
                    set_ty(post, st, 1);
                    expect = 0;
                } else if st[5] == 4 && src[fstart] == 112 && src[fstart + 1] == 117 && src[fstart + 2] == 115 && src[fstart + 3] == 104 {
                    push_handle(post, st, bvi);
                    if expect_char(src, st, 40, n) == 0 { st[3] = 1; return 0; }
                    skip(src, st, n);
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let pty = post[110000 + st[2] - 1];
                    if pty != 1 && pty != 2 { st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 59, 0);
                    set_ty(post, st, 1);
                    expect = 0;
                } else if st[5] == 7 && src[fstart] == 114 && src[fstart + 1] == 101 && src[fstart + 2] == 108 && src[fstart + 3] == 101 && src[fstart + 4] == 97 && src[fstart + 5] == 115 && src[fstart + 6] == 101 {
                    // B3-4b: b.release() -> buffer_release(b); 0 on success, -1 if not top.
                    push_handle(post, st, bvi);
                    push_post(post, st, 62, 0);
                    set_ty(post, st, 1);
                    expect = 0;
                } else { st[3] = 1; return 0; }
            } else if st[0] < n && src[st[0]] == 46 {
                st[0] = st[0] + 1;
                skip(src, st, n);
                let vf = name_id(src, st, post);
                if st[5] == 0 { st[3] = 1; return 0; }
                let rvi = var_find(post, name, st[4], st[0]);
                let rvt = 0;
                if rvi >= 0 { rvt = post[50004 + rvi * 4] & 255; }
                // R2.6-B: hoist the template lookup so the constructor branch
                // conditions stay free of calls inside index expressions
                // (B-LS cannot parse `arr[f(...)]`).
                let tmi = tmpl_find(post, name);
                let tmb = 0;
                if tmi >= 0 { tmb = post[123001 + tmi * 12 + 1] & 128; }
                if rvt == 12 || rvt == 13 || rvt == 14 {
                    let f0 = post[16002 + vf * 2];
                    let fl = post[16002 + vf * 2 + 1];
                    let islen = 0;
                    if fl == 3 {
                        let w0 = post[18000 + f0 / 8];
                        let c0 = (w0 >> ((f0 % 8) * 8)) & 255;
                        let w1 = post[18000 + (f0 + 1) / 8];
                        let c1 = (w1 >> (((f0 + 1) % 8) * 8)) & 255;
                        let w2 = post[18000 + (f0 + 2) / 8];
                        let c2 = (w2 >> (((f0 + 2) % 8) * 8)) & 255;
                        if c0 == 108 && c1 == 101 && c2 == 110 { islen = 1; }
                    }
                    if islen == 0 { st[3] = 1; return 0; }
                    if rvt == 12 { push_post(post, st, 79, rvi); }
                    else { push_post(post, st, 80, rvi); }
                    set_ty(post, st, 1);
                    expect = 0;
                } else {
                let stri = str_find(post, name, st[4]);
                if stri >= 0 {
                    // Compare the field spelling to "len" (108,101,110).
                    let f0 = post[16002 + vf * 2];
                    let fl = post[16002 + vf * 2 + 1];
                    if fl == 3 {
                        let w0 = post[18000 + f0 / 8];
                        let c0 = (w0 >> ((f0 % 8) * 8)) & 255;
                        let w1 = post[18000 + (f0 + 1) / 8];
                        let c1 = (w1 >> (((f0 + 1) % 8) * 8)) & 255;
                        let w2 = post[18000 + (f0 + 2) / 8];
                        let c2 = (w2 >> (((f0 + 2) % 8) * 8)) & 255;
                        if c0 == 108 && c1 == 101 && c2 == 110 {
                            push_post(post, st, 20, stri);
                            set_ty(post, st, 1);
                            expect = 0;
                        } else { st[3] = 1; return 0; }
                    } else { st[3] = 1; return 0; }
                } else if (sl_find(post, name, st[4]) >= 0) {
                    // R2.6-A2: a plain Slice variable's `.len`.  A Slice value
                    // is a 16-byte frame slot: [off]=base ptr, [off+8]=len.
                    // Reuse kind 12 (`mov rax,[rip+val]`) to read the length
                    // word at off+8; only the spelling "len" is accepted.
                    let slf0 = post[16002 + vf * 2];
                    let slfl = post[16002 + vf * 2 + 1];
                    let sli = sl_find(post, name, st[4]);
                    if slfl == 3 {
                        let sw0 = post[18000 + slf0 / 8];
                        let sc0 = (sw0 >> ((slf0 % 8) * 8)) & 255;
                        let sw1 = post[18000 + (slf0 + 1) / 8];
                        let sc1 = (sw1 >> (((slf0 + 1) % 8) * 8)) & 255;
                        let sw2 = post[18000 + (slf0 + 2) / 8];
                        let sc2 = (sw2 >> (((slf0 + 2) % 8) * 8)) & 255;
                        if sc0 == 108 && sc1 == 101 && sc2 == 110 {
                            let sloff = (post[66402 + sli * 2] & 2147483647) + 8;
                            push_post(post, st, 12, sloff);
                            set_ty(post, st, 1);
                            expect = 0;
                        } else { st[3] = 1; return 0; }
                    } else { st[3] = 1; return 0; }
                } else {
                let svi = sv_find(post, name, st[4]);
                if svi >= 0 {
                    let sidx = post[6404 + svi * 4];
                    // R2.6-C: explicit trait-method call `p.eq(q)` / `p.lt(q)`
                    // on a plain struct value (sidx < 70).  The method name maps
                    // to a builtin trait code (eq -> Eq=2, lt -> Ord=1) and the
                    // impl row's method becomes the callee; the receiver and the
                    // argument are pushed as addresses (kind 89), and kind 93
                    // with meta 0 emits the plain two-address method call
                    // (its op-derivation/negation paths stay off for meta 0).
                    let wtc = 0;
                    if sidx < 70 && st[0] < n && src[st[0]] == 40 {
                        let mw0 = post[16002 + vf * 2];
                        let mwl = post[16002 + vf * 2 + 1];
                        if mwl == 2 {
                            let mw1 = post[18000 + mw0 / 8];
                            let mb0 = (mw1 >> ((mw0 % 8) * 8)) & 255;
                            let mw2 = post[18000 + (mw0 + 1) / 8];
                            let mb1 = (mw2 >> (((mw0 + 1) % 8) * 8)) & 255;
                            if mb0 == 101 && mb1 == 113 { wtc = 2; }
                            else if mb0 == 108 && mb1 == 116 { wtc = 1; }
                        }
                    }
                    if wtc != 0 {
                        let mrow = 0 - 1;
                        let ms = 0;
                        while ms < post[135748] {
                            if post[135752 + ms * 4] == wtc && post[135753 + ms * 4] == 30 + sidx { mrow = ms; }
                            ms = ms + 1;
                        }
                        if mrow < 0 {
                            write("stage1: E-LS-NO-IMPL: ");
                            diag_pos(src, st[0] - 1, 0);
                            write("trait method call has no impl for this type\n");
                            write("  fix-it: add an impl of Eq/Ord for this struct (fn eq/lt(ref a, ref b) -> Int)\n");
                            st[3] = 1;
                            return 0;
                        }
                        st[0] = st[0] + 1;
                        skip(src, st, n);
                        push_post(post, st, 89, svi);
                        set_ty(post, st, 30 + sidx);
                        // The argument is a same-type struct variable (bare name).
                        let anm = name_id(src, st, post);
                        if st[5] == 0 { st[3] = 1; return 0; }
                        let asvi = sv_find(post, anm, st[4]);
                        if asvi < 0 {
                            write("stage1: E-LS-UNSUPPORTED: trait method argument must be a struct variable of the same type\n");
                            st[3] = 1;
                            return 0;
                        }
                        let asidx = post[6404 + asvi * 4];
                        if asidx != sidx {
                            write("stage1: E-LS-UNSUPPORTED: trait method argument must be the same struct type\n");
                            st[3] = 1;
                            return 0;
                        }
                        push_post(post, st, 89, asvi);
                        set_ty(post, st, 30 + asidx);
                        skip(src, st, n);
                        if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                        let mi = st[2];
                        push_post(post, st, 93, post[135754 + mrow * 4]);
                        post[100000 + mi] = 0;
                        set_ty(post, st, 1);
                    } else if sidx >= 70 {
                        // R2.2: generic struct instance field read `p.f`
                        // (sidx = 70+ii; the field row lives in the shared
                        // instance table).  Every field slot is 8 bytes.
                        let gii = sidx - 70;
                        let gfi = inst_var_find(post, gii, vf);
                        if gfi < 0 { st[3] = 1; return 0; }
                        let goff = (post[6403 + svi * 4] & 2147483647) + gfi * 8;
                        push_post(post, st, 12, goff);
                        set_ty(post, st, 1);
                    }
                    else {
                    let fi = st_field_find(post, sidx, vf);
                    if fi < 0 { st[3] = 1; return 0; }
                    let fb = 5121 + sidx * 18;
                    let fmeta = post[fb + 3 + fi * 2];
                    let off = (post[6403 + svi * 4] & 2147483647) + (fmeta & 2147483647);
                    let elem = (fmeta >> 31) & 15;
                    if elem >= 11 {
                        // B5-8: a ref read out of a field can point at a local, so
                        // its lifetime is bounded by the struct variable's scope.
                        post[135802] = ((post[6403 + svi * 4] >> 31) << 1) | 1;
                        push_post(post, st, 12, off);
                        set_ty(post, st, elem);
                    }
                    else if elem == 8 { push_post(post, st, 12, off); set_ty(post, st, 1); }
                    else { push_post(post, st, 15, off); set_ty(post, st, 2); }
                    }
                } else if (tmi >= 0 && tmb != 0) {
                    // R2.6-B: a generic-struct template (nparams bit 7) in
                    // expression position is its constructor `S.new(v0..vn)`
                    // with type arguments inferred from the field values.
                    // The value is an instance block (120+ii) produced by
                    // kind 90 field stores + a kind 91 lea, so args, returns
                    // and let receivers reuse the R2.6-A bare-struct ABI.
                    let ti = tmi;
                    let nf = tmpl_nvariants(post, ti);
                    // vf must spell `new` (110,101,119) in the name byte table.
                    let nf0 = post[16002 + vf * 2];
                    let nfl = post[16002 + vf * 2 + 1];
                    let isnew = 0;
                    if nfl == 3 {
                        let nw0 = post[18000 + nf0 / 8];
                        let nc0 = (nw0 >> ((nf0 % 8) * 8)) & 255;
                        let nw1 = post[18000 + (nf0 + 1) / 8];
                        let nc1 = (nw1 >> (((nf0 + 1) % 8) * 8)) & 255;
                        let nw2 = post[18000 + (nf0 + 2) / 8];
                        let nc2 = (nw2 >> (((nf0 + 2) % 8) * 8)) & 255;
                        if nc0 == 110 && nc1 == 101 && nc2 == 119 { isnew = 1; }
                    }
                    if isnew == 0 { write("ctor: expected .new on a generic struct\n"); st[3] = 1; return 0; }
                    let blk = st[12];
                    st[12] = st[12] + nf * 8;
                    skip(src, st, n);
                    if st[0] >= n || src[st[0]] != 40 { write("ctor: expected (\n"); st[3] = 1; return 0; }
                    st[0] = st[0] + 1;
                    let gt1 = 0;
                    let gt2 = 0;
                    let fi = 0;
                    while fi < nf {
                        if fi > 0 {
                            skip(src, st, n);
                            if st[0] >= n || src[st[0]] != 44 { write("ctor: field count mismatch\n"); st[3] = 1; return 0; }
                            st[0] = st[0] + 1;
                        }
                        skip(src, st, n);
                        if st[0] >= n || src[st[0]] == 41 { write("ctor: field count mismatch\n"); st[3] = 1; return 0; }
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        let aty = post[110000 + st[2] - 1];
                        if aty == 0 { write("ctor: unknown field value type\n"); st[3] = 1; return 0; }
                        let pty = tmpl_var_pty(post, ti, fi);
                        let real = pty;
                        if pty == 100 {
                            if gt1 == 0 { gt1 = aty; real = aty; }
                            else if gt1 == aty || ((gt1 == 1 || gt1 == 2) && (aty == 1 || aty == 2)) { real = gt1; }
                            else { write("ctor: inconsistent type argument\n"); st[3] = 1; return 0; }
                        } else if pty == 101 {
                            if gt2 == 0 { gt2 = aty; real = aty; }
                            else if gt2 == aty || ((gt2 == 1 || gt2 == 2) && (aty == 1 || aty == 2)) { real = gt2; }
                            else { write("ctor: inconsistent type argument\n"); st[3] = 1; return 0; }
                        } else if pty != aty && ((pty != 1 && pty != 2) || (aty != 1 && aty != 2)) {
                            write("ctor: field type mismatch\n"); st[3] = 1; return 0;
                        }
                        if real != 1 && real != 2 && (real < 11 || real > 15) {
                            write("ctor: field type not storable in a struct slot\n"); st[3] = 1; return 0;
                        }
                        push_post(post, st, 90, blk + fi * 8);
                        fi = fi + 1;
                    }
                    skip(src, st, n);
                    if expect_char(src, st, 41, n) == 0 { write("ctor: field count mismatch\n"); st[3] = 1; return 0; }
                    let ii = mk_inst(post, ti, gt1, gt2);
                    if ii < 0 { write("ctor: cannot instantiate generic struct\n"); st[3] = 1; return 0; }
                    push_post(post, st, 91, blk);
                    set_ty(post, st, 120 + ii);
                } else if (tmpl_find(post, name) >= 0) {
                    let ti = tmpl_find(post, name);
                    let exp = st[9];
                    let gk = ty_kind(exp);
                    let ii = 0 - 1;
                    let gt1 = 1;
                    let gt2 = 1;
                    if gk == 8 {
                        ii = ty_t1(exp);
                        gt1 = post[124001 + ii * 12 + 1];
                        gt2 = post[124001 + ii * 12 + 2];
                    } else if exp != 0 { write("ctor: expected generic enum\n"); st[3] = 1; return 0; }
                    let nv = tmpl_nvariants(post, ti);
                    let vk = 0 - 1;
                    let k = 0;
                    while k < nv {
                        if tmpl_var_name(post, ti, k) == vf { vk = k; }
                        k = k + 1;
                    }
                    if vk < 0 { write("ctor: unknown generic variant\n"); st[3] = 1; return 0; }
                    let pcode = tmpl_var_pty(post, ti, vk);
                    let preal = pcode;
                    if preal == 100 { preal = gt1; }
                    else if preal == 101 { preal = gt2; }
                    if pcode != 0 {
                        if st[0] >= n || src[st[0]] != 40 { write("ctor: expected (\n"); st[3] = 1; return 0; }
                        st[0] = st[0] + 1;
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        let apty = post[110000 + st[2] - 1];
                        if apty == 0 { write("ctor: unknown payload type\n"); st[3] = 1; return 0; }
                        if pcode == 100 { gt1 = apty; preal = apty; }
                        else if pcode == 101 { gt2 = apty; preal = apty; }
                        else {
                            let scalar_ok = 0;
                            if (preal == 1 || preal == 2) && (apty == 1 || apty == 2) { scalar_ok = 1; }
                            if preal != apty && scalar_ok == 0 { write("ctor: generic payload mismatch\n"); st[3] = 1; return 0; }
                        }
                        if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    }
                    if ii < 0 {
                        ii = mk_inst(post, ti, gt1, gt2);
                        if ii < 0 { write("ctor: cannot instantiate generic enum\n"); st[3] = 1; return 0; }
                        exp = 8 | (ii << 8);
                        preal = inst_var_pty(post, ii, vk);
                    } else {
                        let ip = inst_var_pty(post, ii, vk);
                        if ip != preal { write("ctor: generic payload mismatch\n"); st[3] = 1; return 0; }
                    }
                    let blk = st[12];
                    if preal == 0 { st[12] = st[12] + 8; }
                    else { st[12] = st[12] + ty_size(preal); }
                    let mi = st[2];
                    push_post(post, st, 27, blk);
                    set_ty(post, st, exp);
                    post[100000 + mi] = vk | (preal << 8);
                } else if (name == post[17002] || name == post[17003]) && st[9] != 0 {
                    let exp = st[9];
                    let ekind = ty_kind(exp);
                    let is_opt = 0;
                    if name == post[17002] { is_opt = 1; }
                    let tag = 0 - 1;
                    let need = 0;
                    if is_opt == 1 {
                        if vf == post[17004] { tag = 0; need = 1; }
                        else if vf == post[17005] { tag = 1; }
                        else { write("ctor: bad Option variant\n"); st[3] = 1; return 0; }
                    } else {
                        if vf == post[17006] { tag = 0; need = 1; }
                        else if vf == post[17007] { tag = 1; need = 1; }
                        else { write("ctor: bad Result variant\n"); st[3] = 1; return 0; }
                    }
                    let pty = 0;
                    if need == 1 {
                        if st[0] >= n || src[st[0]] != 40 { write("ctor: expected (\n"); st[3] = 1; return 0; }
                        st[0] = st[0] + 1;
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        pty = post[110000 + st[2] - 1];
                        if pty == 0 { write("ctor: unknown payload type\n"); st[3] = 1; return 0; }
                        if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    }
                    let gdesc = exp;
                    if is_opt == 1 && (ekind != 6 || name != post[17002]) { write("ctor: type mismatch\n"); st[3] = 1; return 0; }
                    if is_opt == 0 && (ekind != 7 || name != post[17003]) { write("ctor: type mismatch\n"); st[3] = 1; return 0; }
                    let gty = 0;
                    if need == 1 {
                        if is_opt == 1 { gty = ty_t1(gdesc); }
                        else if tag == 0 { gty = ty_t1(gdesc); }
                        else { gty = ty_t2(gdesc); }
                        if gty != pty {
                            let scalar_ok = 0;
                            if (gty == 1 || gty == 2) && (pty == 1 || pty == 2) { scalar_ok = 1; }
                            if scalar_ok == 0 { write("ctor: payload type mismatch\n"); st[3] = 1; return 0; }

                        }
                    }
                    let blk = st[12];
                    if gty == 0 { st[12] = st[12] + 8; }
                    else if (gty & 255) >= 30 { st[12] = st[12] + 8 + st_size(post, (gty & 255) - 30); }
                    else { st[12] = st[12] + ty_size(gty); }
                    let mi = st[2];
                    push_post(post, st, 27, blk);
                    set_ty(post, st, gdesc);
                    post[100000 + mi] = tag | (gty << 8);
                } else if ((name == post[17002] || name == post[17003]) && st[9] == 0) {
                    let is_opt = 0;
                    if name == post[17002] { is_opt = 1; }
                    let tag = 0 - 1;
                    let need = 0;
                    if is_opt == 1 {
                        if vf == post[17004] { tag = 0; need = 1; }
                        else if vf == post[17005] { tag = 1; }
                        else { write("ctor: bad Option variant\n"); st[3] = 1; return 0; }
                    } else {
                        write("ctor: Result needs a type annotation\n"); st[3] = 1; return 0;
                    }
                    if need == 0 { write("ctor: cannot infer None type\n"); st[3] = 1; return 0; }
                    if st[0] >= n || src[st[0]] != 40 { write("ctor: expected (\n"); st[3] = 1; return 0; }
                    st[0] = st[0] + 1;
                    parse_index(src, st, post);
                    if st[3] != 0 { return 0; }
                    let pty = post[110000 + st[2] - 1];
                    if pty == 0 { write("ctor: unknown payload type\n"); st[3] = 1; return 0; }
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    let gdesc = mk_opt_ty(pty);
                    let blk = st[12];
                    if (pty & 255) >= 30 { st[12] = st[12] + 8 + st_size(post, (pty & 255) - 30); }
                    else { st[12] = st[12] + ty_size(pty); }
                    let mi = st[2];
                    push_post(post, st, 27, blk);
                    set_ty(post, st, gdesc);
                    post[100000 + mi] = tag | (pty << 8);
                } else {
                    let ei = en_find(post, name);
                    if ei < 0 { st[3] = 1; return 0; }
                    let etag = en_var_find(post, ei, vf);
                    if etag < 0 { st[3] = 1; return 0; }
                    skip(src, st, n);
                    if (etag & 256) != 0 {
                        if st[0] >= n || src[st[0]] != 40 { st[3] = 1; return 0; }
                        st[0] = st[0] + 1;
                        parse_index(src, st, post);
                        if st[3] != 0 { return 0; }
                        if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                        push_post(post, st, 24, etag & 255);
                    } else {
                        push_post(post, st, 0, etag & 255);
                        set_ty(post, st, 0);
                    }
                }
                }
                            }
} else {
                let stri = str_find(post, name, st[4]);
                if stri >= 0 { push_post(post, st, 19, stri); set_ty(post, st, 3); }
                else {
                    let si = sl_find(post, name, st[4]);
                    if si >= 0 {
                        push_post(post, st, 13, si);
                        set_ty(post, st, slice_ty((post[66402 + si * 2] >> 31) & 15));
                    }
                    else {
                        let vi = var_find(post, name, st[4], st[0]);
                        // R2.6-F: a by-value struct parameter is registered in
                        // both the var and the sv tables (type stays 0 in the
                        // var table); prefer the sv entry so a bare name still
                        // means the struct address, not a scalar load.
                        if (vi >= 0 && (post[50004 + vi * 4] & 255) == 0 && sv_find(post, name, st[4]) >= 0) { vi = 0 - 1; }
                        if vi >= 0 {
                            push_var_expect(post, st, vi);
                            // B5-9: a bare ref read carries its lifetime, so array
                            // element / field stores can check it.
                            let vty2 = post[110000 + st[2] - 1];
                            if vty2 >= 11 && vty2 <= 15 { post[135802] = post[136000 + vi]; }
                        } else {
                            // B7: a bare struct value pushes its runtime address
                            // (method-call ABI operand).
                            let svi4 = sv_find(post, name, st[4]);
                            if svi4 >= 0 {
                                push_post(post, st, 89, svi4);
                                let sty = post[6404 + svi4 * 4];
                                if sty >= 70 { sty = 120 + sty - 70; }
                                else { sty = 30 + sty; }
                                set_ty(post, st, sty);
                            } else {
                                // R4.5: Result/Option variables are opt-table entries;
                                // load their block pointer so `r?` can consume them.
                                let ovi = opt_find(post, name, st[4]);
                                if ovi < 0 { st[3] = 1; return 0; }
                                let obase = 90001 + ovi * 6;
                                let ometa = post[obase + 2];
                                let oty = 0;
                                if (ometa & 255) == 1 { oty = mk_opt_ty((ometa >> 8) & 255); }
                                else { oty = mk_res_ty((ometa >> 8) & 255, (ometa >> 16) & 255); }
                                push_post(post, st, 69, post[obase + 5]);
                                set_ty(post, st, oty);
                            }
                        }
                    }
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
            while top > 0 && ops[top - 1] != 99 && ops[top - 1] != 98 {
                st[8] = ops[top - 1]; push_binop(src, post, st);
                top = top - 1;
            }
                if top > 0 && ops[top - 1] == 98 {
                    top = top - 1;
                    let fty = post[120000 + cname[cdepth - 1]];
                    let rfi2 = cref[cdepth - 1];
                    let rm2 = 0;
                    let rt2 = 0;
                    let rai2 = cnargs[cdepth - 1];
                    if rfi2 >= 0 {
                        rm2 = post[130000 + rfi2];
                        if rai2 < 8 { rt2 = post[130600 + rfi2 * 8 + rai2]; }
                    }
                    if (rm2 & (1 << rai2)) != 0 && st[2] > cargstart[cdepth - 1] {
                        post[130700] = rt2;
                        let rr2 = make_ref_arg(post, st, cargstart[cdepth - 1], rai2);
                        if rr2 == 0 - 1 { write("ref argument must be a mutable Int variable\n"); st[3] = 1; return 0; }
                        if rr2 == 0 - 2 { write("ref argument cannot be a val binding\n"); st[3] = 1; return 0; }
                        if rr2 == 0 - 3 { write("ref arguments alias the same variable\n"); st[3] = 1; return 0; }
                    }
                    if (fty & 1073741824) != 0 {
                        if st[2] > cargstart[cdepth - 1] { box_last_arg(post, st); }
                    }
                    let actual = cnargs[cdepth - 1];
                    if st[2] > cargstart[cdepth - 1] { actual = actual + 1; }
                    let declared = post[130500 + cname[cdepth - 1]];
                    if declared != 0 && (declared & 255) - 1 != actual {
                        write("stage1: E-LS-ARITY: ");
                        diag_pos(src, st[0] - 1, 0);
                        write("function call argument count mismatch\n");
                        write("  fix-it: expected ");
                        diag_pos(src, (declared & 255) - 1, 1);
                        write(" argument(s), call has ");
                        diag_pos(src, actual, 1);
                        write(" - add the missing argument or align the signature\n");
                        st[3] = 1;
                        return 0;
                    }
                    let ci = cdepth - 1;
                    // B5-10: the callee's boundary effects must be declared here too,
                    // and they propagate into this function's produced set.
                    let cfi2 = cref[cdepth - 1];
                    if post[135700] != 0 { cfi2 = 0 - 1; }
                    if cfi2 >= 0 {
                        let cm2 = post[131700 + cfi2];
                        if cm2 != 0 {
                            let own2 = post[131700 + st[4]];
                            let need2 = cm2 & 116;
                            if (need2 & (116 - (own2 & 116))) != 0 {
                                write("stage1: E-LS-EFFECT: ");
                                diag_pos(src, st[0] - 1, 0);
                                write("call requires an effect the caller does not declare\n");
                                write("  fix-it: declare ");
                                if (need2 & 4) != 0 { write("alloc "); }
                                if (need2 & 16) != 0 { write("panic "); }
                                if (need2 & 32) != 0 { write("spawn "); }
                                if (need2 & 64) != 0 { write("unsafe "); }
                                write("in this function's eff(...) clause, or hoist the call out\n");
                                st[3] = 1;
                                return 0;
                            }
                            post[131960] = post[131960] | need2;
                        }
                    }
                    if (fty & 1073741824) != 0 && actual > cnargs[ci] && cnargs[ci] < 7 {
                        ctypes[ci * 8 + cnargs[ci]] = post[110000 + st[2] - 1];
                    }
                    cdepth = cdepth - 1;
                    let w = arg_width(post, cargstart[cdepth], st[2]);
                    cargs[cdepth] = cargs[cdepth] + w;
                    if (fty & 1073741824) != 0 {
                        let fi = fn_find_nid(post, cname[ci]);
                        let gc = post[135072 + fi * 4];
                        if (gc >= 2) {
                            let q = 0;
                            while q < 2 { post[135800 + q] = 0; q = q + 1; }
                            let bad = 0;
                            let k = 0;
                            while k < actual {
                                let pt = post[132000 + fi * 8 + k];
                                let at = ctypes[ci * 8 + k];
                                if at == 0 { bad = 1; break; }
                                if pt >= 100 {
                                    let gi = pt - 100;
                                    if post[135800 + gi] == 0 { post[135800 + gi] = at; }
                                    else if post[135800 + gi] != at { bad = 1; break; }
                                } else {
                                    let ok = 0;
                                    if pt == at { ok = 1; }
                                    if (pt == 1 || pt == 2) && (at == 1 || at == 2) { ok = 1; }
                                    if ok == 0 { bad = 1; break; }
                                }
                                k = k + 1;
                            }
                            if bad != 0 {
                                write("fn: generic argument type mismatch\n");
                                st[3] = 1;
                                return 0;
                            }
                            k = 0;
                            while k < gc {
                                let req = post[133024 + fi * 8 + k];
                                if req > 0 {
                                    let at = post[135800 + k];
                                    if at == 0 || bound_ok(post, at, req, st[4]) == 0 {
                                        write("fn: generic argument does not satisfy bound\n");
                                        st[3] = 1;
                                        return 0;
                                    }
                                }
                                k = k + 1;
                            }
                            let rg = post[135072 + fi * 4 + 1];
                            let rty = 0;
                            if rg >= 100 { rty = post[135800 + rg - 100]; }
                            else { rty = post[135072 + fi * 4 + 2]; }
                            if rty == 0 {
                                write("fn: cannot infer generic result\n");
                                st[3] = 1;
                                return 0;
                            }
                            if rg >= 100 && rty < 100 { push_post(post, st, 140 + cargs[ci], cname[ci]); }
                            else { push_post(post, st, 160 + cargs[ci], cname[ci]); }
                            set_ty(post, st, rty);
                        } else {
                            let aty = 0;
                            if st[2] > 0 { aty = post[110000 + st[2] - 1]; }
                            if aty == 0 { write("fn: cannot infer generic argument\n"); st[3] = 1; return 0; }
                            if fi >= 0 {
                                let req = post[133024 + fi * 8];
                                if req > 0 && bound_ok(post, aty, req, st[4]) == 0 {
                                    write("fn: generic argument does not satisfy bound\n");
                                    st[3] = 1;
                                    return 0;
                                }
                            }
                            if (fty & 268435456) != 0 && aty < 100 {
                                let opok = 0;
                                if aty == 1 || aty == 2 { opok = 1; }
                                else if aty == 3 { if (fty & 67108864) == 0 { opok = 1; } }
                                else if aty == 4 || aty == 5 { if (fty & 134217728) == 0 { opok = 1; } }
                                if opok == 0 { write("fn: unsupported generic T operation\n"); st[3] = 1; return 0; }
                            }
                            if (fty & 536870912) != 0 && aty < 100 {
                                push_post(post, st, 140 + cargs[ci], cname[ci]);
                                set_ty(post, st, aty);
                            } else {
                                push_post(post, st, 160 + cargs[ci], cname[ci]);
                                set_ty(post, st, fty & 16777215);
                            }
                        }
                    } else {
                        push_post(post, st, 3 + cargs[cdepth], cname[cdepth]);
                        set_ty(post, st, fty);
                    }
                } else if top > 0 && ops[top - 1] == 99 {
                top = top - 1;
            }
            paren = paren - 1;
            st[0] = st[0] + 1;
            expect = 0;
        } else if c == 63 {
            if expect != 0 { write("qmark: bad context\n"); st[3] = 1; return 0; }
            let rkind = ty_kind(st[8]);
            if rkind != 6 && rkind != 7 { write("qmark: bad function type\n"); st[3] = 1; return 0; }
            let ity = post[110000 + st[2] - 1];
            let ikind = ty_kind(ity);
            if ikind != rkind || ty_t1(ity) != ty_t1(st[8]) || ty_t2(ity) != ty_t2(st[8]) {
                write("qmark: type mismatch\n"); st[3] = 1; return 0;
            }
            push_post(post, st, 25, 0);
            set_ty(post, st, ty_t1(ity));
            // B5-9: an unboxed ref payload has no tracked lifetime -> keep it
            // maximally local so escapes are rejected instead of accepted.
            if (ty_t1(ity) >= 11 && ty_t1(ity) <= 15) { post[135802] = 1; }
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
                st[8] = ops[top - 1]; push_binop(src, post, st);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { st[8] = ops[top - 1]; push_binop(src, post, st); }
        top = top - 1;
    }
    return 0;
}

