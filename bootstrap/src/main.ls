// stage1 (B-LS): compile a tiny L-Sys subset to an x86_64 Linux ELF.
// M1c scope: `fn main() -> Int { write("..."); return N; }`.
// Usage: stage1 <input.ls> <output>

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

fn main() -> Int {
    let src: Array[U8, 65536] = Array.zeroed();
    let code: Array[U8, 65536] = Array.zeroed();
    let data: Array[U8, 65536] = Array.zeroed();
    let out: Array[U8, 131072] = Array.zeroed();
    let path: Array[U8, 256] = Array.zeroed();
    let opath: Array[U8, 256] = Array.zeroed();

    let str_off: Array[Int, 64] = Array.zeroed();
    let str_len: Array[Int, 64] = Array.zeroed();
    let dpos: Array[Int, 64] = Array.zeroed();

    let st: Array[Int, 8] = Array.zeroed();
    let cs: Array[Int, 8] = Array.zeroed();
    let css: Slice[Int] = slice(cs, 0, 8);
    let nstr = 0;
    let dlen = 0;
    let retval = 0;

    if argc() < 3 {
        write("stage1: usage: stage1 <input> <output>\n");
        return 2;
    }

    let plen = arg_len(1);
    let i = 0;
    while i < plen {
        path[i] = arg_byte(1, i);
        i = i + 1;
    }
    let inp: Slice[U8] = slice(path, 0, plen);
    let n = read_file(inp, src, 65536);
    if n <= 0 {
        write("stage1: cannot read input\n");
        return 3;
    }

    let olen = arg_len(2);
    i = 0;
    while i < olen {
        opath[i] = arg_byte(2, i);
        i = i + 1;
    }
    let oup: Slice[U8] = slice(opath, 0, olen);

    let srcs: Slice[U8] = slice(src, 0, n);
    let sts: Slice[Int] = slice(st, 0, 8);
    st[0] = 0;

    if expect_char(srcs, sts, 102, n) == 0 { write("stage1: expected fn\n"); return 4; }
    if expect_char(srcs, sts, 110, n) == 0 { write("stage1: expected fn\n"); return 4; }
    if expect_char(srcs, sts, 109, n) == 0 { write("stage1: expected main\n"); return 4; }
    if expect_char(srcs, sts, 97, n) == 0 { write("stage1: expected main\n"); return 4; }
    if expect_char(srcs, sts, 105, n) == 0 { write("stage1: expected main\n"); return 4; }
    if expect_char(srcs, sts, 110, n) == 0 { write("stage1: expected main\n"); return 4; }
    if expect_char(srcs, sts, 40, n) == 0 { write("stage1: expected (\n"); return 4; }
    if expect_char(srcs, sts, 41, n) == 0 { write("stage1: expected )\n"); return 4; }
    if expect_char(srcs, sts, 45, n) == 0 { write("stage1: expected ->\n"); return 4; }
    if expect_char(srcs, sts, 62, n) == 0 { write("stage1: expected ->\n"); return 4; }
    if expect_char(srcs, sts, 73, n) == 0 { write("stage1: expected Int\n"); return 4; }
    if expect_char(srcs, sts, 110, n) == 0 { write("stage1: expected Int\n"); return 4; }
    if expect_char(srcs, sts, 116, n) == 0 { write("stage1: expected Int\n"); return 4; }
    if expect_char(srcs, sts, 123, n) == 0 { write("stage1: expected {\n"); return 4; }

    let done = 0;
    while done == 0 {
        skip(srcs, sts, n);
        if st[0] >= n { write("stage1: unexpected eof\n"); return 4; }
        if srcs[st[0]] == 125 {
            st[0] = st[0] + 1;
            done = 1;
        } else if srcs[st[0]] == 119 {
            // write ( "..." ) ;
            st[0] = st[0] + 1;
            if expect_char(srcs, sts, 114, n) == 0 { write("stage1: bad write\n"); return 4; }
            if expect_char(srcs, sts, 105, n) == 0 { write("stage1: bad write\n"); return 4; }
            if expect_char(srcs, sts, 116, n) == 0 { write("stage1: bad write\n"); return 4; }
            if expect_char(srcs, sts, 101, n) == 0 { write("stage1: bad write\n"); return 4; }
            if expect_char(srcs, sts, 40, n) == 0 { write("stage1: bad write\n"); return 4; }
            if expect_char(srcs, sts, 34, n) == 0 { write("stage1: bad string\n"); return 4; }
            let off = dlen;
            let len = 0;
            while st[0] < n && srcs[st[0]] != 34 {
                let c = srcs[st[0]];
                if c == 92 && st[0] + 1 < n {
                    st[0] = st[0] + 1;
                    c = srcs[st[0]];
                    if c == 110 { c = 10; }
                    else if c == 116 { c = 9; }
                }
                data[dlen] = c;
                dlen = dlen + 1;
                len = len + 1;
                st[0] = st[0] + 1;
            }
            if expect_char(srcs, sts, 34, n) == 0 { write("stage1: bad string\n"); return 4; }
            if expect_char(srcs, sts, 41, n) == 0 { write("stage1: bad write\n"); return 4; }
            if expect_char(srcs, sts, 59, n) == 0 { write("stage1: bad write\n"); return 4; }
            str_off[nstr] = off;
            str_len[nstr] = len;
            nstr = nstr + 1;
        } else if srcs[st[0]] == 114 {
            // return N ;
            st[0] = st[0] + 1;
            if expect_char(srcs, sts, 101, n) == 0 { write("stage1: bad return\n"); return 4; }
            if expect_char(srcs, sts, 116, n) == 0 { write("stage1: bad return\n"); return 4; }
            if expect_char(srcs, sts, 117, n) == 0 { write("stage1: bad return\n"); return 4; }
            if expect_char(srcs, sts, 114, n) == 0 { write("stage1: bad return\n"); return 4; }
            if expect_char(srcs, sts, 110, n) == 0 { write("stage1: bad return\n"); return 4; }
            skip(srcs, sts, n);
            let v = 0;
            while st[0] < n && srcs[st[0]] >= 48 && srcs[st[0]] <= 57 {
                v = v * 10 + (srcs[st[0]] - 48);
                st[0] = st[0] + 1;
            }
            retval = v;
            if expect_char(srcs, sts, 59, n) == 0 { write("stage1: bad return\n"); return 4; }
        } else {
            write("stage1: unexpected statement\n");
            return 4;
        }
    }

    // ---- codegen ----
    let c: Slice[U8] = slice(code, 0, 65536);
    cs[0] = 0;
    let k = 0;
    while k < nstr {
        emit1(c, css, 184); emit4(c, css, 1);      // mov eax,1
        emit1(c, css, 191); emit4(c, css, 1);      // mov edi,1
        emit1(c, css, 72); emit1(c, css, 141); emit1(c, css, 53); // lea rsi,[rip+disp]
        dpos[k] = cs[0];
        emit4(c, css, 0);
        emit1(c, css, 186); emit4(c, css, str_len[k]); // mov edx,len
        emit1(c, css, 15); emit1(c, css, 5);       // syscall
        k = k + 1;
    }
    emit1(c, css, 184); emit4(c, css, 60);         // mov eax,60
    emit1(c, css, 191); emit4(c, css, retval);     // mov edi,retval
    emit1(c, css, 15); emit1(c, css, 5);           // syscall

    let clen = cs[0];
    let code_vaddr = 4194424; // 0x400000 + 120
    let data_vaddr = code_vaddr + clen;
    k = 0;
    while k < nstr {
        let instr_end = code_vaddr + dpos[k] + 4;
        let addr = data_vaddr + str_off[k];
        put32(c, dpos[k], addr - instr_end);
        k = k + 1;
    }

    let total = 120 + clen + dlen;
    let o: Slice[U8] = slice(out, 0, 131072);
    o[0] = 127; o[1] = 69; o[2] = 76; o[3] = 70; // \x7fELF
    o[4] = 2; o[5] = 1; o[6] = 1;
    put16(o, 16, 2);
    put16(o, 18, 62);
    put32(o, 20, 1);
    put64(o, 24, code_vaddr);
    put64(o, 32, 64);
    put64(o, 40, 0);
    put32(o, 48, 0);
    put16(o, 52, 64);
    put16(o, 54, 56);
    put16(o, 56, 1);
    put16(o, 58, 0);
    put16(o, 60, 0);
    put16(o, 62, 0);
    put32(o, 64, 1);
    put32(o, 68, 7);
    put64(o, 72, 0);
    put64(o, 80, 4194304); // 0x400000
    put64(o, 88, 4194304);
    put64(o, 96, total);
    put64(o, 104, total);
    put64(o, 112, 4096);

    let dst_code: Slice[U8] = slice(out, 120, clen);
    let src_code: Slice[U8] = slice(code, 0, clen);
    copy(dst_code, src_code, clen);
    let dst_data: Slice[U8] = slice(out, 120 + clen, dlen);
    let src_data: Slice[U8] = slice(data, 0, dlen);
    copy(dst_data, src_data, dlen);
    if write_file(oup, out, total) != 0 {
        write("stage1: cannot write output\n");
        return 5;
    }

    write("stage1 ok\n");
    return 0;
}
