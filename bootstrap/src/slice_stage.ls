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

fn parse_name(src: Slice[U8], st: Slice[Int], n: Int) -> Int {
    let nm = 0;
    let len = 0;
    while st[0] < n {
        let cc = src[st[0]];
        if (cc >= 97 && cc <= 122) || (cc >= 65 && cc <= 90) || (cc >= 48 && cc <= 57) || cc == 95 {
            if len < 8 { nm = nm | (cc << (len * 8)); }
            len = len + 1;
            st[0] = st[0] + 1;
        } else {
            break;
        }
    }
    st[5] = len;
    return nm;
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
fn parse_index(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let top = 0;
    let expect = 1;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 41 || c == 123 || c == 44 || c == 93 { break; }
        if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) {
            push_post(post, st, 1, c - 97);
            st[0] = st[0] + 1;
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            if top > 0 { top = top - 1; }
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
    let expect = 1;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 41 || c == 123 || c == 44 || c == 93 { break; }
        if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v);
            expect = 0;
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 {
            let name = 0;
            let len = 0;
            while st[0] < n {
                let cc = src[st[0]];
                if (cc >= 97 && cc <= 122) || (cc >= 65 && cc <= 90) || (cc >= 48 && cc <= 57) || cc == 95 {
                    if len < 8 { name = name | (cc << (len * 8)); }
                    len = len + 1;
                    st[0] = st[0] + 1;
                } else {
                    break;
                }
            }
            skip(src, st, n);
            if st[0] < n && src[st[0]] == 40 {
                st[0] = st[0] + 1;
                let slots = 0;
                while 1 {
                    skip(src, st, n);
                    if st[0] < n && src[st[0]] == 41 { st[0] = st[0] + 1; break; }
                    if st[0] >= n { st[3] = 1; return 0; }
                    let ac = src[st[0]];
                    if ac >= 48 && ac <= 57 {
                        let v = 0;
                        while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                            v = v * 10 + (src[st[0]] - 48);
                            st[0] = st[0] + 1;
                        }
                        push_post(post, st, 0, v);
                        slots = slots + 1;
                    } else if (ac >= 97 && ac <= 122) || (ac >= 65 && ac <= 90) {
                        let si = sl_find(post, ac, st[4]);
                        if si >= 0 {
                            push_post(post, st, 13, si);
                            slots = slots + 2;
                        } else {
                            push_post(post, st, 1, ac - 97);
                            slots = slots + 1;
                        }
                        st[0] = st[0] + 1;
                    } else {
                        st[3] = 1; return 0;
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
            } else if len == 1 {
                let si = sl_find(post, name, st[4]);
                if si >= 0 { push_post(post, st, 13, si); }
                else { push_post(post, st, 1, (name & 255) - 97); }
            } else {
                st[3] = 1; return 0;
            }
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                push_post(post, st, 2, ops[top - 1]);
                top = top - 1;
            }
            if top > 0 { top = top - 1; }
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
            post[cst[3] + cst[2] * 2 + 1] = cst[4] * 208 + val * 8;
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
    let src: Array[U8, 65536] = Array.zeroed();
    let code: Array[U8, 65536] = Array.zeroed();
    let data: Array[U8, 65536] = Array.zeroed();
    let out: Array[U8, 131072] = Array.zeroed();
    let path: Array[U8, 256] = Array.zeroed();
    let opath: Array[U8, 256] = Array.zeroed();
    let post: Array[Int, 8192] = Array.zeroed();
    let st: Array[Int, 16] = Array.zeroed();
    let cs: Array[Int, 8] = Array.zeroed();
    let fname: Array[Int, 16] = Array.zeroed();
    let flabel: Array[Int, 16] = Array.zeroed();
    let fparams: Array[Int, 16] = Array.zeroed();
    let fparamc: Array[Int, 16] = Array.zeroed();
    let fpelem: Array[Int, 16] = Array.zeroed();
    let nf = 0;
    let dlen = 3328;

    if argc() < 3 { write("slice: usage: stage1-slice <in> <out>\n"); return 2; }
    let plen = arg_len(1);
    let i = 0;
    while i < plen { path[i] = arg_byte(1, i); i = i + 1; }
    let inp: Slice[U8] = slice(path, 0, plen);
    let n = read_file(inp, src, 65536);
    if n <= 0 { write("slice: read failed\n"); return 3; }
    let olen = arg_len(2);
    i = 0;
    while i < olen { opath[i] = arg_byte(2, i); i = i + 1; }
    let oup: Slice[U8] = slice(opath, 0, olen);

    let srcs: Slice[U8] = slice(src, 0, n);
    let sts: Slice[Int] = slice(st, 0, 16);
    st[0] = 0; st[1] = n; st[3] = 0; st[4] = 0;

    let c: Slice[U8] = slice(code, 0, 65536);
    let ps: Slice[Int] = slice(post, 0, 8192);
    let css: Slice[Int] = slice(cs, 0, 8);
    cs[0] = 0; cs[2] = 0; cs[3] = 2048; cs[5] = 0; cs[6] = 3072;

    let done = 0;
    while done == 0 {
        skip(srcs, sts, n);
        if st[0] >= n { done = 1; }
        else {
            if expect_char(srcs, sts, 102, n) == 0 { write("slice: expected fn\n"); return 4; }
            if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected fn\n"); return 4; }
            skip(srcs, sts, n);
            let fnm = parse_name(srcs, sts, n);
            if st[5] == 0 { write("slice: bad name\n"); return 4; }
            if expect_char(srcs, sts, 40, n) == 0 { write("slice: expected (\n"); return 4; }
            let pc = 0;
            let ppacked = 0;
            let pebits = 0;
            while 1 {
                skip(srcs, sts, n);
                if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                if pc >= 6 { write("slice: too many params\n"); return 4; }
                let pch = srcs[st[0]];
                if pch < 97 || pch > 122 { write("slice: bad param\n"); return 4; }
                st[0] = st[0] + 1;
                ppacked = ppacked | (pch << (pc * 8));
                if expect_char(srcs, sts, 58, n) == 0 { write("slice: expected :\n"); return 4; }
                skip(srcs, sts, n);
                let pe = 0;
                if st[0] < n && srcs[st[0]] == 73 {
                    if expect_char(srcs, sts, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                    if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
                    pe = 0;
                } else if st[0] < n && srcs[st[0]] == 83 {
                    if expect_char(srcs, sts, 83, n) == 0 { write("slice: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 108, n) == 0 { write("slice: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 105, n) == 0 { write("slice: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 99, n) == 0 { write("slice: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("slice: expected Slice\n"); return 4; }
                    if expect_char(srcs, sts, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                    skip(srcs, sts, n);
                    if st[0] < n && srcs[st[0]] == 85 {
                        if expect_char(srcs, sts, 85, n) == 0 { write("slice: expected U8\n"); return 4; }
                        if expect_char(srcs, sts, 56, n) == 0 { write("slice: expected U8\n"); return 4; }
                        pe = 1;
                    } else {
                        if expect_char(srcs, sts, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                        if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                        if expect_char(srcs, sts, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
                        pe = 8;
                    }
                    if expect_char(srcs, sts, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                } else {
                    write("slice: unsupported param type\n"); return 4;
                }
                pebits = pebits | (pe << (pc * 4));
                pc = pc + 1;
                skip(srcs, sts, n);
                if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                else if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                else { write("slice: bad params\n"); return 4; }
            }
            if expect_char(srcs, sts, 45, n) == 0 { write("slice: expected ->\n"); return 4; }
            if expect_char(srcs, sts, 62, n) == 0 { write("slice: expected ->\n"); return 4; }
            if expect_char(srcs, sts, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
            if expect_char(srcs, sts, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
            if expect_char(srcs, sts, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
            if expect_char(srcs, sts, 123, n) == 0 { write("slice: expected {\n"); return 4; }

            if nf >= 16 { write("slice: too many functions\n"); return 4; }
            fname[nf] = fnm;
            flabel[nf] = cs[0];
            fparams[nf] = ppacked;
            fparamc[nf] = pc;
            fpelem[nf] = pebits;
            cs[4] = nf;
            st[4] = nf;

            // param stores, Slice uses two consecutive registers
            let reg = 0;
            i = 0;
            while i < pc {
                let pch = (ppacked >> (i * 8)) & 255;
                let pe = (pebits >> (i * 4)) & 15;
                if pe == 0 {
                    let off = nf * 208 + (pch - 97) * 8;
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
                    add_sl(ps, pch, soff | (pe << 20) | (nf << 24));
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
            while 1 {
                skip(srcs, sts, n);
                if st[0] >= n { write("slice: eof in body\n"); return 4; }
                if srcs[st[0]] == 125 { st[0] = st[0] + 1; break; }
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
                } else if srcs[st[0]] == 108 && st[0] + 1 < n && srcs[st[0] + 1] == 101 {
                    if expect_char(srcs, sts, 108, n) == 0 { write("slice: bad let\n"); return 4; }
                    if expect_char(srcs, sts, 101, n) == 0 { write("slice: bad let\n"); return 4; }
                    if expect_char(srcs, sts, 116, n) == 0 { write("slice: bad let\n"); return 4; }
                    skip(srcs, sts, n);
                    let vnm = parse_name(srcs, sts, n);
                    if st[5] == 0 { write("slice: bad let name\n"); return 4; }
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
                        let anm = parse_name(srcs, sts, n);
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
                        write("slice: unsupported let type\n"); return 4;
                    }
                } else {
                    let vnm = parse_name(srcs, sts, n);
                    if st[5] == 0 { write("slice: bad statement\n"); return 4; }
                    skip(srcs, sts, n);
                    if st[0] >= n || srcs[st[0]] != 91 { write("slice: expected [\n"); return 4; }
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
                }
            }
            if have_ret == 0 {
                emit1(c, css, 72); emit1(c, css, 49); emit1(c, css, 192);
                emit1(c, css, 195);
            }
            nf = nf + 1;
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
        if fname[i] == 1852399981 { main_found = 1; main_i = i; }
        i = i + 1;
    }
    if main_found == 0 { write("slice: missing main\n"); return 4; }
    let entry_off = cs[0];
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
    let o: Slice[U8] = slice(out, 0, 131072);
    o[0] = 127; o[1] = 69; o[2] = 76; o[3] = 70;
    o[4] = 2; o[5] = 1; o[6] = 1;
    put16(o, 16, 2); put16(o, 18, 62); put32(o, 20, 1);
    put64(o, 24, code_vaddr + entry_off); put64(o, 32, 64); put64(o, 40, 0);
    put32(o, 48, 0); put16(o, 52, 64); put16(o, 54, 56);
    put16(o, 56, 1); put16(o, 58, 0); put16(o, 60, 0); put16(o, 62, 0);
    put32(o, 64, 1); put32(o, 68, 7); put64(o, 72, 0);
    put64(o, 80, 4194304); put64(o, 88, 4194304);
    put64(o, 96, total); put64(o, 104, total); put64(o, 112, 4096);
    let dst_code: Slice[U8] = slice(out, 120, clen);
    let src_code: Slice[U8] = slice(code, 0, clen);
    copy(dst_code, src_code, clen);
    let dst_data: Slice[U8] = slice(out, 120 + clen, dlen);
    let src_data: Slice[U8] = slice(data, 0, dlen);
    copy(dst_data, src_data, dlen);
    if write_file(oup, out, total) != 0 { write("slice: write failed\n"); return 5; }
    write("slice ok\n");
    return 0;
}
