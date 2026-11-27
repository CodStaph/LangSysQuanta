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

fn push_post(post: Slice[Int], st: Slice[Int], kind: Int, pval: Int) -> Int {
    post[st[2] * 2] = kind;
    post[st[2] * 2 + 1] = pval;
    if st[2] < 20000 {
        if kind == 2 { post[110000 + st[2]] = 1; }
        else { post[110000 + st[2]] = 0; }
    }
    st[2] = st[2] + 1;
    return 0;
}

fn set_ty(post: Slice[Int], st: Slice[Int], ty: Int) -> Int {
    if st[2] > 0 && st[2] <= 20000 { post[110000 + st[2] - 1] = ty; }
    return 0;
}

// Box the last argument expression for a generic function call.
fn box_last_arg(post: Slice[Int], st: Slice[Int]) -> Int {
    if st[2] <= 0 { return 0; }
    let aty = post[110000 + st[2] - 1];
    if aty == 0 { return 0; }
    // B4: a symbolic generic value is already a box (forwarding call).
    if aty >= 100 && aty < 108 { return 0; }
    let w = ty_width(aty);
    let blk = st[12];
    st[12] = st[12] + 8 + w * 8;
    push_post(post, st, 28, blk);
    set_ty(post, st, aty);
    return 0;
}

