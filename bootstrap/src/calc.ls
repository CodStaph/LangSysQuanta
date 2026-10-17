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

fn parse_expr(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let top = 0;
    let expect = 1;
    st[2] = 0;
    let n = st[1];
    while st[0] < n {
        skip(src, st, n);
        if st[0] >= n { break; }
        let c = src[st[0]];
        if c == 59 || c == 125 || c == 41 || c == 123 { break; }
        if c >= 48 && c <= 57 {
            let v = 0;
            while st[0] < n && src[st[0]] >= 48 && src[st[0]] <= 57 {
                v = v * 10 + (src[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            push_post(post, st, 0, v);
            expect = 0;
        } else if c >= 97 && c <= 122 {
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
            post[cst[3] + cst[2] * 2 + 1] = val * 8;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 80);
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
    let post: Array[Int, 4096] = Array.zeroed();
    let str_off: Array[Int, 64] = Array.zeroed();
    let str_len: Array[Int, 64] = Array.zeroed();
    let dpos: Array[Int, 64] = Array.zeroed();
    let st: Array[Int, 8] = Array.zeroed();
    let cs: Array[Int, 8] = Array.zeroed();
    let ck: Array[Int, 64] = Array.zeroed();
    let cje: Array[Int, 64] = Array.zeroed();
    let cstart: Array[Int, 64] = Array.zeroed();
    let cjmp: Array[Int, 64] = Array.zeroed();
    let cd = 0;
    let nstr = 0;
    let dlen = 208;
    let have_ret = 0;

    if argc() < 2 { write("calc: usage: stage1-calc <in> <out>\n"); return 2; }
    let plen = arg_len(0);
    let i = 0;
    while i < plen {
        path[i] = arg_byte(0, i);
        i = i + 1;
    }
    let inp: Slice[U8] = slice(path, 0, plen);
    let n = read_file(inp, src, 65536);
    if n <= 0 { write("calc: read failed\n"); return 3; }
    let olen = arg_len(1);
    i = 0;
    while i < olen {
        opath[i] = arg_byte(1, i);
        i = i + 1;
    }
    let oup: Slice[U8] = slice(opath, 0, olen);

    let srcs: Slice[U8] = slice(src, 0, n);
    let sts: Slice[Int] = slice(st, 0, 8);
    st[0] = 0; st[1] = n; st[3] = 0;

    if expect_char(srcs, sts, 102, n) == 0 { write("calc: expected fn\n"); return 4; }
    if expect_char(srcs, sts, 110, n) == 0 { write("calc: expected fn\n"); return 4; }
    if expect_char(srcs, sts, 109, n) == 0 { write("calc: expected main\n"); return 4; }
    if expect_char(srcs, sts, 97, n) == 0 { write("calc: expected main\n"); return 4; }
    if expect_char(srcs, sts, 105, n) == 0 { write("calc: expected main\n"); return 4; }
    if expect_char(srcs, sts, 110, n) == 0 { write("calc: expected main\n"); return 4; }
    if expect_char(srcs, sts, 40, n) == 0 { write("calc: expected (\n"); return 4; }
    if expect_char(srcs, sts, 41, n) == 0 { write("calc: expected )\n"); return 4; }
    if expect_char(srcs, sts, 45, n) == 0 { write("calc: expected ->\n"); return 4; }
    if expect_char(srcs, sts, 62, n) == 0 { write("calc: expected ->\n"); return 4; }
    if expect_char(srcs, sts, 73, n) == 0 { write("calc: expected Int\n"); return 4; }
    if expect_char(srcs, sts, 110, n) == 0 { write("calc: expected Int\n"); return 4; }
    if expect_char(srcs, sts, 116, n) == 0 { write("calc: expected Int\n"); return 4; }
    if expect_char(srcs, sts, 123, n) == 0 { write("calc: expected {\n"); return 4; }

    let c: Slice[U8] = slice(code, 0, 65536);
    let ps: Slice[Int] = slice(post, 0, 4096);
    let css: Slice[Int] = slice(cs, 0, 8);
    cs[0] = 0; cs[2] = 0; cs[3] = 2048;
    let done = 0;
    while done == 0 {
        skip(srcs, sts, n);
        if st[0] >= n { write("calc: eof\n"); return 4; }
        let ch = srcs[st[0]];
        if ch == 125 {
            if cd == 0 {
                st[0] = st[0] + 1;
                done = 1;
            } else {
                st[0] = st[0] + 1;
                let kind = ck[cd - 1];
                if kind == 1 {
                    skip(srcs, sts, n);
                    let is_else = st[0] + 4 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 115 && srcs[st[0] + 3] == 101;
                    if is_else {
                        patch_jump(c, cje[cd - 1], cs[0]);
                        let jp = emit_jmp(c, css);
                        cd = cd - 1;
                        ck[cd] = 2; cjmp[cd] = jp; cd = cd + 1;
                        st[0] = st[0] + 4;
                        if expect_char(srcs, sts, 123, n) == 0 { write("calc: expected {\n"); return 4; }
                    } else {
                        patch_jump(c, cje[cd - 1], cs[0]);
                        cd = cd - 1;
                    }
                } else if kind == 2 {
                    patch_jump(c, cjmp[cd - 1], cs[0]);
                    cd = cd - 1;
                } else {
                    let jp = emit_jmp(c, css);
                    patch_jump(c, jp, cstart[cd - 1]);
                    patch_jump(c, cje[cd - 1], cs[0]);
                    cd = cd - 1;
                }
            }
        } else if ch == 108 {
            st[0] = st[0] + 1;
            if expect_char(srcs, sts, 101, n) == 0 { write("calc: bad let\n"); return 4; }
            if expect_char(srcs, sts, 116, n) == 0 { write("calc: bad let\n"); return 4; }
            skip(srcs, sts, n);
            let vi = srcs[st[0]] - 97;
            st[0] = st[0] + 1;
            if expect_char(srcs, sts, 61, n) == 0 { write("calc: expected =\n"); return 4; }
            st[2] = 0;
            parse_expr(srcs, sts, ps);
            if st[3] != 0 { write("calc: bad expr\n"); return 4; }
            if expect_char(srcs, sts, 59, n) == 0 { write("calc: expected ;\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, css, ps);
            emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
            ps[cs[3] + cs[2] * 2] = cs[0];
            ps[cs[3] + cs[2] * 2 + 1] = vi * 8;
            cs[2] = cs[2] + 1;
            emit4(c, css, 0);
        } else if ch == 105 {
            if st[0] + 1 < n && srcs[st[0] + 1] == 102 {
                st[0] = st[0] + 2;
                st[2] = 0;
                parse_expr(srcs, sts, ps);
                if st[3] != 0 { write("calc: bad if\n"); return 4; }
                if expect_char(srcs, sts, 123, n) == 0 { write("calc: expected {\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, css, ps);
                emit1(c, css, 72); emit1(c, css, 133); emit1(c, css, 192);
                let jp = emit_je(c, css);
                if cd >= 64 { write("calc: too deep\n"); return 4; }
                ck[cd] = 1; cje[cd] = jp; cd = cd + 1;
            } else {
                let vi = ch - 97;
                st[0] = st[0] + 1;
                if expect_char(srcs, sts, 61, n) == 0 { write("calc: expected =\n"); return 4; }
                st[2] = 0;
                parse_expr(srcs, sts, ps);
                if st[3] != 0 { write("calc: bad expr\n"); return 4; }
                if expect_char(srcs, sts, 59, n) == 0 { write("calc: expected ;\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, css, ps);
                emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = vi * 8;
                cs[2] = cs[2] + 1;
                emit4(c, css, 0);
            }
        } else if ch == 119 {
            if st[0] + 1 < n && srcs[st[0] + 1] == 104 {
                st[0] = st[0] + 5;
                let start = cs[0];
                st[2] = 0;
                parse_expr(srcs, sts, ps);
                if st[3] != 0 { write("calc: bad while\n"); return 4; }
                if expect_char(srcs, sts, 123, n) == 0 { write("calc: expected {\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, css, ps);
                emit1(c, css, 72); emit1(c, css, 133); emit1(c, css, 192);
                let jp = emit_je(c, css);
                if cd >= 64 { write("calc: too deep\n"); return 4; }
                ck[cd] = 3; cstart[cd] = start; cje[cd] = jp; cd = cd + 1;
            } else {
                st[0] = st[0] + 5;
                if expect_char(srcs, sts, 40, n) == 0 { write("calc: bad write\n"); return 4; }
                if expect_char(srcs, sts, 34, n) == 0 { write("calc: bad string\n"); return 4; }
                let off = dlen;
                let len = 0;
                while st[0] < n && srcs[st[0]] != 34 {
                    let cc = srcs[st[0]];
                    if cc == 92 && st[0] + 1 < n {
                        st[0] = st[0] + 1;
                        cc = srcs[st[0]];
                        if cc == 110 { cc = 10; }
                        else if cc == 116 { cc = 9; }
                    }
                    data[dlen] = cc;
                    dlen = dlen + 1;
                    len = len + 1;
                    st[0] = st[0] + 1;
                }
                if expect_char(srcs, sts, 34, n) == 0 { write("calc: bad string\n"); return 4; }
                if expect_char(srcs, sts, 41, n) == 0 { write("calc: bad write\n"); return 4; }
                if expect_char(srcs, sts, 59, n) == 0 { write("calc: bad write\n"); return 4; }
                str_off[nstr] = off;
                str_len[nstr] = len;
                emit1(c, css, 184); emit4(c, css, 1);
                emit1(c, css, 191); emit4(c, css, 1);
                emit1(c, css, 72); emit1(c, css, 141); emit1(c, css, 53);
                dpos[nstr] = cs[0];
                emit4(c, css, 0);
                emit1(c, css, 186); emit4(c, css, len);
                emit1(c, css, 15); emit1(c, css, 5);
                nstr = nstr + 1;
            }
        } else if ch == 114 {
            st[0] = st[0] + 1;
            if expect_char(srcs, sts, 101, n) == 0 { write("calc: bad return\n"); return 4; }
            if expect_char(srcs, sts, 116, n) == 0 { write("calc: bad return\n"); return 4; }
            if expect_char(srcs, sts, 117, n) == 0 { write("calc: bad return\n"); return 4; }
            if expect_char(srcs, sts, 114, n) == 0 { write("calc: bad return\n"); return 4; }
            if expect_char(srcs, sts, 110, n) == 0 { write("calc: bad return\n"); return 4; }
            st[2] = 0;
            parse_expr(srcs, sts, ps);
            if st[3] != 0 { write("calc: bad expr\n"); return 4; }
            if expect_char(srcs, sts, 59, n) == 0 { write("calc: expected ;\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, css, ps);
            emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 199);
            emit1(c, css, 184); emit4(c, css, 60);
            emit1(c, css, 15); emit1(c, css, 5);
            have_ret = 1;
        } else {
            let vi = ch - 97;
            st[0] = st[0] + 1;
            if expect_char(srcs, sts, 61, n) == 0 { write("calc: expected =\n"); return 4; }
            st[2] = 0;
            parse_expr(srcs, sts, ps);
            if st[3] != 0 { write("calc: bad expr\n"); return 4; }
            if expect_char(srcs, sts, 59, n) == 0 { write("calc: expected ;\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, css, ps);
            emit1(c, css, 72); emit1(c, css, 137); emit1(c, css, 5);
            ps[cs[3] + cs[2] * 2] = cs[0];
            ps[cs[3] + cs[2] * 2 + 1] = vi * 8;
            cs[2] = cs[2] + 1;
            emit4(c, css, 0);
        }
    }
    if have_ret == 0 {
        emit1(c, css, 184); emit4(c, css, 60);
        emit1(c, css, 191); emit4(c, css, 0);
        emit1(c, css, 15); emit1(c, css, 5);
    }

    let clen = cs[0];
    let code_vaddr = 4194424;
    let data_vaddr = code_vaddr + clen;
    i = 0;
    while i < nstr {
        put32(c, dpos[i], data_vaddr + str_off[i] - (code_vaddr + dpos[i] + 4));
        i = i + 1;
    }
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
    put64(o, 24, code_vaddr); put64(o, 32, 64); put64(o, 40, 0);
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
    if write_file(oup, out, total) != 0 { write("calc: write failed\n"); return 5; }
    write("calc ok\n");
    return 0;
}