fn push_binop(src: Slice[U8], post: Slice[Int], st: Slice[Int]) -> Int {
    // The operator travels through st[8]: seeding caps a call at six argument
    // slots and the three slices above already take all of them.
    let op = st[8];
    let t1 = 0;
    let t2 = 0;
    if st[2] >= 2 {
        t1 = post[110000 + st[2] - 1];
        t2 = post[110000 + st[2] - 2];
    }
    if ((t1 >= 11 && t1 <= 15) || (t2 >= 11 && t2 <= 15)) {
        write("stage1: E-LS-UNSUPPORTED: ref value must be bound to a ref local before use\n");
        st[3] = 1;
        return 0;
    }
    // B5-12/B7: struct values compare through impl methods, not field loads.
    if (((t1 & 255) >= 30 && t1 < 100) || ((t2 & 255) >= 30 && t2 < 100)) {
        if op >= 6 && op <= 11 && t1 == t2 && t1 >= 30 && t1 < 100 {
            // B7: derive a method call from the impl registry; ==/!= need Eq,
            // the ordering ops need Ord.
            let wtc = 2;
            if op > 7 { wtc = 1; }
            let rs3 = 0;
            let rrow = 0 - 1;
            while rs3 < post[135748] {
                if post[135752 + rs3 * 4] == wtc && post[135753 + rs3 * 4] == t1 { rrow = rs3; }
                rs3 = rs3 + 1;
            }
            if rrow < 0 {
                write("stage1: E-LS-NO-IMPL: ");
                diag_pos(src, st[0] - 1, 0);
                write("struct comparison has no impl of Eq/Ord for this type\n");
                write("  fix-it: add an impl of Eq/Ord for this struct (fn eq/lt(ref a, ref b) -> Int)\n");
                st[3] = 1;
                return 0;
            }
            let mi = st[2];
            push_post(post, st, 93, post[135754 + rrow * 4]);
            post[100000 + mi] = op;
            set_ty(post, st, 1);
            // B7: return here - falling through to the generic/plain binop
            // path would append a second IR entry (kind 2 cmp) and make the
            // method call consume the stack twice.
            return 0;
        } else if op == 1 && t1 == t2 && t1 >= 30 && t1 < 100 {
            // R2.6-C: `p + q` dispatches to impl Add for the struct type.
            // The method is called with both addresses and must return Int
            // (the operator result type is Int in B-LS).
            let rs5 = 0;
            let rrow5 = 0 - 1;
            while rs5 < post[135748] {
                if post[135752 + rs5 * 4] == 4 && post[135753 + rs5 * 4] == t1 { rrow5 = rs5; }
                rs5 = rs5 + 1;
            }
            if rrow5 < 0 {
                write("stage1: E-LS-NO-IMPL: ");
                diag_pos(src, st[0] - 1, 0);
                write("struct addition has no impl of Add for this type\n");
                write("  fix-it: add an impl of Add for this struct (fn add(ref a, ref b) -> Int)\n");
                st[3] = 1;
                return 0;
            }
            let mi5 = st[2];
            push_post(post, st, 93, post[135754 + rrow5 * 4]);
            post[100000 + mi5] = 1;
            set_ty(post, st, 1);
            return 0;
        } else {
            write("stage1: E-LS-UNSUPPORTED: struct value must be used through its fields\n");
            st[3] = 1;
            return 0;
        }
    }
    // R4.3: direct Str/Slice `+` used to be an integer add; require the
    // fallible builtins (str_try_concat / concat_into) instead.
    if op == 1 && (t1 == 3 || t1 == 4 || t1 == 5 || t2 == 3 || t2 == 4 || t2 == 5) {
        write("stage1: E-LS-UNSUPPORTED: Str/Slice + needs str_try_concat or concat_into\n");
        st[3] = 1;
        return 0;
    }
    if (t1 >= 100 && t1 < 108) || (t2 >= 100 && t2 < 108) {
        if t1 != t2 { write("generic: type mismatch in operation\n"); st[3] = 1; return 0; }
        let bnd = post[133024 + st[4] * 8 + (t1 - 100)];
        if bnd == 1 {
            if op < 6 || op > 11 { write("stage1: E-LS-UNSUPPORTED: generic bound does not permit this operation\n"); st[3] = 1; return 0; }
        } else if bnd == 2 {
            if op != 6 && op != 7 { write("stage1: E-LS-UNSUPPORTED: generic bound does not permit this operation\n"); st[3] = 1; return 0; }
        } else if bnd == 4 {
            if op != 1 && (op < 6 || op > 11) { write("stage1: E-LS-UNSUPPORTED: generic bound does not permit this operation\n"); st[3] = 1; return 0; }
        } else if bnd == 3 {
            if op < 1 || op > 18 { write("stage1: E-LS-UNSUPPORTED: generic bound does not permit this operation\n"); st[3] = 1; return 0; }
        }
        let is_cmp = 0;
        if op >= 6 && op <= 11 { is_cmp = 1; }
        let blk = 0;
        if is_cmp == 0 { blk = st[12]; st[12] = st[12] + 32; }
        let mi = st[2];
        post[125500 + st[4]] = 1;
        if op == 1 { post[125501 + st[4]] = 1; }
        if op >= 2 && op <= 5 { post[125501 + st[4]] = 1; post[125502 + st[4]] = 1; }
        if op >= 12 && op <= 18 { post[125501 + st[4]] = 1; post[125502 + st[4]] = 1; }
        push_post(post, st, 30, blk);
        post[100000 + mi] = op;
        if is_cmp == 1 { set_ty(post, st, 1); }
        else { set_ty(post, st, t1); }
    } else {
        push_post(post, st, 2, op);
    }
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
            push_post(post, st, 0, v); set_ty(post, st, 1);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nid = name_id(src, st, post);
            let vi = var_find(post, nid, st[4], st[0]);
            if vi < 0 { st[3] = 1; return 0; }
            push_var_expect(post, st, vi);
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            paren = paren + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                st[8] = ops[top - 1]; push_binop(src, post, st);
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
            push_post(post, st, 0, v); set_ty(post, st, 1);
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
                    set_ty(post, st, elem_ty((post[4098 + ai * 3] >> 31) & 15));
                } else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 {
                        push_post(post, st, 11, si);
                        set_ty(post, st, elem_ty((post[66402 + si * 2] >> 31) & 15));
                    }
                    else { st[3] = 1; return 0; }
                }
            } else {
                let vi = var_find(post, nid, st[4], st[0]);
                if vi < 0 { st[3] = 1; return 0; }
                push_var_expect(post, st, vi);
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
                st[8] = ops[top - 1]; push_binop(src, post, st);
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
            push_post(post, st, 0, v); set_ty(post, st, 1);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nid = name_id(src, st, post);
            skip(src, st, n);
            if st[5] == 5 && st[0] - 5 >= 0 && src[st[0] - 5] == 69 && src[st[0] - 4] == 114 && src[st[0] - 3] == 114 && src[st[0] - 2] == 111 && src[st[0] - 1] == 114 && st[0] < n && src[st[0]] == 46 {
                // B5-12: `Error.Variant` payload constants (parse_index path).
                st[0] = st[0] + 1;
                skip(src, st, n);
                let vstart2 = st[0];
                let vn2 = name_id(src, st, post);
                if st[5] == 0 { write("error: bad Error variant
"); st[3] = 1; return 0; }
                let etag2 = 0;
                if st[5] == 4 && src[vstart2] == 70 && src[vstart2 + 1] == 117 && src[vstart2 + 2] == 108 && src[vstart2 + 3] == 108 { etag2 = 1; }
                else if st[5] == 8 && src[vstart2] == 78 && src[vstart2 + 1] == 111 && src[vstart2 + 2] == 116 && src[vstart2 + 3] == 70 && src[vstart2 + 4] == 111 && src[vstart2 + 5] == 117 && src[vstart2 + 6] == 110 && src[vstart2 + 7] == 100 { etag2 = 2; }
                else if st[5] == 10 && src[vstart2] == 73 && src[vstart2 + 1] == 110 && src[vstart2 + 2] == 118 && src[vstart2 + 3] == 97 && src[vstart2 + 4] == 108 && src[vstart2 + 5] == 105 && src[vstart2 + 6] == 100 && src[vstart2 + 7] == 67 && src[vstart2 + 8] == 97 && src[vstart2 + 9] == 112 { etag2 = 3; }
                else if st[5] == 11 && src[vstart2] == 79 && src[vstart2 + 1] == 117 && src[vstart2 + 2] == 116 && src[vstart2 + 3] == 79 && src[vstart2 + 4] == 102 && src[vstart2 + 5] == 77 && src[vstart2 + 6] == 101 && src[vstart2 + 7] == 109 && src[vstart2 + 8] == 111 && src[vstart2 + 9] == 114 && src[vstart2 + 10] == 121 { etag2 = 4; }
                else { write("error: unknown Error variant
"); st[3] = 1; return 0; }
                push_post(post, st, 0, etag2);
                set_ty(post, st, 20);
                expect = 0;
            } else if st[0] < n && src[st[0]] == 91 {
                st[0] = st[0] + 1;
                parse_index1(src, st, post);
                if st[3] != 0 { return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                let ai = arr_find(post, nid, st[4]);
                if ai >= 0 {
                    push_post(post, st, 10, ai);
                    set_ty(post, st, elem_ty((post[4098 + ai * 3] >> 31) & 15));
                } else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 {
                        push_post(post, st, 11, si);
                        set_ty(post, st, elem_ty((post[66402 + si * 2] >> 31) & 15));
                    }
                    else { st[3] = 1; return 0; }
                }
            } else {
                let vi = var_find(post, nid, st[4], st[0]);
                if vi >= 0 {
                    // R4.5: use the variable's real type so Buffer[Int] handles
                    // (type 9) survive parse_index (e.g. `Result.Ok(b)`).
                    push_var_expect(post, st, vi);
                } else if (st[10] & 255) >= 30 && sv_find(post, nid, st[4]) >= 0 {
                    // B5-12: struct payload -> one slot per field, retagged as
                    // the struct type so the ctor copies the right width.
                    let sv2 = sv_find(post, nid, st[4]);
                    let sid2 = post[6404 + sv2 * 4];
                    let sb2 = 5121 + sid2 * 18;
                    let sfc = post[sb2 + 1];
                    let sfi = 0;
                    while sfi < sfc {
                        let sfm = post[sb2 + 3 + sfi * 2];
                        push_post(post, st, 12, (post[6403 + sv2 * 4] & 2147483647) + (sfm & 2147483647));
                        set_ty(post, st, 1);
                        sfi = sfi + 1;
                    }
                    set_ty(post, st, st[10]);
                } else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 {
                        push_post(post, st, 13, si);
                        set_ty(post, st, slice_ty((post[66402 + si * 2] >> 31) & 15));
                    }
                    else {
                        let stri = str_find(post, nid, st[4]);
                        if stri < 0 { st[3] = 1; return 0; }
                        push_post(post, st, 19, stri);
                        set_ty(post, st, 3);
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
            while top > 0 && ops[top - 1] != 99 {
                st[8] = ops[top - 1]; push_binop(src, post, st);
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

fn arg_width(post: Slice[Int], start: Int, end: Int) -> Int {
    if end == start { return 0; }
    if end - start == 1 {
        let k = post[start * 2];
        if k == 13 || k == 23 || k == 78 { return 2; }
        if k == 19 || k == 77 { return 3; }
    }
    return 1;
}

// B4: find a declared function by name id (0..127).
fn fn_find_nid(post: Slice[Int], nm: Int) -> Int {
    let i = 0;
    while i < 128 {
        if post[135584 + i] == nm { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

// Bound capability check for a concrete or symbolic actual type.
//   1 Ord, 2 Eq, 3 Num, 4 Add
fn bound_covers(cb: Int, req: Int) -> Int {
    if cb == req { return 1; }
    if cb == 1 && (req == 2) { return 1; }
    if cb == 3 && (req == 1 || req == 2 || req == 4) { return 1; }
    if cb == 4 && (req == 2) { return 1; }
    return 0;
}

fn bound_ok(post: Slice[Int], at: Int, req: Int, fi: Int) -> Int {
    if at >= 100 && at < 108 {
        let cb = post[133024 + fi * 8 + (at - 100)];
        return bound_covers(cb, req);
    }
    if req >= 16 {
        // B7: a user-trait bound must be backed by an impl row on this type.
        let rs4 = 0;
        while rs4 < post[135748] {
            if post[135752 + rs4 * 4] == req && post[135753 + rs4 * 4] == at { return 1; }
            rs4 = rs4 + 1;
        }
        return 0;
    }
    if req == 3 { if at == 1 || at == 2 { return 1; } return 0; }
    if req == 4 { if at == 1 || at == 2 || at == 3 { return 1; } return 0; }
    if at >= 1 && at <= 5 { return 1; }
    if req == 5 { return 1; }
    return 0;
}

// B5-1: convert the last argument (a single Int variable) to an address.
// Returns 0 ok, -1 not a mutable Int variable, -2 val binding, -3 alias.
fn make_ref_arg(post: Slice[Int], st: Slice[Int], start: Int, ai: Int) -> Int {
    let rt = post[130700];
    let n = st[2] - start;
    let base = start * 2;
    let ci = 0;
    let cidx = 0;
    let cgrp = 0;
    if n == 1 {
        let kind = post[base];
        let idx = post[base + 1];
        if kind == 1 {
            let meta = post[50004 + idx * 4];
            if rt == 11 {
                if (meta & 255) != 1 { return 0 - 1; }
                if ((meta >> 8) & 1) == 1 { return 0 - 2; }
                ci = 74; cidx = idx; cgrp = 1;
            } else if rt == 15 {
                if (meta & 255) != 9 { return 0 - 1; }
                if ((meta >> 8) & 1) == 1 { return 0 - 2; }
                ci = 74; cidx = idx; cgrp = 1;
            } else { return 0 - 1; }
        } else if kind == 19 {
            if rt != 12 { return 0 - 1; }
            ci = 81; cidx = idx; cgrp = 2;
        } else if kind == 13 {
            let elem = (post[66402 + idx * 2] >> 31) & 15;
            if rt == 13 && elem == 1 { ci = 82; cidx = idx; cgrp = 3; }
            else if rt == 14 && elem == 8 { ci = 82; cidx = idx; cgrp = 3; }
            else { return 0 - 1; }
        } else if kind == 77 {
            if rt != 12 { return 0 - 1; }
            ci = 75; cidx = idx; cgrp = 1;
        } else if kind == 78 {
            if rt != 13 && rt != 14 { return 0 - 1; }
            ci = 75; cidx = idx; cgrp = 1;
        } else {
            return 0 - 1;
        }
        let k = 0;
        while k < base {
            let pk = post[k];
            if (pk == 74 || pk == 75) && cgrp == 1 && post[k + 1] == cidx { return 0 - 3; }
            if pk == 81 && cgrp == 2 && post[k + 1] == cidx { return 0 - 3; }
            if pk == 82 && cgrp == 3 && post[k + 1] == cidx { return 0 - 3; }
            k = k + 2;
        }
        // B5-8: propagate the lifetime of the borrowed place so a ref returned
        // by the callee cannot be laundered into a longer-lived location.
        let rl = 1;
        if kind == 1 { rl = (((post[50004 + idx * 4] >> 30) & 1048575) << 1) | 1; }
        else if kind == 19 { rl = (post[266336 + 1368] << 1) | 1; }
        else if kind == 13 { rl = (post[266336 + 1368] << 1) | 1; }
        else { rl = post[136000 + idx]; }
        rl_join(post, rl);
        post[base] = ci;
        set_ty(post, st, rt);
        return 0;
    }
    if n == 2 {
        if rt != 11 && rt != 15 { return 0 - 1; }
        if post[base] != 1 || post[base + 2] != 76 { return 0 - 1; }
        let idx = post[base + 1];
        let meta = post[50004 + idx * 4];
        if (meta & 255) != rt { return 0 - 1; }
        let k = 0;
        while k < base {
            let pk = post[k];
            if (pk == 74 || pk == 75) && post[k + 1] == idx { return 0 - 3; }
            k = k + 2;
        }
        rl_join(post, post[136000 + idx]);
        post[base] = 75;
        st[2] = start + 1;
        set_ty(post, st, rt);
        return 0;
    }
    return 0 - 1;
}

