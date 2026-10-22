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

fn is_ident_byte(c: Int) -> Int {
    if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || (c >= 48 && c <= 57) || c == 95 || c >= 128 { return 1; }
    return 0;
}

fn kw_end(src: Slice[U8], pos: Int, n: Int) -> Int {
    if pos >= n { return 1; }
    if is_ident_byte(src[pos]) == 1 { return 0; }
    return 1;
}

// B0-lite: a single syntax preflight gate before parsing/emitting.  It is
// deliberately lexical: strings/comments are skipped, unsupported Stage-2
// keywords are rejected with a stable diagnostic before codegen starts.
fn preflight(src: Slice[U8], n: Int) -> Int {
    let i = 0;
    while i < n {
        let c = src[i];
        if c == 32 || c == 9 || c == 10 || c == 13 {
            i = i + 1;
        } else if c == 47 && i + 1 < n && src[i + 1] == 47 {
            i = i + 2;
            while i < n && src[i] != 10 { i = i + 1; }
        } else if c == 47 && i + 1 < n && src[i + 1] == 42 {
            i = i + 2;
            while i + 1 < n && (src[i] != 42 || src[i + 1] != 47) { i = i + 1; }
            if i + 1 < n { i = i + 2; }
        } else if c == 34 {
            i = i + 1;
            while i < n {
                if src[i] == 92 { i = i + 2; }
                else if src[i] == 34 { i = i + 1; break; }
                else { i = i + 1; }
            }
        } else if is_ident_byte(c) == 1 {
            let start = i;
            while i < n && is_ident_byte(src[i]) == 1 { i = i + 1; }
            let len = i - start;
                                    if len == 3 && src[start] == 101 && src[start + 1] == 102 && src[start + 2] == 102 {
                write("stage1: E-LS-UNSUPPORTED: eff(...) clauses are not implemented in B-LS yet\n");
                return 4;
            }
            if len == 8 && src[start] == 114 && src[start + 1] == 101 && src[start + 2] == 113 && src[start + 3] == 117 && src[start + 4] == 105 && src[start + 5] == 114 && src[start + 6] == 101 && src[start + 7] == 115 {
                write("stage1: E-LS-UNSUPPORTED: requires clauses are not implemented in B-LS yet\n");
                return 4;
            }
            if len == 7 && src[start] == 101 && src[start + 1] == 110 && src[start + 2] == 115 && src[start + 3] == 117 && src[start + 4] == 114 && src[start + 5] == 101 && src[start + 6] == 115 {
                write("stage1: E-LS-UNSUPPORTED: ensures clauses are not implemented in B-LS yet\n");
                return 4;
            }
            if len == 6 && src[start] == 66 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 {
                write("stage1: E-LS-UNSUPPORTED: Buffer[T] is not implemented in B-LS yet\n");
                return 4;
            }
        } else {
            i = i + 1;
        }
    }
    return 0;
}

// B0.2: function-level declaration table (front-end AST side table).
//
// Layout: 8 ints per function, `fd[0]` = count.
//   +0 name_start   +1 name_len    +2 nparams   +3 ret_code
//   +4 body_start   +5 body_end    +6 params_start  +7 params_end
//
// `ret_code`: 1 = Int, 2 = U8, 3 = Str, 9 = other/unknown (same codes the
// call site already uses via `post[30000+nid]`).
//
// The pipeline is now three passes, so parsing/checking no longer happens in
// the emit walk:
//   scan_funcs  — record declarations + body spans (this function);
//   check_decls — duplicates / main / limit + publish arity (`post`);
//   check_calls — verify call arity against the table before codegen.
// Emit still walks the source (that is B0's remaining debt), but it no longer
// owns the only copy of the signature table.
fn scan_funcs(src: Slice[U8], n: Int, fd: Slice[Int]) -> Int {
    let i = 0;
    let count = 0;
    while i < n {
        let c = src[i];
        if c == 32 || c == 9 || c == 10 || c == 13 {
            i = i + 1;
        } else if c == 47 && i + 1 < n && src[i + 1] == 47 {
            i = i + 2;
            while i < n && src[i] != 10 { i = i + 1; }
        } else if c == 47 && i + 1 < n && src[i + 1] == 42 {
            i = i + 2;
            while i + 1 < n && (src[i] != 42 || src[i + 1] != 47) { i = i + 1; }
            if i + 1 < n { i = i + 2; }
        } else if c == 34 {
            i = i + 1;
            while i < n {
                if src[i] == 92 { i = i + 2; }
                else if src[i] == 34 { i = i + 1; break; }
                else { i = i + 1; }
            }
        } else if is_ident_byte(c) == 1 {
            let start = i;
            while i < n && is_ident_byte(src[i]) == 1 { i = i + 1; }
            let len = i - start;
            if len == 2 && src[start] == 102 && src[start + 1] == 110 {
                if count >= 128 {
                    write("stage1: E-LS-FN-LIMIT: more than 128 functions\n");
                    return 4;
                }
                let p = i;
                while p < n && (src[p] == 32 || src[p] == 9 || src[p] == 10 || src[p] == 13) { p = p + 1; }
                if p < n && is_ident_byte(src[p]) == 1 {
                    let ns = p;
                    while p < n && is_ident_byte(src[p]) == 1 { p = p + 1; }
                    let nl = p - ns;
                    let q = p;
                    while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    // Generic parameter list `[T]` (skipped: B-LS erases it).
                    if q < n && src[q] == 91 {
                        let gd = 1;
                        q = q + 1;
                        while q < n && gd > 0 {
                            if src[q] == 91 { gd = gd + 1; }
                            else if src[q] == 93 { gd = gd - 1; }
                            q = q + 1;
                        }
                    }
                    while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    let pc = 0;
                    let pstart = 0;
                    let pend = 0;
                    if q < n && src[q] == 40 {
                        pstart = q + 1;
                        q = q + 1;
                        let ad = 0;
                        let commas = 0;
                        let any = 0;
                        while q < n {
                            let ch = src[q];
                            if ch == 91 {
                                ad = ad + 1;
                                q = q + 1;
                            } else if ch == 93 {
                                ad = ad - 1;
                                q = q + 1;
                            } else if ch == 41 && ad == 0 {
                                pend = q;
                                q = q + 1;
                                break;
                            } else if ch == 44 && ad == 0 {
                                commas = commas + 1;
                                q = q + 1;
                            } else {
                                if ch != 32 && ch != 9 && ch != 10 && ch != 13 { any = 1; }
                                q = q + 1;
                            }
                        }
                        if any == 1 { pc = commas + 1; }
                    }
                    let ret = 0;
                    let rp = q;
                    while rp < n && (src[rp] == 32 || src[rp] == 9 || src[rp] == 10 || src[rp] == 13) { rp = rp + 1; }
                    if rp + 1 < n && src[rp] == 45 && src[rp + 1] == 62 {
                        rp = rp + 2;
                        while rp < n && (src[rp] == 32 || src[rp] == 9 || src[rp] == 10 || src[rp] == 13) { rp = rp + 1; }
                        let rs = rp;
                        while rp < n && is_ident_byte(src[rp]) == 1 { rp = rp + 1; }
                        let rl = rp - rs;
                        if rl == 3 && src[rs] == 73 && src[rs + 1] == 110 && src[rs + 2] == 116 { ret = 1; }
                        else if rl == 2 && src[rs] == 85 && src[rs + 1] == 56 { ret = 2; }
                        else if rl == 3 && src[rs] == 83 && src[rs + 1] == 116 && src[rs + 2] == 114 { ret = 3; }
                        else { ret = 9; }
                    }
                    // Body span: find the first `{` after the parameters. Return
                    // types may be complex (`Option[U8]`, `Result[T,E]`, …), so
                    // do not start from the parsed return-type identifier.
                    let bstart = 0;
                    let bend = 0;
                    let lb = scan_until_lbrace(src, q, n);
                    if lb >= 0 {
                        bstart = lb;
                        let after = scan_block_end(src, lb, n);
                        if after >= 0 { bend = after; }
                    }
                    let base = 1 + count * 8;
                    fd[base] = ns;
                    fd[base + 1] = nl;
                    fd[base + 2] = pc;
                    fd[base + 3] = ret;
                    fd[base + 4] = bstart;
                    fd[base + 5] = bend;
                    fd[base + 6] = pstart;
                    fd[base + 7] = pend;
                    count = count + 1;
                }
            }
        } else {
            i = i + 1;
        }
    }
    fd[0] = count;
    return 0;
}

// Declaration-level checks on the table (no source re-scan for signatures).
fn check_decls(src: Slice[U8], fd: Slice[Int], post: Slice[Int]) -> Int {
    let count = fd[0];
    let nst: Array[Int, 16] = Array.zeroed();
    let nsts: Slice[Int] = slice(nst, 0, 16);
    let k = 0;
    while k < count {
        let base = 1 + k * 8;
        let ns = fd[base];
        let nl = fd[base + 1];
        let j = 0;
        while j < k {
            let obase = 1 + j * 8;
            if fd[obase + 1] == nl {
                let os = fd[obase];
                let same = 1;
                let t = 0;
                while t < nl {
                    if src[os + t] != src[ns + t] { same = 0; break; }
                    t = t + 1;
                }
                if same == 1 {
                    write("stage1: E-LS-DUP: duplicate function name\n");
                    return 4;
                }
            }
            j = j + 1;
        }
        let nid = name_id(src, nsts, post);
        post[30000 + nid] = fd[base + 2] + 1;
        if nl == 4 && src[ns] == 109 && src[ns + 1] == 97 && src[ns + 2] == 105 && src[ns + 3] == 110 {
            if fd[base + 2] != 0 {
                write("stage1: E-LS-MAIN: main must not take parameters\n");
                return 4;
            }
            if fd[base + 3] != 1 {
                write("stage1: E-LS-MAIN: main must return Int\n");
                return 4;
            }
        }
        k = k + 1;
    }
    return 0;
}

// Table lookup by name span; `-1` when the identifier is not a declared fn
// (builtins, enum variants, struct names, locals).
fn fd_find(src: Slice[U8], fd: Slice[Int], s: Int, l: Int) -> Int {
    let count = fd[0];
    let k = 0;
    while k < count {
        let base = 1 + k * 8;
        if fd[base + 1] == l {
            let os = fd[base];
            let same = 1;
            let j = 0;
            while j < l {
                if src[os + j] != src[s + j] { same = 0; break; }
                j = j + 1;
            }
            if same == 1 { return k; }
        }
        k = k + 1;
    }
    return 0 - 1;
}

// Call-site check, separated from emit: for every call to a declared function,
// the argument count must match the declaration (same message as the parser's
// late check, but reported before any code is generated).
fn check_calls(src: Slice[U8], fd: Slice[Int]) -> Int {
    let count = fd[0];
    let r = 0;
    while r < count {
        let base = 1 + r * 8;
        let bs = fd[base + 4];
        let be = fd[base + 5];
        let i = bs;
        while i < be {
            let c = src[i];
            if c == 32 || c == 9 || c == 10 || c == 13 {
                i = i + 1;
            } else if c == 47 && i + 1 < be && src[i + 1] == 47 {
                i = i + 2;
                while i < be && src[i] != 10 { i = i + 1; }
            } else if c == 47 && i + 1 < be && src[i + 1] == 42 {
                i = i + 2;
                while i + 1 < be && (src[i] != 42 || src[i + 1] != 47) { i = i + 1; }
                if i + 1 < be { i = i + 2; }
            } else if c == 34 {
                i = i + 1;
                while i < be {
                    if src[i] == 92 { i = i + 2; }
                    else if src[i] == 34 { i = i + 1; break; }
                    else { i = i + 1; }
                }
            } else if is_ident_byte(c) == 1 {
                let s = i;
                while i < be && is_ident_byte(src[i]) == 1 { i = i + 1; }
                let l = i - s;
                let k = fd_find(src, fd, s, l);
                if k >= 0 {
                    let q = i;
                    while q < be && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    if q < be && src[q] == 91 {
                        let gd = 1;
                        q = q + 1;
                        while q < be && gd > 0 {
                            if src[q] == 91 { gd = gd + 1; }
                            else if src[q] == 93 { gd = gd - 1; }
                            q = q + 1;
                        }
                    }
                    while q < be && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    if q < be && src[q] == 40 {
                        q = q + 1;
                        let d = 0;
                        let commas = 0;
                        let any = 0;
                        while q < be {
                            let ch = src[q];
                            if ch == 34 {
                                q = q + 1;
                                while q < be {
                                    if src[q] == 92 { q = q + 2; }
                                    else if src[q] == 34 { q = q + 1; break; }
                                    else { q = q + 1; }
                                }
                            } else if ch == 47 && q + 1 < be && src[q + 1] == 47 {
                                q = q + 2;
                                while q < be && src[q] != 10 { q = q + 1; }
                            } else if ch == 47 && q + 1 < be && src[q + 1] == 42 {
                                q = q + 2;
                                while q + 1 < be && (src[q] != 42 || src[q + 1] != 47) { q = q + 1; }
                                if q + 1 < be { q = q + 2; }
                            } else if ch == 40 || ch == 91 {
                                d = d + 1;
                                q = q + 1;
                            } else if ch == 41 && d == 0 {
                                q = q + 1;
                                break;
                            } else if ch == 93 && d == 0 {
                                q = q + 1;
                                break;
                            } else if ch == 41 || ch == 93 {
                                d = d - 1;
                                q = q + 1;
                            } else if ch == 44 && d == 0 {
                                commas = commas + 1;
                                q = q + 1;
                            } else {
                                if ch != 32 && ch != 9 && ch != 10 && ch != 13 { any = 1; }
                                q = q + 1;
                            }
                        }
                        let actual = 0;
                        if any == 1 { actual = commas + 1; }
                        let kbase = 1 + k * 8;
                        if actual != fd[kbase + 2] {
                            write("stage1: E-LS-ARITY: function call argument count mismatch\n");
                            return 4;
                        }
                    }
                }
            } else {
                i = i + 1;
            }
        }
        r = r + 1;
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
//   post[16000] = name count
//   post[16001] = bytes used in pool
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
// meta: off (bits 0..30) | elem << 31 | fn << 35 (7 bits) | len << 42
fn arr_find(post: Slice[Int], nm: Int, fnidx: Int) -> Int {
    let cnt = post[4096];
    let i = 0;
    while i < cnt {
        let meta = post[4098 + i * 2];
        if post[4097 + i * 2] == nm && ((meta >> 35) & 127) == fnidx {
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
        if post[4609 + i * 2] == nm && ((meta >> 35) & 127) == fnidx {
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

// Parse a concrete payload type: Int, U8, Str, Slice[U8], Slice[Int].
fn parse_ty(src: Slice[U8], st: Slice[Int], n: Int) -> Int {
    skip(src, st, n);
    if st[0] >= n { st[3] = 1; return 0; }
    let c = src[st[0]];
    if c == 66 && st[0] + 6 <= n && src[st[0] + 1] == 117 && src[st[0] + 2] == 102 && src[st[0] + 3] == 102 && src[st[0] + 4] == 101 && src[st[0] + 5] == 114 && kw_end(src, st[0] + 6, n) == 1 {
        write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
        st[3] = 1;
        return 0;
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
    st[3] = 1;
    return 0;
}

// Generic enum templates / instances (scalar payloads only).
// templates: [123000] count, entry 123001 + i*12
//   { name, nparams, nvariants, vname0, pty0, ..., vname3, pty3 }
// instances: [124000] count, entry 124001 + i*12
//   { tmpl, t1, t2, enidx, ... }
fn tmpl_find(post: Slice[Int], nm: Int) -> Int {
    let cnt = post[123000];
    let i = 0;
    while i < cnt {
        if post[123001 + i * 12] == nm { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn tmpl_add(post: Slice[Int], nm: Int, nparams: Int) -> Int {
    let c = post[123000];
    let base = 123001 + c * 12;
    post[base] = nm;
    post[base + 1] = nparams;
    post[base + 2] = 0;
    post[123000] = c + 1;
    return c;
}

fn tmpl_var_add(post: Slice[Int], ti: Int, vname: Int, pty: Int) -> Int {
    let base = 123001 + ti * 12;
    let n = post[base + 2];
    post[base + 3 + n * 2] = vname;
    post[base + 4 + n * 2] = pty;
    post[base + 2] = n + 1;
    return n;
}

fn tmpl_name(post: Slice[Int], ti: Int) -> Int {
    return post[123001 + ti * 12];
}

fn tmpl_nvariants(post: Slice[Int], ti: Int) -> Int {
    return post[123001 + ti * 12 + 2];
}

fn tmpl_var_name(post: Slice[Int], ti: Int, k: Int) -> Int {
    return post[123001 + ti * 12 + 3 + k * 2];
}

fn tmpl_var_pty(post: Slice[Int], ti: Int, k: Int) -> Int {
    return post[123001 + ti * 12 + 4 + k * 2];
}

fn inst_find(post: Slice[Int], ti: Int, t1: Int, t2: Int) -> Int {
    let cnt = post[124000];
    let i = 0;
    while i < cnt {
        let base = 124001 + i * 12;
        if post[base] == ti && post[base + 1] == t1 && post[base + 2] == t2 { return i; }
        i = i + 1;
    }
    return 0 - 1;
}

fn inst_tmpl(post: Slice[Int], ii: Int) -> Int {
    return post[124001 + ii * 12];
}

fn inst_nvariants(post: Slice[Int], ii: Int) -> Int {
    return post[124001 + ii * 12 + 3];
}

fn inst_var_name(post: Slice[Int], ii: Int, k: Int) -> Int {
    return post[124001 + ii * 12 + 4 + k * 2];
}

fn inst_var_pty(post: Slice[Int], ii: Int, k: Int) -> Int {
    return post[124001 + ii * 12 + 5 + k * 2];
}

fn inst_var_find(post: Slice[Int], ii: Int, vname: Int) -> Int {
    let n = inst_nvariants(post, ii);
    let k = 0;
    while k < n {
        if inst_var_name(post, ii, k) == vname { return k; }
        k = k + 1;
    }
    return 0 - 1;
}

fn mk_inst(post: Slice[Int], ti: Int, t1: Int, t2: Int) -> Int {
    let old = inst_find(post, ti, t1, t2);
    if old >= 0 { return old; }
    let n = tmpl_nvariants(post, ti);
    let c = post[124000];
    let base = 124001 + c * 12;
    post[base] = ti;
    post[base + 1] = t1;
    post[base + 2] = t2;
    post[base + 3] = n;
    let k = 0;
    while k < n {
        let pty = tmpl_var_pty(post, ti, k);
        if pty == 100 { pty = t1; }
        else if pty == 101 { pty = t2; }
        post[base + 4 + k * 2] = tmpl_var_name(post, ti, k);
        post[base + 5 + k * 2] = pty;
        k = k + 1;
    }
    post[124000] = c + 1;
    return c;
}

fn parse_user_desc(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let save = st[0];
    skip(src, st, st[1]);
    let nm = name_id(src, st, post);
    if st[5] == 0 { st[0] = save; return 0; }
    skip(src, st, st[1]);
    if st[0] >= st[1] || src[st[0]] != 91 { st[0] = save; return 0; }
    st[0] = st[0] + 1;
    let t1 = parse_ty(src, st, st[1]);
    if st[3] != 0 || t1 == 0 { return 0 - 1; }
    let t2 = 0;
    skip(src, st, st[1]);
    if st[0] < st[1] && src[st[0]] == 44 {
        st[0] = st[0] + 1;
        t2 = parse_ty(src, st, st[1]);
        if st[3] != 0 || t2 == 0 { return 0 - 1; }
    }
    if expect_char(src, st, 93, st[1]) == 0 { return 0 - 1; }
    let ti = tmpl_find(post, nm);
    if ti < 0 { return 0 - 1; }
    let ii = mk_inst(post, ti, t1, t2);
    if ii < 0 { return 0 - 1; }
    return 8 | (ii << 8);
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
    let w = ty_width(aty);
    let blk = st[12];
    st[12] = st[12] + 8 + w * 8;
    push_post(post, st, 28, blk);
    set_ty(post, st, aty);
    return 0;
}

fn push_binop(post: Slice[Int], st: Slice[Int], op: Int) -> Int {
    let t1 = 0;
    let t2 = 0;
    if st[2] >= 2 {
        t1 = post[110000 + st[2] - 1];
        t2 = post[110000 + st[2] - 2];
    }
    if t1 == 100 || t2 == 100 {
        if t1 != t2 { st[3] = 1; return 0; }
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
        else { set_ty(post, st, 100); }
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
            let vi = var_find(post, nid, st[4]);
            if vi < 0 { st[3] = 1; return 0; }
            push_post(post, st, 1, vi); set_ty(post, st, 1);
            expect = 0;
        } else if c == 40 {
            ops[top] = 99;
            top = top + 1;
            paren = paren + 1;
            st[0] = st[0] + 1;
            expect = 1;
        } else if c == 41 {
            while top > 0 && ops[top - 1] != 99 {
                push_binop(post, st, ops[top - 1]);
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
                push_binop(post, st, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_binop(post, st, ops[top - 1]); }
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
                    set_ty(post, st, elem_ty((post[4098 + ai * 2] >> 31) & 15));
                } else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 {
                        push_post(post, st, 11, si);
                        set_ty(post, st, elem_ty((post[4610 + si * 2] >> 31) & 15));
                    }
                    else { st[3] = 1; return 0; }
                }
            } else {
                let vi = var_find(post, nid, st[4]);
                if vi < 0 { st[3] = 1; return 0; }
                push_post(post, st, 1, vi); set_ty(post, st, 1);
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
                push_binop(post, st, ops[top - 1]);
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
                push_binop(post, st, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_binop(post, st, ops[top - 1]); }
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
            if st[0] < n && src[st[0]] == 91 {
                st[0] = st[0] + 1;
                parse_index1(src, st, post);
                if st[3] != 0 { return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                let ai = arr_find(post, nid, st[4]);
                if ai >= 0 {
                    push_post(post, st, 10, ai);
                    set_ty(post, st, elem_ty((post[4098 + ai * 2] >> 31) & 15));
                } else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 {
                        push_post(post, st, 11, si);
                        set_ty(post, st, elem_ty((post[4610 + si * 2] >> 31) & 15));
                    }
                    else { st[3] = 1; return 0; }
                }
            } else {
                let vi = var_find(post, nid, st[4]);
                if vi >= 0 { push_post(post, st, 1, vi); set_ty(post, st, 1); }
                else {
                    let si = sl_find(post, nid, st[4]);
                    if si >= 0 {
                        push_post(post, st, 13, si);
                        set_ty(post, st, slice_ty((post[4610 + si * 2] >> 31) & 15));
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
                push_binop(post, st, ops[top - 1]);
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
                push_binop(post, st, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_binop(post, st, ops[top - 1]); }
        top = top - 1;
    }
    return 0;
}

fn arg_width(post: Slice[Int], start: Int, end: Int) -> Int {
    if end == start { return 0; }
    if end - start == 1 {
        let k = post[start * 2];
        if k == 13 || k == 23 { return 2; }
        if k == 19 { return 3; }
    }
    return 1;
}

fn parse_expr(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let ops: Array[Int, 128] = Array.zeroed();
    let cname: Array[Int, 32] = Array.zeroed();
    let cnargs: Array[Int, 32] = Array.zeroed();
    let cargs: Array[Int, 32] = Array.zeroed();
    let cargstart: Array[Int, 32] = Array.zeroed();
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
                if ops[top - 1] != 99 { push_binop(post, st, ops[top - 1]); }
                top = top - 1;
            }
            if (post[120000 + cname[cdepth - 1]] & 1073741824) != 0 {
                if st[2] > cargstart[cdepth - 1] { box_last_arg(post, st); }
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
        } else if (c >= 97 && c <= 122) || (c >= 65 && c <= 90) || c == 95 || c >= 128 {
            let nstart = st[0];
            let name = name_id(src, st, post);
            let bcode = builtin_code(src, nstart, st[5]);
            skip(src, st, n);
            if st[0] < n && src[st[0]] == 40 && bcode != 0 {
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
                    let mi = st[2];
                    push_post(post, st, 31, 0);
                    post[100200 + mi] = boxA;
                    post[100201 + mi] = boxB;
                    post[100203 + mi] = boxOut;
                    post[100202 + mi] = ty1 | (bcode << 8);
                    set_ty(post, st, ty1);
                } else if bcode == 8 {
                    if expect_char(src, st, 41, n) == 0 { st[3] = 1; return 0; }
                    push_post(post, st, 32, 0);
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
                cdepth = cdepth + 1;
                ops[top] = 98;
                top = top + 1;
                paren = paren + 1;
                expect = 1;
            } else if st[0] < n && src[st[0]] == 91 {
                st[0] = st[0] + 1;
                parse_index(src, st, post);
                if st[3] != 0 { return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                let ai = arr_find(post, name, st[4]);
                if ai >= 0 {
                    push_post(post, st, 10, ai);
                    set_ty(post, st, elem_ty((post[4098 + ai * 2] >> 31) & 15));
                } else {
                    let si = sl_find(post, name, st[4]);
                    if si >= 0 {
                        push_post(post, st, 11, si);
                        set_ty(post, st, elem_ty((post[4610 + si * 2] >> 31) & 15));
                    }
                    else { st[3] = 1; return 0; }
                }
            } else if st[0] < n && src[st[0]] == 46 {
                st[0] = st[0] + 1;
                skip(src, st, n);
                let vf = name_id(src, st, post);
                if st[5] == 0 { st[3] = 1; return 0; }
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
                } else {
                let svi = sv_find(post, name, st[4]);
                if svi >= 0 {
                    let sidx = post[6404 + svi * 4];
                    let fi = st_field_find(post, sidx, vf);
                    if fi < 0 { st[3] = 1; return 0; }
                    let fb = 5121 + sidx * 18;
                    let fmeta = post[fb + 3 + fi * 2];
                    let off = post[6403 + svi * 4] + (fmeta & 2147483647);
                    let elem = (fmeta >> 31) & 15;
                    if elem == 8 { push_post(post, st, 12, off); set_ty(post, st, 1); }
                    else { push_post(post, st, 15, off); set_ty(post, st, 2); }
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
                    st[12] = st[12] + ty_size(pty);
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
            } else {
                let stri = str_find(post, name, st[4]);
                if stri >= 0 { push_post(post, st, 19, stri); set_ty(post, st, 3); }
                else {
                    let si = sl_find(post, name, st[4]);
                    if si >= 0 {
                        push_post(post, st, 13, si);
                        set_ty(post, st, slice_ty((post[4610 + si * 2] >> 31) & 15));
                    }
                    else {
                        let vi = var_find(post, name, st[4]);
                        if vi < 0 { st[3] = 1; return 0; }
                        let vty = post[9004 + vi * 4];
                        if vty == 0 { vty = 1; }
                        push_post(post, st, 1, vi);
                        set_ty(post, st, vty);
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
                push_binop(post, st, ops[top - 1]);
                top = top - 1;
            }
                if top > 0 && ops[top - 1] == 98 {
                    top = top - 1;
                    let fty = post[120000 + cname[cdepth - 1]];
                    if (fty & 1073741824) != 0 {
                        if st[2] > cargstart[cdepth - 1] { box_last_arg(post, st); }
                    }
                    let actual = cnargs[cdepth - 1];
                    if st[2] > cargstart[cdepth - 1] { actual = actual + 1; }
                    let declared = post[30000 + cname[cdepth - 1]];
                    if declared != 0 && declared - 1 != actual {
                        write("stage1: E-LS-ARITY: function call argument count mismatch\n");
                        st[3] = 1;
                        return 0;
                    }
                    cdepth = cdepth - 1;
                    let w = arg_width(post, cargstart[cdepth], st[2]);
                    cargs[cdepth] = cargs[cdepth] + w;
                    if (fty & 1073741824) != 0 {
                        let aty = 0;
                        if st[2] > 0 { aty = post[110000 + st[2] - 1]; }
                        if aty == 0 { write("fn: cannot infer generic argument\n"); st[3] = 1; return 0; }
                        if (fty & 268435456) != 0 {
                            let opok = 0;
                            if aty == 1 || aty == 2 { opok = 1; }
                            else if aty == 3 { if (fty & 67108864) == 0 { opok = 1; } }
                            else if aty == 4 || aty == 5 { if (fty & 134217728) == 0 { opok = 1; } }
                            if opok == 0 { write("fn: unsupported generic T operation\n"); st[3] = 1; return 0; }
                        }
                        if (fty & 536870912) != 0 {
                            push_post(post, st, 140 + cargs[cdepth], cname[cdepth]);
                            set_ty(post, st, aty);
                        } else {
                            push_post(post, st, 160 + cargs[cdepth], cname[cdepth]);
                            set_ty(post, st, fty & 16777215);
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
                push_binop(post, st, ops[top - 1]);
                top = top - 1;
            }
            ops[top] = op;
            top = top + 1;
            st[0] = st[0] + len;
            expect = 1;
        }
    }
    while top > 0 {
        if ops[top - 1] != 99 { push_binop(post, st, ops[top - 1]); }
        top = top - 1;
    }
    return 0;
}

fn emit_expr_a(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let val = post[cst[9] * 2 + 1];
    let done = 0;
    if kind == 0 {
        emit1(code, cst, 72); emit1(code, cst, 184);
        let k = 0;
        while k < 8 {
            emit1(code, cst, (val >> (k * 8)) & 255);
            k = k + 1;
        }
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 1 && done == 0 {
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = post[9003 + val * 4];
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if (kind == 10 || kind == 11) && done == 0 {
        let meta = 0;
        if kind == 10 { meta = post[4098 + val * 2]; }
        else { meta = post[4610 + val * 2]; }
        let off = meta & 2147483647;
        let elem = (meta >> 31) & 15;
        emit1(code, cst, 89);
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
        done = 1;
    }
    if kind == 13 && done == 0 {
        let meta = post[4610 + val * 2];
        let off = meta & 2147483647;
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
        done = 1;
    }
    if (kind == 12 || kind == 15) && done == 0 {
        if kind == 12 { emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5); }
        else { emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 5); }
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = val;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 18 && done == 0 {
        let meta = post[4098 + val * 2];
        let off = meta & 2147483647;
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = off;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 19 && done == 0 {
        let off = post[15003 + val * 4];
        let k = 0;
        while k < 3 {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = off + k * 8;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 80);
            k = k + 1;
        }
        done = 1;
    }
    if kind == 20 && done == 0 {
        let off = post[15003 + val * 4];
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = off + 16;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 23 && done == 0 {
        let off = post[15003 + val * 4];
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
        done = 1;
    }
    return done;
}

fn emit_expr_io(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let val = post[cst[9] * 2 + 1];
    let done = 0;
    if kind == 44 || kind == 45 {
        emit1(code, cst, 90);
        emit1(code, cst, 94);
        emit1(code, cst, 89);
        emit1(code, cst, 95);
        emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 240);
        emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 209);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 254);
        emit1(code, cst, 184); emit4(code, cst, 257);
        emit1(code, cst, 72); emit1(code, cst, 199); emit1(code, cst, 199); emit4(code, cst, 4294967196);
        if kind == 44 {
            emit1(code, cst, 49); emit1(code, cst, 210);
            emit1(code, cst, 69); emit1(code, cst, 49); emit1(code, cst, 210);
        } else {
            emit1(code, cst, 186); emit4(code, cst, 577);
            emit1(code, cst, 65); emit1(code, cst, 186); emit4(code, cst, 493);
        }
        emit1(code, cst, 15); emit1(code, cst, 5);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 199);
        let rkind = kind - 44;
        emit1(code, cst, 184); emit4(code, cst, 0 + rkind);
        emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 198);
        emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 202);
        emit1(code, cst, 15); emit1(code, cst, 5);
        emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 192);
        emit1(code, cst, 184); emit4(code, cst, 3);
        emit1(code, cst, 15); emit1(code, cst, 5);
        emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 192);
        emit1(code, cst, 80);
        done = 1;
    }
    return done;
}

fn emit_expr_b1(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let val = post[cst[9] * 2 + 1];
    let done = 0;
    if kind == 41 {
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = cst[7];
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    return done;
}

fn emit_expr_b2(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let val = post[cst[9] * 2 + 1];
    let done = 0;
    if kind == 42 {
        emit1(code, cst, 89);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = cst[7] + 8;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 200);
        emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 210);
        emit1(code, cst, 72); emit1(code, cst, 133); emit1(code, cst, 192);
        emit1(code, cst, 15); emit1(code, cst, 132);
        let p0 = cst[0];
        emit4(code, cst, 0);
        let loop0 = cst[0];
        emit1(code, cst, 128); emit1(code, cst, 60); emit1(code, cst, 16); emit1(code, cst, 0);
        emit1(code, cst, 15); emit1(code, cst, 132);
        let p1 = cst[0];
        emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 255); emit1(code, cst, 194);
        emit1(code, cst, 233);
        let p2 = cst[0];
        emit4(code, cst, 0);
        let end0 = cst[0];
        put32(code, p0, end0 - (p0 + 4));
        put32(code, p1, end0 - (p1 + 4));
        put32(code, p2, loop0 - (p2 + 4));
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 208);
        emit1(code, cst, 80);
        done = 1;
    }
    return done;
}

fn emit_expr_b3(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let val = post[cst[9] * 2 + 1];
    let done = 0;
    if kind == 43 {
        emit1(code, cst, 94);
        emit1(code, cst, 95);
        emit1(code, cst, 232);
        emit4(code, cst, cst[8] - (cst[0] + 4));
        emit1(code, cst, 80);
        done = 1;
    }
    return done;
}

fn emit_expr_b(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let h = emit_expr_b1(code, cst, post);
    if h == 0 { h = emit_expr_b2(code, cst, post); }
    if h == 0 { h = emit_expr_b3(code, cst, post); }
    return h;
}

fn emit_expr_c(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let val = post[cst[9] * 2 + 1];
    if kind == 24 {
        // Option.Some(v) / Result.Ok(v) / Result.Err(v): pack tag | (v << 8).
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 224); emit1(code, cst, 8);
        emit1(code, cst, 72); emit1(code, cst, 13);
        emit4(code, cst, val & 255);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 27 {
        let meta = post[100000 + cst[9]];
        let tag = meta & 255;
        let ty = (meta >> 8) & 255;
        if ty != 0 {
            let w = ty_width(ty);
            let k = w - 1;
            while k >= 0 {
                emit1(code, cst, 88);
                emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
                post[cst[3] + cst[2] * 2] = cst[0];
                post[cst[3] + cst[2] * 2 + 1] = val + 8 + k * 8;
                cst[2] = cst[2] + 1;
                emit4(code, cst, 0);
                k = k - 1;
            }
        }
        emit1(code, cst, 72); emit1(code, cst, 184);
        let k = 0;
        while k < 8 { emit1(code, cst, (tag >> (k * 8)) & 255); k = k + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = val;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = val;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 32 {
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 184); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 31 {
        let boxA = post[100200 + cst[9]];
        let boxB = post[100201 + cst[9]];
        let boxOut = post[100203 + cst[9]];
        let meta = post[100202 + cst[9]];
        let ty = meta & 255;
        let bcode = (meta >> 8) & 255;
        // Pop output slice (base, len).
        emit1(code, cst, 88); emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxOut + 16; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 88); emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxOut + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 184); emit1(code, cst, ty); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxOut; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        if bcode == 6 {
            emit1(code, cst, 88); emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxB + 16; cst[2] = cst[2] + 1; emit4(code, cst, 0);
            emit1(code, cst, 88); emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxB + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0);
            emit1(code, cst, 72); emit1(code, cst, 184); emit1(code, cst, ty); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0);
            emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxB; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        } else {
            emit1(code, cst, 88); emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxB + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0);
            emit1(code, cst, 72); emit1(code, cst, 184); emit1(code, cst, ty); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0);
            emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxB; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        }
        emit1(code, cst, 88); emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxA + 16; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 88); emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxA + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 184); emit1(code, cst, ty); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0); emit1(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxA; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxA; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxB; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxOut; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 186);
        if bcode == 6 { emit4(code, cst, 31); } else { emit4(code, cst, 32); }
        emit1(code, cst, 232);
        let callp = cst[0];
        emit4(code, cst, cst[15] - (callp + 4));
        emit1(code, cst, 80);
        emit1(code, cst, 82);
        return 0;
    }
    if kind == 30 {
        let op = post[100000 + cst[9]];
        let cmp = 0;
        if op >= 6 && op <= 11 { cmp = 1; }
        emit1(code, cst, 94);
        emit1(code, cst, 95);
        emit1(code, cst, 139); emit1(code, cst, 7);
        emit1(code, cst, 59); emit1(code, cst, 6);
        emit1(code, cst, 15); emit1(code, cst, 133);
        let tp1 = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 2);
        emit1(code, cst, 15); emit1(code, cst, 132);
        let ju8 = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 3);
        emit1(code, cst, 15); emit1(code, cst, 132);
        let jstr = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 4);
        emit1(code, cst, 15); emit1(code, cst, 132);
        let jsl4 = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 5);
        emit1(code, cst, 15); emit1(code, cst, 132);
        let jsl5 = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 1);
        emit1(code, cst, 15); emit1(code, cst, 133);
        let tp2 = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 76); emit1(code, cst, 139); emit1(code, cst, 71); emit1(code, cst, 8);
        emit1(code, cst, 76); emit1(code, cst, 139); emit1(code, cst, 78); emit1(code, cst, 8);
        emit1(code, cst, 233);
        let jop = cst[0]; emit4(code, cst, 0);
        let u8lbl = cst[0];
        patch_jump(code, ju8, u8lbl);
        emit1(code, cst, 68); emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 71); emit1(code, cst, 8);
        emit1(code, cst, 68); emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 78); emit1(code, cst, 8);
        let oplbl = cst[0];
        patch_jump(code, jop, oplbl);
        let tp3 = 0;
        let tp4 = 0;
        if op == 1 { emit1(code, cst, 77); emit1(code, cst, 1); emit1(code, cst, 200); }
        else if op == 2 { emit1(code, cst, 77); emit1(code, cst, 41); emit1(code, cst, 200); }
        else if op == 3 { emit1(code, cst, 77); emit1(code, cst, 15); emit1(code, cst, 175); emit1(code, cst, 193); }
        else if op == 4 || op == 5 {
            emit1(code, cst, 77); emit1(code, cst, 133); emit1(code, cst, 201);
            emit1(code, cst, 15); emit1(code, cst, 132);
            tp3 = cst[0]; emit4(code, cst, 0);
            emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 192);
            emit1(code, cst, 72); emit1(code, cst, 153);
            emit1(code, cst, 73); emit1(code, cst, 247); emit1(code, cst, 249);
            if op == 4 { emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 192); }
            else { emit1(code, cst, 73); emit1(code, cst, 137); emit1(code, cst, 208); }
        } else {
            emit1(code, cst, 49); emit1(code, cst, 192);
            emit1(code, cst, 77); emit1(code, cst, 57); emit1(code, cst, 200);
            if op == 6 { emit1(code, cst, 15); emit1(code, cst, 148); }
            else if op == 7 { emit1(code, cst, 15); emit1(code, cst, 149); }
            else if op == 8 { emit1(code, cst, 15); emit1(code, cst, 156); }
            else if op == 9 { emit1(code, cst, 15); emit1(code, cst, 158); }
            else if op == 10 { emit1(code, cst, 15); emit1(code, cst, 159); }
            else { emit1(code, cst, 15); emit1(code, cst, 157); }
            emit1(code, cst, 192);
            emit1(code, cst, 80);
        }
        if cmp == 0 {
            emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = val;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            emit1(code, cst, 139); emit1(code, cst, 7);
            emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 2);
            emit1(code, cst, 15); emit1(code, cst, 133);
            tp4 = cst[0]; emit4(code, cst, 0);
            emit1(code, cst, 73); emit1(code, cst, 129); emit1(code, cst, 224); emit4(code, cst, 255);
            let nomask = cst[0];
            patch_jump(code, tp4, nomask);
            emit1(code, cst, 137); emit1(code, cst, 1);
            emit1(code, cst, 76); emit1(code, cst, 137); emit1(code, cst, 65); emit1(code, cst, 8);
            emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 200);
            emit1(code, cst, 80);
        }
        emit1(code, cst, 233);
        let jdone = cst[0]; emit4(code, cst, 0);
        let strlbl = cst[0];
        patch_jump(code, jstr, strlbl);
        patch_jump(code, jsl4, strlbl);
        patch_jump(code, jsl5, strlbl);
        if cmp == 0 {
            emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = val;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
        } else {
            emit1(code, cst, 49); emit1(code, cst, 201);
        }
        emit1(code, cst, 76); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = post[17011];
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 76); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = post[17012];
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 186); emit4(code, cst, op);
        emit1(code, cst, 232);
        let strcall = cst[0];
        emit4(code, cst, cst[15] - (strcall + 4));
        emit1(code, cst, 80);
        emit1(code, cst, 233);
        let jstrdone = cst[0]; emit4(code, cst, 0);
        let traplbl = cst[0];
        patch_jump(code, tp1, traplbl);
        patch_jump(code, tp2, traplbl);
        if tp3 != 0 { patch_jump(code, tp3, traplbl); }
        emit1(code, cst, 184); emit4(code, cst, 60);
        emit1(code, cst, 191); emit4(code, cst, 70);
        emit1(code, cst, 15); emit1(code, cst, 5);
        let donelbl = cst[0];
        patch_jump(code, jstrdone, donelbl);
        patch_jump(code, jdone, donelbl);
        return 0;
    }
    if kind == 28 {
        let aty = post[110000 + cst[9]];
        let w = ty_width(aty);
        let k = w - 1;
        while k >= 0 {
            emit1(code, cst, 88);
            emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
            post[cst[3] + cst[2] * 2] = cst[0];
            post[cst[3] + cst[2] * 2 + 1] = val + 8 + k * 8;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            k = k - 1;
        }
        emit1(code, cst, 72); emit1(code, cst, 184);
        let b = 0;
        while b < 8 { emit1(code, cst, (aty >> (b * 8)) & 255); b = b + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = val;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = val;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind >= 160 {
        let nargs = kind - 160;
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
        emit1(code, cst, 80);
        return 0;
    }
    if kind >= 140 {
        let nargs = kind - 140;
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
        let ty = post[110000 + cst[9]];
        let w = ty_width(ty);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194);
        let k = 0;
        while k < w {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 66); emit1(code, cst, 8 + k * 8);
            emit1(code, cst, 80);
            k = k + 1;
        }
        return 0;
    }
    if kind == 25 {
        // expr?: the value is a pointer to a block [tag, payload...].
        let ity = post[110000 + cst[9] - 1];
        let ty = ty_t1(ity);
        emit1(code, cst, 88);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 8);
        emit1(code, cst, 131); emit1(code, cst, 249); emit1(code, cst, 0);
        let jp = emit_je(code, cst);
        emit_ret(code, cst);
        patch_jump(code, jp, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194);
        if ty == 3 {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 66); emit1(code, cst, 8);
            emit1(code, cst, 80);
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 66); emit1(code, cst, 16);
            emit1(code, cst, 80);
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 66); emit1(code, cst, 24);
            emit1(code, cst, 80);
        } else if ty == 4 || ty == 5 {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 66); emit1(code, cst, 8);
            emit1(code, cst, 80);
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 66); emit1(code, cst, 16);
            emit1(code, cst, 80);
        } else {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 66); emit1(code, cst, 8);
            emit1(code, cst, 80);
        }
        return 0;
    }
    if kind >= 3 {
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
        emit1(code, cst, 80);
        return 0;
    }
    if val == 20 {
        emit1(code, cst, 88);
        emit1(code, cst, 72); emit1(code, cst, 247); emit1(code, cst, 216);
        emit1(code, cst, 80);
        return 0;
    }
    emit1(code, cst, 89);
    emit1(code, cst, 88);
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
        // rax = lhs, rcx = rhs: normalize both, then combine truth values.
        emit1(code, cst, 72); emit1(code, cst, 133); emit1(code, cst, 192);
        emit1(code, cst, 15); emit1(code, cst, 149); emit1(code, cst, 192);
        emit1(code, cst, 72); emit1(code, cst, 133); emit1(code, cst, 201);
        emit1(code, cst, 15); emit1(code, cst, 149); emit1(code, cst, 193);
        if val == 13 { emit1(code, cst, 32); emit1(code, cst, 200); }
        else { emit1(code, cst, 8); emit1(code, cst, 200); }
        emit1(code, cst, 72); emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 192);
    } else if val == 14 { emit1(code, cst, 72); emit1(code, cst, 9); emit1(code, cst, 200); }
    else if val == 15 { emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 200); }
    else if val == 16 { emit1(code, cst, 72); emit1(code, cst, 33); emit1(code, cst, 200); }
    else if val == 17 { emit1(code, cst, 72); emit1(code, cst, 211); emit1(code, cst, 224); }
    else if val == 18 { emit1(code, cst, 72); emit1(code, cst, 211); emit1(code, cst, 248); }
    emit1(code, cst, 80);
    return 0;
}

fn emit_expr(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let i = 0;
    while i < cst[1] {
        cst[9] = i;
        let h = emit_expr_a(code, cst, post);
        if h == 0 { h = emit_expr_b(code, cst, post); }
        if h == 0 { h = emit_expr_io(code, cst, post); }
        if h == 0 { emit_expr_c(code, cst, post); }
        i = i + 1;
    }
    emit1(code, cst, 88);
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

// Every compiled function keeps a frame pointer so `?` can unwind any
// partially-evaluated expression stack before returning.
fn emit_ret(code: Slice[U8], cst: Slice[Int]) -> Int {
    emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 236);
    emit1(code, cst, 93);
    emit1(code, cst, 195);
    return 0;
}

// B0.3c: lexical block matcher. `pos` points at `{`; returns the position just
// after the matching `}`, or -1. Strings and comments are skipped.
fn scan_block_end(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos < 0 || pos >= end || src[pos] != 123 { return 0 - 1; }
    let d = 1;
    pos = pos + 1;
    while pos < end {
        let ch = src[pos];
        if ch == 34 {
            pos = pos + 1;
            while pos < end {
                if src[pos] == 92 { pos = pos + 2; }
                else if src[pos] == 34 { pos = pos + 1; break; }
                else { pos = pos + 1; }
            }
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 47 {
            pos = pos + 2;
            while pos < end && src[pos] != 10 { pos = pos + 1; }
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 42 {
            pos = pos + 2;
            while pos + 1 < end && (src[pos] != 42 || src[pos + 1] != 47) { pos = pos + 1; }
            if pos + 1 < end { pos = pos + 2; }
        } else if ch == 123 {
            d = d + 1;
            pos = pos + 1;
        } else if ch == 125 {
            d = d - 1;
            pos = pos + 1;
            if d == 0 { return pos; }
        } else {
            pos = pos + 1;
        }
    }
    return 0 - 1;
}

// B0.3c: statement-AST scanner helpers. These are lexical: they find statement
// boundaries, blocks, and keywords without parsing expressions.
fn scan_skip(src: Slice[U8], pos: Int, end: Int) -> Int {
    while pos < end {
        let ch = src[pos];
        if ch == 32 || ch == 9 || ch == 10 || ch == 13 {
            pos = pos + 1;
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 47 {
            pos = pos + 2;
            while pos < end && src[pos] != 10 { pos = pos + 1; }
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 42 {
            pos = pos + 2;
            while pos + 1 < end && (src[pos] != 42 || src[pos + 1] != 47) { pos = pos + 1; }
            if pos + 1 < end { pos = pos + 2; }
        } else {
            return pos;
        }
    }
    return pos;
}

fn scan_until_lbrace(src: Slice[U8], pos: Int, end: Int) -> Int {
    while pos < end {
        let ch = src[pos];
        if ch == 34 {
            pos = pos + 1;
            while pos < end {
                if src[pos] == 92 { pos = pos + 2; }
                else if src[pos] == 34 { pos = pos + 1; break; }
                else { pos = pos + 1; }
            }
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 47 {
            pos = pos + 2;
            while pos < end && src[pos] != 10 { pos = pos + 1; }
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 42 {
            pos = pos + 2;
            while pos + 1 < end && (src[pos] != 42 || src[pos + 1] != 47) { pos = pos + 1; }
            if pos + 1 < end { pos = pos + 2; }
        } else if ch == 123 {
            return pos;
        } else {
            pos = pos + 1;
        }
    }
    return 0 - 1;
}

fn scan_to_semi(src: Slice[U8], pos: Int, end: Int) -> Int {
    while pos < end {
        let ch = src[pos];
        if ch == 34 {
            pos = pos + 1;
            while pos < end {
                if src[pos] == 92 { pos = pos + 2; }
                else if src[pos] == 34 { pos = pos + 1; break; }
                else { pos = pos + 1; }
            }
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 47 {
            pos = pos + 2;
            while pos < end && src[pos] != 10 { pos = pos + 1; }
        } else if ch == 47 && pos + 1 < end && src[pos + 1] == 42 {
            pos = pos + 2;
            while pos + 1 < end && (src[pos] != 42 || src[pos + 1] != 47) { pos = pos + 1; }
            if pos + 1 < end { pos = pos + 2; }
        } else if ch == 59 {
            return pos + 1;
        } else if ch == 125 {
            return 0 - 1;
        } else {
            pos = pos + 1;
        }
    }
    return 0 - 1;
}

fn scan_is_if(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 1 < end && src[pos] == 105 && src[pos + 1] == 102 && kw_end(src, pos + 2, end) == 1 { return 1; }
    return 0;
}

fn scan_is_else(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 3 < end && src[pos] == 101 && src[pos + 1] == 108 && src[pos + 2] == 115 && src[pos + 3] == 101 && kw_end(src, pos + 4, end) == 1 { return 1; }
    return 0;
}

fn scan_is_while(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 4 < end && src[pos] == 119 && src[pos + 1] == 104 && src[pos + 2] == 105 && src[pos + 3] == 108 && src[pos + 4] == 101 && kw_end(src, pos + 5, end) == 1 { return 1; }
    return 0;
}

fn scan_is_match(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 4 < end && src[pos] == 109 && src[pos + 1] == 97 && src[pos + 2] == 116 && src[pos + 3] == 99 && src[pos + 4] == 104 && kw_end(src, pos + 5, end) == 1 { return 1; }
    return 0;
}

fn scan_is_region(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 5 < end && src[pos] == 114 && src[pos + 1] == 101 && src[pos + 2] == 103 && src[pos + 3] == 105 && src[pos + 4] == 111 && src[pos + 5] == 110 && kw_end(src, pos + 6, end) == 1 { return 1; }
    return 0;
}

fn scan_is_comptime(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 7 < end && src[pos] == 99 && src[pos + 1] == 111 && src[pos + 2] == 109 && src[pos + 3] == 112 && src[pos + 4] == 116 && src[pos + 5] == 105 && src[pos + 6] == 109 && src[pos + 7] == 101 && kw_end(src, pos + 8, end) == 1 { return 1; }
    return 0;
}

fn scan_is_break(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 4 < end && src[pos] == 98 && src[pos + 1] == 114 && src[pos + 2] == 101 && src[pos + 3] == 97 && src[pos + 4] == 107 && kw_end(src, pos + 5, end) == 1 { return 1; }
    return 0;
}

fn scan_is_continue(src: Slice[U8], pos: Int, end: Int) -> Int {
    if pos + 7 < end && src[pos] == 99 && src[pos + 1] == 111 && src[pos + 2] == 110 && src[pos + 3] == 116 && src[pos + 4] == 105 && src[pos + 5] == 110 && src[pos + 6] == 117 && src[pos + 7] == 101 && kw_end(src, pos + 8, end) == 1 { return 1; }
    return 0;
}

// Append one 6-int AST record. Fields:
//   +0 kind  +1 start  +2 end
//   +3 first_child  +4 next_sibling  +5 last_child
// `sast[0]` is the record count; records start at sast[257].
fn scan_add_node(sast: Slice[Int], kind: Int, start: Int, end: Int, parent: Int) -> Int {
    let child = sast[0];
    sast[0] = child + 1;
    let off = 257 + child * 6;
    sast[off] = kind;
    sast[off + 1] = start;
    sast[off + 2] = end;
    sast[off + 3] = 0 - 1;
    sast[off + 4] = 0 - 1;
    sast[off + 5] = 0 - 1;
    if parent >= 0 {
        let poff = 257 + parent * 6;
        let last = sast[poff + 5];
        if last < 0 { sast[poff + 3] = child; }
        else { sast[257 + last * 6 + 4] = child; }
        sast[poff + 5] = child;
    }
    return child;
}

// Build a statement tree for every function body. Kinds:
//   0 block, 1 if, 2 while, 3 region, 4 comptime,
//   5 break, 6 continue, 7 leaf/match.
fn scan_stmts(mem: Slice[U8], ps: Slice[Int], n: Int) -> Int {
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let fd: Slice[Int] = slice_at(ps, 140000, 1024);
    let sast: Slice[Int] = slice_at(ps, 141024, 57928);
    let K_BLOCK = 0;
    let K_IF = 1;
    let K_WHILE = 2;
    let K_REGION = 3;
    let K_COMPTIME = 4;
    let K_BREAK = 5;
    let K_CONTINUE = 6;
    let K_LEAF = 7;
    let bs: Array[Int, 256] = Array.zeroed();
    let be: Array[Int, 256] = Array.zeroed();
    let bp: Array[Int, 256] = Array.zeroed();
    let ifs: Array[Int, 64] = Array.zeroed();
    sast[0] = 0;
    let fi = 0;
    while fi < fd[0] {
        let base = 1 + fi * 8;
        let bstart = fd[base + 4];
        let bend = fd[base + 5];
        if bstart > 0 && bend > bstart {
            let root = scan_add_node(sast, K_BLOCK, bstart, bend, 0 - 1);
            sast[1 + fi * 2] = root;
            sast[2 + fi * 2] = 0;
            let bsp = 1;
            bs[0] = bstart + 1;
            be[0] = bend - 1;
            bp[0] = root;
            while bsp > 0 {
                bsp = bsp - 1;
                let parent = bp[bsp];
                let end = be[bsp];
                let p = scan_skip(srcs, bs[bsp], end);
                while p < end {
                    if sast[0] >= 9500 { write("stmts: too many statements\n"); return 4; }
                    if srcs[p] == 125 { break; }
                    if scan_is_if(srcs, p, end) == 1 {
                        let start = p;
                        let cp = scan_skip(srcs, p + 2, end);
                        let lb = scan_until_lbrace(srcs, cp, end);
                        if lb < 0 { write("stmts: expected {\n"); return 4; }
                        let after = scan_block_end(srcs, lb, end);
                        if after < 0 { write("stmts: bad block\n"); return 4; }
                        let cur_if = scan_add_node(sast, K_IF, start, 0, parent);
                        let nifs = 1;
                        ifs[0] = cur_if;
                        let blk = scan_add_node(sast, K_BLOCK, lb, after, cur_if);
                        if bsp >= 256 { write("stmts: too deep\n"); return 4; }
                        bs[bsp] = lb + 1; be[bsp] = after - 1; bp[bsp] = blk; bsp = bsp + 1;
                        p = scan_skip(srcs, after, end);
                        let done = 0;
                        while done == 0 {
                            if scan_is_else(srcs, p, end) == 1 {
                                p = scan_skip(srcs, p + 4, end);
                                if scan_is_if(srcs, p, end) == 1 {
                                    let nested = scan_add_node(sast, K_IF, p, 0, cur_if);
                                    if nifs >= 64 { write("stmts: too many else-if\n"); return 4; }
                                    ifs[nifs] = nested; nifs = nifs + 1;
                                    cur_if = nested;
                                    let cp2 = scan_skip(srcs, p + 2, end);
                                    let lb2 = scan_until_lbrace(srcs, cp2, end);
                                    if lb2 < 0 { write("stmts: expected {\n"); return 4; }
                                    let after2 = scan_block_end(srcs, lb2, end);
                                    if after2 < 0 { write("stmts: bad block\n"); return 4; }
                                    let blk2 = scan_add_node(sast, K_BLOCK, lb2, after2, cur_if);
                                    if bsp >= 256 { write("stmts: too deep\n"); return 4; }
                                    bs[bsp] = lb2 + 1; be[bsp] = after2 - 1; bp[bsp] = blk2; bsp = bsp + 1;
                                    p = scan_skip(srcs, after2, end);
                                } else {
                                    let lb2 = scan_until_lbrace(srcs, p, end);
                                    if lb2 < 0 { write("stmts: expected {\n"); return 4; }
                                    let after2 = scan_block_end(srcs, lb2, end);
                                    if after2 < 0 { write("stmts: bad block\n"); return 4; }
                                    let blk2 = scan_add_node(sast, K_BLOCK, lb2, after2, cur_if);
                                    if bsp >= 256 { write("stmts: too deep\n"); return 4; }
                                    bs[bsp] = lb2 + 1; be[bsp] = after2 - 1; bp[bsp] = blk2; bsp = bsp + 1;
                                    p = after2;
                                    done = 1;
                                }
                            } else {
                                done = 1;
                            }
                        }
                        let k = 0;
                        while k < nifs {
                            sast[257 + ifs[k] * 6 + 2] = p;
                            k = k + 1;
                        }
                    } else if scan_is_while(srcs, p, end) == 1 {
                        let start = p;
                        let cp = scan_skip(srcs, p + 5, end);
                        let lb = scan_until_lbrace(srcs, cp, end);
                        if lb < 0 { write("stmts: expected {\n"); return 4; }
                        let after = scan_block_end(srcs, lb, end);
                        if after < 0 { write("stmts: bad block\n"); return 4; }
                        let wn = scan_add_node(sast, K_WHILE, start, after, parent);
                        let blk = scan_add_node(sast, K_BLOCK, lb, after, wn);
                        if bsp >= 256 { write("stmts: too deep\n"); return 4; }
                        bs[bsp] = lb + 1; be[bsp] = after - 1; bp[bsp] = blk; bsp = bsp + 1;
                        p = after;
                    } else if scan_is_match(srcs, p, end) == 1 {
                        let start = p;
                        let cp = scan_skip(srcs, p + 5, end);
                        let lb = scan_until_lbrace(srcs, cp, end);
                        if lb < 0 { write("stmts: expected {\n"); return 4; }
                        let after = scan_block_end(srcs, lb, end);
                        if after < 0 { write("stmts: bad block\n"); return 4; }
                        scan_add_node(sast, K_LEAF, start, after, parent);
                        p = after;
                    } else if scan_is_region(srcs, p, end) == 1 {
                        let start = p;
                        let cp = scan_skip(srcs, p + 6, end);
                        let lb = scan_until_lbrace(srcs, cp, end);
                        if lb < 0 { write("stmts: expected {\n"); return 4; }
                        let after = scan_block_end(srcs, lb, end);
                        if after < 0 { write("stmts: bad block\n"); return 4; }
                        let rn = scan_add_node(sast, K_REGION, start, after, parent);
                        let blk = scan_add_node(sast, K_BLOCK, lb, after, rn);
                        if bsp >= 256 { write("stmts: too deep\n"); return 4; }
                        bs[bsp] = lb + 1; be[bsp] = after - 1; bp[bsp] = blk; bsp = bsp + 1;
                        p = after;
                    } else if scan_is_comptime(srcs, p, end) == 1 {
                        let start = p;
                        let cp = scan_skip(srcs, p + 8, end);
                        let lb = scan_until_lbrace(srcs, cp, end);
                        if lb < 0 { write("stmts: expected {\n"); return 4; }
                        let after = scan_block_end(srcs, lb, end);
                        if after < 0 { write("stmts: bad block\n"); return 4; }
                        let cn = scan_add_node(sast, K_COMPTIME, start, after, parent);
                        let blk = scan_add_node(sast, K_BLOCK, lb, after, cn);
                        if bsp >= 256 { write("stmts: too deep\n"); return 4; }
                        bs[bsp] = lb + 1; be[bsp] = after - 1; bp[bsp] = blk; bsp = bsp + 1;
                        p = after;
                    } else {
                        let start = p;
                        let epos = scan_to_semi(srcs, p, end);
                        if epos < 0 { write("stmts: expected ;\n"); return 4; }
                        let kind = K_LEAF;
                        if scan_is_break(srcs, p, end) == 1 { kind = K_BREAK; }
                        else if scan_is_continue(srcs, p, end) == 1 { kind = K_CONTINUE; }
                        scan_add_node(sast, kind, start, epos, parent);
                        p = epos;
                    }
                    p = scan_skip(srcs, p, end);
                }
            }
        }
        fi = fi + 1;
    }
    return 0;
}

// Emit one function body from the statement AST. The AST is walked with an
// explicit frame stack (no recursion: compiled functions use global slots).
fn emit_stmt_list(mem: Slice[U8], ps: Slice[Int], n: Int) -> Int {
    let ctxi: Slice[Int] = slice_at(ps, 198952, 2048);
    let st: Slice[Int] = slice_at(ctxi, 0, 16);
    let cs: Slice[Int] = slice_at(ctxi, 16, 16);
    let fname: Slice[Int] = slice_at(ctxi, 416, 128);
    let flabel: Slice[Int] = slice_at(ctxi, 544, 128);
    let fparams: Slice[Int] = slice_at(ctxi, 672, 16);
    let fpelem: Slice[Int] = slice_at(ctxi, 688, 16);
    let fret: Slice[Int] = slice_at(ctxi, 704, 128);
    let fret_t1: Slice[Int] = slice_at(ctxi, 832, 128);
    let fret_t2: Slice[Int] = slice_at(ctxi, 960, 128);
    let fret_ty: Slice[Int] = slice_at(ctxi, 1088, 128);
    let rname: Slice[Int] = slice_at(ctxi, 352, 64);
    let rlen: Slice[Int] = slice_at(ctxi, 1288, 64);
    let ck: Slice[Int] = slice_at(ctxi, 32, 64);
    let cje: Slice[Int] = slice_at(ctxi, 96, 64);
    let cstart: Slice[Int] = slice_at(ctxi, 160, 64);
    let cjmp: Slice[Int] = slice_at(ctxi, 1221, 64);
    let bpos: Slice[Int] = slice_at(ctxi, 288, 64);
    let bloop: Slice[Int] = slice_at(ctxi, 224, 64);
    let NF = 1216;
    let DLEN = 1217;
    let CD = 1218;
    let NBRK = 1219;
    let SPAN_START = 1285;
    let SPAN_END = 1286;
    let RDEPTH = 1287;
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let c: Slice[U8] = slice_at(mem, 294912, 1048576);
    let ds: Slice[U8] = slice_at(mem, 1343488, 65536);
    let sast: Slice[Int] = slice_at(ps, 141024, 57928);
    let K_BLOCK = 0;
    let K_IF = 1;
    let K_WHILE = 2;
    let K_REGION = 3;
    let K_COMPTIME = 4;
    let K_BREAK = 5;
    let K_CONTINUE = 6;
    let K_LEAF = 7;
    let root = sast[1 + ctxi[NF] * 2];
    if root < 0 { write("ast: missing function body\n"); return 4; }
    let fnodes: Array[Int, 256] = Array.zeroed();
    let fphase: Array[Int, 256] = Array.zeroed();
    let fd1: Array[Int, 256] = Array.zeroed();
    let fd2: Array[Int, 256] = Array.zeroed();
    let fchild: Array[Int, 256] = Array.zeroed();
    let sp = 0;
    fnodes[0] = root;
    fphase[0] = 0;
    fchild[0] = 0 - 1;
    fd1[0] = 0;
    fd2[0] = 0;
    sp = 1;
    while sp > 0 {
        let top = sp - 1;
        let node = fnodes[top];
        let noff = 257 + node * 6;
        let kind = sast[noff];
        if kind == K_COMPTIME {
            let cblk = sast[noff + 3];
            if cblk >= 0 && sast[257 + cblk * 6 + 3] >= 0 {
                write("stage1: E-LS-UNSUPPORTED: comptime blocks with non-empty bodies are not implemented in B-LS yet\n");
                return 4;
            }
            sp = sp - 1;
        } else if kind == K_REGION {
            if fphase[top] == 0 {
                let rp = scan_skip(srcs, sast[noff + 1] + 6, n);
                let rns = rp;
                while rp < n && is_ident_byte(srcs[rp]) == 1 { rp = rp + 1; }
                let rnl = rp - rns;
                if rnl == 0 { write("region: bad name\n"); return 4; }
                let rd = ctxi[RDEPTH];
                let rk = 0;
                let dup = 0;
                while rk < rd {
                    if rlen[rk] == rnl {
                        let same = 1;
                        let rj = 0;
                        while rj < rnl {
                            if srcs[rname[rk] + rj] != srcs[rns + rj] { same = 0; break; }
                            rj = rj + 1;
                        }
                        if same == 1 { dup = 1; break; }
                    }
                    rk = rk + 1;
                }
                if dup == 1 { write("region: duplicate active region name\n"); return 4; }
                if rd >= 64 { write("region: too deep\n"); return 4; }
                rname[rd] = rns;
                rlen[rd] = rnl;
                ctxi[RDEPTH] = rd + 1;
                fphase[top] = 1;
                let rblk = sast[noff + 3];
                if sp >= 256 { write("ast: too deep\n"); return 4; }
                fnodes[sp] = rblk; fphase[sp] = 0; fchild[sp] = 0 - 1; fd1[sp] = 0; fd2[sp] = 0; sp = sp + 1;
            } else {
                ctxi[RDEPTH] = ctxi[RDEPTH] - 1;
                sp = sp - 1;
            }
        } else if kind == K_BLOCK {
            if fphase[top] == 0 {
                fphase[top] = 1;
                fchild[top] = sast[noff + 3];
            }
            if fchild[top] >= 0 {
                let child = fchild[top];
                fchild[top] = sast[257 + child * 6 + 4];
                if sp >= 256 { write("ast: too deep\n"); return 4; }
                fnodes[sp] = child; fphase[sp] = 0; fchild[sp] = 0 - 1; fd1[sp] = 0; fd2[sp] = 0; sp = sp + 1;
            } else {
                sp = sp - 1;
            }
        } else if kind == K_IF {
            let then = sast[noff + 3];
            if then < 0 { write("ast: if without body\n"); return 4; }
            let cpos = scan_skip(srcs, sast[noff + 1] + 2, n);
            let cend = sast[257 + then * 6 + 1];
            if fphase[top] == 0 {
                st[0] = cpos; st[1] = cend; st[2] = 0; st[3] = 0; st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                st[1] = n;
                if st[3] != 0 { write("ctl: bad if expr\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 133); emit1(c, cs, 192);
                fd1[top] = emit_je(c, cs);
                fd2[top] = 0 - 1;
                fphase[top] = 1;
                if sp >= 256 { write("ast: too deep\n"); return 4; }
                fnodes[sp] = then; fphase[sp] = 0; fchild[sp] = 0 - 1; fd1[sp] = 0; fd2[sp] = 0; sp = sp + 1;
            } else if fphase[top] == 1 {
                let els = sast[257 + then * 6 + 4];
                if els >= 0 {
                    fd2[top] = emit_jmp(c, cs);
                    patch_jump(c, fd1[top], cs[0]);
                    fphase[top] = 2;
                    if sp >= 256 { write("ast: too deep\n"); return 4; }
                    fnodes[sp] = els; fphase[sp] = 0; fchild[sp] = 0 - 1; fd1[sp] = 0; fd2[sp] = 0; sp = sp + 1;
                } else {
                    patch_jump(c, fd1[top], cs[0]);
                    sp = sp - 1;
                }
            } else {
                patch_jump(c, fd2[top], cs[0]);
                sp = sp - 1;
            }
        } else if kind == K_WHILE {
            let body = sast[noff + 3];
            if body < 0 { write("ast: while without body\n"); return 4; }
            let cpos = scan_skip(srcs, sast[noff + 1] + 5, n);
            let cend = sast[257 + body * 6 + 1];
            if fphase[top] == 0 {
                let level = ctxi[CD];
                if level >= 64 { write("ctl: too deep\n"); return 4; }
                let lstart = cs[0];
                cstart[level] = lstart;
                ctxi[CD] = level + 1;
                st[0] = cpos; st[1] = cend; st[2] = 0; st[3] = 0; st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                st[1] = n;
                if st[3] != 0 { write("ctl: bad while expr\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 133); emit1(c, cs, 192);
                fd1[top] = emit_je(c, cs);
                fd2[top] = lstart;
                fphase[top] = 1;
                if sp >= 256 { write("ast: too deep\n"); return 4; }
                fnodes[sp] = body; fphase[sp] = 0; fchild[sp] = 0 - 1; fd1[sp] = 0; fd2[sp] = 0; sp = sp + 1;
            } else {
                let jp = emit_jmp(c, cs);
                patch_jump(c, jp, fd2[top]);
                let end_label = cs[0];
                patch_jump(c, fd1[top], end_label);
                let level = ctxi[CD] - 1;
                let w = 0;
                let k = 0;
                while k < ctxi[NBRK] {
                    if bloop[k] == level {
                        patch_jump(c, bpos[k], end_label);
                    } else {
                        bpos[w] = bpos[k];
                        bloop[w] = bloop[k];
                        w = w + 1;
                    }
                    k = k + 1;
                }
                ctxi[NBRK] = w;
                ctxi[CD] = level;
                sp = sp - 1;
            }
        } else if kind == K_BREAK {
            if ctxi[CD] == 0 { write("ctl: break outside loop\n"); return 4; }
            let jp = emit_jmp(c, cs);
            if ctxi[NBRK] >= 64 { write("ctl: too many breaks\n"); return 4; }
            bpos[ctxi[NBRK]] = jp;
            bloop[ctxi[NBRK]] = ctxi[CD] - 1;
            ctxi[NBRK] = ctxi[NBRK] + 1;
            sp = sp - 1;
        } else if kind == K_CONTINUE {
            if ctxi[CD] == 0 { write("ctl: continue outside loop\n"); return 4; }
            let jp = emit_jmp(c, cs);
            patch_jump(c, jp, cstart[ctxi[CD] - 1]);
            sp = sp - 1;
        } else {
            ctxi[SPAN_START] = sast[noff + 1];
            ctxi[SPAN_END] = sast[noff + 2];
            let er = emit_stmt_span(mem, ps, n);
            if er != 0 { return er; }
            sp = sp - 1;
        }
    }
    return 0;
}

fn emit_stmt_span(mem: Slice[U8], ps: Slice[Int], n: Int) -> Int {
    let ctxi: Slice[Int] = slice_at(ps, 198952, 2048);
    let st: Slice[Int] = slice_at(ctxi, 0, 16);
    let cs: Slice[Int] = slice_at(ctxi, 16, 16);
    let fname: Slice[Int] = slice_at(ctxi, 416, 128);
    let flabel: Slice[Int] = slice_at(ctxi, 544, 128);
    let fparams: Slice[Int] = slice_at(ctxi, 672, 16);
    let fpelem: Slice[Int] = slice_at(ctxi, 688, 16);
    let fret: Slice[Int] = slice_at(ctxi, 704, 128);
    let fret_t1: Slice[Int] = slice_at(ctxi, 832, 128);
    let fret_t2: Slice[Int] = slice_at(ctxi, 960, 128);
    let fret_ty: Slice[Int] = slice_at(ctxi, 1088, 128);
    let rname: Slice[Int] = slice_at(ctxi, 352, 64);
    let ck: Slice[Int] = slice_at(ctxi, 32, 64);
    let cje: Slice[Int] = slice_at(ctxi, 96, 64);
    let cstart: Slice[Int] = slice_at(ctxi, 160, 64);
    let cjmp: Slice[Int] = slice_at(ctxi, 1221, 64);
    let bpos: Slice[Int] = slice_at(ctxi, 288, 64);
    let bloop: Slice[Int] = slice_at(ctxi, 224, 64);
    let NF = 1216;
    let DLEN = 1217;
    let CD = 1218;
    let NBRK = 1219;
    let HAVE_RET = 1220;
    let SPAN_START = 1285;
    let SPAN_END = 1286;
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let c: Slice[U8] = slice_at(mem, 294912, 1048576);
    let ds: Slice[U8] = slice_at(mem, 1343488, 65536);
    st[0] = ctxi[SPAN_START];
    st[1] = n;
    st[3] = 0;
    while 1 {
        skip(srcs, st, n);
        if st[0] >= ctxi[SPAN_END] { break; }
        if st[0] >= n { write("slice: eof in body\n"); return 4; }
        if srcs[st[0]] == 125 {
            st[0] = st[0] + 1;
            if ctxi[CD] == 0 { break; }
            let kind = ck[ctxi[CD] - 1];
            let finished = 0;
            if kind == 1 {
                skip(srcs, st, n);
                let is_else = st[0] + 4 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 115 && srcs[st[0] + 3] == 101;
                if is_else {
                    st[0] = st[0] + 4;
                    skip(srcs, st, n);
                    let is_eif = st[0] + 1 < n && srcs[st[0]] == 105 && srcs[st[0] + 1] == 102;
                    let jp = emit_jmp(c, cs);
                    patch_jump(c, cje[ctxi[CD] - 1], cs[0]);
                    ctxi[CD] = ctxi[CD] - 1;
                    if is_eif {
                        if ctxi[CD] >= 64 { write("slice: too deep\n"); return 4; }
                        ck[ctxi[CD]] = 4; cjmp[ctxi[CD]] = jp; ctxi[CD] = ctxi[CD] + 1;
                    } else {
                        if ctxi[CD] >= 64 { write("slice: too deep\n"); return 4; }
                        ck[ctxi[CD]] = 2; cjmp[ctxi[CD]] = jp; ctxi[CD] = ctxi[CD] + 1;
                        if expect_char(srcs, st, 123, n) == 0 { write("slice: expected {\n"); return 4; }
                    }
                } else {
                    patch_jump(c, cje[ctxi[CD] - 1], cs[0]);
                    ctxi[CD] = ctxi[CD] - 1;
                    finished = 1;
                }
            } else if kind == 2 {
                patch_jump(c, cjmp[ctxi[CD] - 1], cs[0]);
                ctxi[CD] = ctxi[CD] - 1;
                finished = 1;
            } else if kind == 3 {
                let jp = emit_jmp(c, cs);
                patch_jump(c, jp, cstart[ctxi[CD] - 1]);
                patch_jump(c, cje[ctxi[CD] - 1], cs[0]);
                // Patch this loop's breaks, then drop them so later loops
                // at the same depth cannot re-patch stale break sites.
                let k = 0;
                let w = 0;
                while k < ctxi[NBRK] {
                    if bloop[k] == ctxi[CD] - 1 {
                        patch_jump(c, bpos[k], cs[0]);
                    } else {
                        bpos[w] = bpos[k];
                        bloop[w] = bloop[k];
                        w = w + 1;
                    }
                    k = k + 1;
                }
                ctxi[NBRK] = w;
                ctxi[CD] = ctxi[CD] - 1;
            } else if kind == 5 {
                ctxi[CD] = ctxi[CD] - 1;
                continue;
            } else {
                patch_jump(c, cjmp[ctxi[CD] - 1], cs[0]);
                ctxi[CD] = ctxi[CD] - 1;
                finished = 1;
            }
            if finished == 1 {
                while ctxi[CD] > 0 && ck[ctxi[CD] - 1] == 4 {
                    patch_jump(c, cjmp[ctxi[CD] - 1], cs[0]);
                    ctxi[CD] = ctxi[CD] - 1;
                }
            }
            continue;
        }
        if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
            write("stage1: E-LS-UNSUPPORTED: Buffer[T] expressions are not implemented in B-LS yet\n");
            return 4;
        }
        if srcs[st[0]] == 114 && st[0] + 6 <= n && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 103 && srcs[st[0] + 3] == 105 && srcs[st[0] + 4] == 111 && srcs[st[0] + 5] == 110 && kw_end(srcs, st[0] + 6, n) == 1 {
            if expect_char(srcs, st, 114, n) == 0 { write("region: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("region: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 103, n) == 0 { write("region: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 105, n) == 0 { write("region: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 111, n) == 0 { write("region: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 110, n) == 0 { write("region: bad keyword\n"); return 4; }
            skip(srcs, st, n);
            let rnm = name_id(srcs, st, ps);
            if st[5] == 0 { write("region: bad name\n"); return 4; }
            if expect_char(srcs, st, 123, n) == 0 { write("region: expected {\n"); return 4; }
            let rk = 0;
            let dup = 0;
            while rk < ctxi[CD] {
                if ck[rk] == 5 && rname[rk] == rnm { dup = 1; break; }
                rk = rk + 1;
            }
            if dup == 1 { write("region: duplicate active region name\n"); return 4; }
            if ctxi[CD] >= 64 { write("region: too deep\n"); return 4; }
            rname[ctxi[CD]] = rnm;
            ck[ctxi[CD]] = 5;
            ctxi[CD] = ctxi[CD] + 1;
            continue;
        }
        if srcs[st[0]] == 99 && st[0] + 8 <= n && srcs[st[0] + 1] == 111 && srcs[st[0] + 2] == 109 && srcs[st[0] + 3] == 112 && srcs[st[0] + 4] == 116 && srcs[st[0] + 5] == 105 && srcs[st[0] + 6] == 109 && srcs[st[0] + 7] == 101 && kw_end(srcs, st[0] + 8, n) == 1 {
            if expect_char(srcs, st, 99, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 111, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 109, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 112, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 116, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 105, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 109, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("comptime: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 123, n) == 0 { write("comptime: expected {\n"); return 4; }
            skip(srcs, st, n);
            if st[0] < n && srcs[st[0]] == 125 {
                st[0] = st[0] + 1;
            } else {
                write("stage1: E-LS-UNSUPPORTED: comptime blocks with non-empty bodies are not implemented in B-LS yet\n");
                return 4;
            }
            continue;
        }
        if srcs[st[0]] == 114 && st[0] + 5 < n && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 116 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 114 && srcs[st[0] + 5] == 110 {
            if expect_char(srcs, st, 114, n) == 0 { write("slice: bad return\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("slice: bad return\n"); return 4; }
            if expect_char(srcs, st, 116, n) == 0 { write("slice: bad return\n"); return 4; }
            if expect_char(srcs, st, 117, n) == 0 { write("slice: bad return\n"); return 4; }
            if expect_char(srcs, st, 114, n) == 0 { write("slice: bad return\n"); return 4; }
            if expect_char(srcs, st, 110, n) == 0 { write("slice: bad return\n"); return 4; }
            st[2] = 0;
            st[9] = fret_ty[ctxi[NF]]; st[10] = fret_t1[ctxi[NF]]; st[11] = fret_t2[ctxi[NF]];
            st[12] = ctxi[DLEN];
            parse_expr(srcs, st, ps);
            ctxi[DLEN] = st[12];
            st[9] = 0; st[10] = 0; st[11] = 0;
            if st[3] != 0 { write("slice: bad expr\n"); return 4; }
            if expect_char(srcs, st, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, cs, ps);
            emit_ret(c, cs);
            ctxi[HAVE_RET] = 1;
        } else if srcs[st[0]] == 105 && st[0] + 1 < n && srcs[st[0] + 1] == 102 && kw_end(srcs, st[0] + 2, n) == 1 {
            if expect_char(srcs, st, 105, n) == 0 { write("ctl: bad if\n"); return 4; }
            if expect_char(srcs, st, 102, n) == 0 { write("ctl: bad if\n"); return 4; }
            st[2] = 0;
            st[12] = ctxi[DLEN];
            parse_expr(srcs, st, ps);
            ctxi[DLEN] = st[12];
            if st[3] != 0 { write("ctl: bad if expr\n"); return 4; }
            if expect_char(srcs, st, 123, n) == 0 { write("ctl: expected {\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, cs, ps);
            emit1(c, cs, 72); emit1(c, cs, 133); emit1(c, cs, 192);
            let jp = emit_je(c, cs);
            if ctxi[CD] >= 64 { write("ctl: too deep\n"); return 4; }
            ck[ctxi[CD]] = 1; cje[ctxi[CD]] = jp; ctxi[CD] = ctxi[CD] + 1;
        } else if srcs[st[0]] == 119 && st[0] + 1 < n && srcs[st[0] + 1] == 104 && kw_end(srcs, st[0] + 5, n) == 1 {
            if expect_char(srcs, st, 119, n) == 0 { write("ctl: bad while\n"); return 4; }
            if expect_char(srcs, st, 104, n) == 0 { write("ctl: bad while\n"); return 4; }
            if expect_char(srcs, st, 105, n) == 0 { write("ctl: bad while\n"); return 4; }
            if expect_char(srcs, st, 108, n) == 0 { write("ctl: bad while\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("ctl: bad while\n"); return 4; }
            let wstart = cs[0];
            st[2] = 0;
            st[12] = ctxi[DLEN];
            parse_expr(srcs, st, ps);
            ctxi[DLEN] = st[12];
            if st[3] != 0 { write("ctl: bad while expr\n"); return 4; }
            if expect_char(srcs, st, 123, n) == 0 { write("ctl: expected {\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, cs, ps);
            emit1(c, cs, 72); emit1(c, cs, 133); emit1(c, cs, 192);
            let jp = emit_je(c, cs);
            if ctxi[CD] >= 64 { write("ctl: too deep\n"); return 4; }
            ck[ctxi[CD]] = 3; cstart[ctxi[CD]] = wstart; cje[ctxi[CD]] = jp; ctxi[CD] = ctxi[CD] + 1;
        } else if srcs[st[0]] == 98 && st[0] + 1 < n && srcs[st[0] + 1] == 114 && kw_end(srcs, st[0] + 5, n) == 1 {
            if expect_char(srcs, st, 98, n) == 0 { write("ctl: bad break\n"); return 4; }
            if expect_char(srcs, st, 114, n) == 0 { write("ctl: bad break\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("ctl: bad break\n"); return 4; }
            if expect_char(srcs, st, 97, n) == 0 { write("ctl: bad break\n"); return 4; }
            if expect_char(srcs, st, 107, n) == 0 { write("ctl: bad break\n"); return 4; }
            if expect_char(srcs, st, 59, n) == 0 { write("ctl: expected ;\n"); return 4; }
            let li = ctxi[CD] - 1;
            while li >= 0 && ck[li] != 3 { li = li - 1; }
            if li < 0 { write("ctl: break outside loop\n"); return 4; }
            let jp = emit_jmp(c, cs);
            if ctxi[NBRK] >= 64 { write("ctl: too many breaks\n"); return 4; }
            bpos[ctxi[NBRK]] = jp; bloop[ctxi[NBRK]] = li; ctxi[NBRK] = ctxi[NBRK] + 1;
        } else if srcs[st[0]] == 99 && st[0] + 7 < n && srcs[st[0] + 1] == 111 && srcs[st[0] + 2] == 110 && srcs[st[0] + 3] == 116 && srcs[st[0] + 4] == 105 && srcs[st[0] + 5] == 110 && srcs[st[0] + 6] == 117 && srcs[st[0] + 7] == 101 && kw_end(srcs, st[0] + 8, n) == 1 {
            if expect_char(srcs, st, 99, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 111, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 110, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 116, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 105, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 110, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 117, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("ctl: bad continue\n"); return 4; }
            if expect_char(srcs, st, 59, n) == 0 { write("ctl: expected ;\n"); return 4; }
            let li = ctxi[CD] - 1;
            while li >= 0 && ck[li] != 3 { li = li - 1; }
            if li < 0 { write("ctl: continue outside loop\n"); return 4; }
            let jp = emit_jmp(c, cs);
            patch_jump(c, jp, cstart[li]);
        } else if srcs[st[0]] == 119 && st[0] + 1 < n && srcs[st[0] + 1] == 114 && kw_end(srcs, st[0] + 5, n) == 1 {
            if expect_char(srcs, st, 119, n) == 0 { write("io: bad write\n"); return 4; }
            if expect_char(srcs, st, 114, n) == 0 { write("io: bad write\n"); return 4; }
            if expect_char(srcs, st, 105, n) == 0 { write("io: bad write\n"); return 4; }
            if expect_char(srcs, st, 116, n) == 0 { write("io: bad write\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("io: bad write\n"); return 4; }
            if expect_char(srcs, st, 40, n) == 0 { write("io: expected (\n"); return 4; }
            skip(srcs, st, n);
            if st[0] < n && srcs[st[0]] != 34 {
                let wn = name_id(srcs, st, ps);
                if st[5] == 0 { write("io: bad Str name\n"); return 4; }
                let wsi = str_find(ps, wn, ctxi[NF]);
                if wsi < 0 { write("io: unknown Str\n"); return 4; }
                let woff = ps[15003 + wsi * 4];
                if expect_char(srcs, st, 41, n) == 0 { write("io: expected )\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("io: expected ;\n"); return 4; }
                emit1(c, cs, 184); emit4(c, cs, 1);
                emit1(c, cs, 191); emit4(c, cs, 1);
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 53);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = woff;
                cs[2] = cs[2] + 1; emit4(c, cs, 0);
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = woff + 8;
                cs[2] = cs[2] + 1; emit4(c, cs, 0);
                emit1(c, cs, 15); emit1(c, cs, 5);
            } else {
            if expect_char(srcs, st, 34, n) == 0 { write("io: expected string\n"); return 4; }
            let soff = st[6];
            let ssz = 0;
            while st[0] < n && srcs[st[0]] != 34 {
                let cc = srcs[st[0]];
                if cc == 92 && st[0] + 1 < n {
                    st[0] = st[0] + 1;
                    cc = srcs[st[0]];
                    if cc == 110 { cc = 10; }
                    else if cc == 116 { cc = 9; }
                }
                ds[st[6]] = cc;
                st[6] = st[6] + 1;
                ssz = ssz + 1;
                st[0] = st[0] + 1;
            }
            if expect_char(srcs, st, 34, n) == 0 { write("io: bad string\n"); return 4; }
            if expect_char(srcs, st, 41, n) == 0 { write("io: expected )\n"); return 4; }
            if expect_char(srcs, st, 59, n) == 0 { write("io: expected ;\n"); return 4; }
            emit1(c, cs, 184); emit4(c, cs, 1);
            emit1(c, cs, 191); emit4(c, cs, 1);
            emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 53);
            ps[cs[3] + cs[2] * 2] = cs[0];
            ps[cs[3] + cs[2] * 2 + 1] = soff;
            cs[2] = cs[2] + 1;
            emit4(c, cs, 0);
            emit1(c, cs, 186); emit4(c, cs, ssz);
            emit1(c, cs, 15); emit1(c, cs, 5);
            }
        } else if srcs[st[0]] == 108 && st[0] + 2 < n && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 116 {
            if expect_char(srcs, st, 108, n) == 0 { write("slice: bad let\n"); return 4; }
            if expect_char(srcs, st, 101, n) == 0 { write("slice: bad let\n"); return 4; }
            if expect_char(srcs, st, 116, n) == 0 { write("slice: bad let\n"); return 4; }
            skip(srcs, st, n);
            let vnm = name_id(srcs, st, ps);
            if st[5] == 0 { write("slice: bad let name\n"); return 4; }
            skip(srcs, st, n);
            if st[0] >= n || srcs[st[0]] != 58 {
                // untyped let: string literal -> Str; otherwise Int slot.
                if expect_char(srcs, st, 61, n) == 0 { write("struct: expected =\n"); return 4; }
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 34 {
                    let soff = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 24;
                    str_add(ps, vnm, ctxi[NF], soff);
                    let slen = parse_str_lit(srcs, st, ds);
                    if st[3] != 0 { write("str: bad literal\n"); return 4; }
                    let chars = utf8_count(ds, st[7], slen);
                    emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = st[7];
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 184); emit4(c, cs, slen);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff + 8;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 184); emit4(c, cs, chars);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff + 16;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    if expect_char(srcs, st, 59, n) == 0 { write("str: expected ;\n"); return 4; }
                } else {
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("struct: bad let expr\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
                let rty = ps[110000 + st[2] - 1];
                let rkind = ty_kind(rty);
                cs[1] = st[2];
                if rkind == 8 {
                    let off = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 8;
                    let vii = ty_t1(rty);
                    opt_add(ps, vnm, ctxi[NF], 8 | (vii << 8), off);
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = off;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                } else if rkind == 6 || rkind == 7 {
                    let off = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 8;
                    if rkind == 6 { opt_add(ps, vnm, ctxi[NF], 1 | (ty_t1(rty) << 8), off); }
                    else { opt_add(ps, vnm, ctxi[NF], 2 | (ty_t1(rty) << 8) | (ty_t2(rty) << 16), off); }
                    emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                } else if rkind == 3 {
                    let off = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 24;
                    str_add(ps, vnm, ctxi[NF], off);
                    emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off + 16;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                    emit1(c, cs, 88);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off + 8;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                    emit1(c, cs, 88);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                } else if rkind == 4 || rkind == 5 {
                    let off = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 16;
                    let elem = 8;
                    if rkind == 4 { elem = 1; }
                    add_sl(ps, vnm, off | (elem << 31) | (ctxi[NF] << 35));
                    emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off + 8;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                    emit1(c, cs, 88);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                } else {
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    let vi = var_find(ps, vnm, ctxi[NF]);
                    let voff = 0;
                    if vi >= 0 { voff = ps[9003 + vi * 4]; }
                    else { voff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8; vi = var_add(ps, vnm, ctxi[NF], voff); }
                    if rty == 100 { ps[9004 + vi * 4] = 100; }
                    else { ps[9004 + vi * 4] = 1; }
                    ps[cs[3] + cs[2] * 2 + 1] = voff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                }
                }
            } else {
            if expect_char(srcs, st, 58, n) == 0 { write("slice: expected :\n"); return 4; }
            skip(srcs, st, n);
            if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet
");
                return 4;
            }
            if st[0] < n && srcs[st[0]] == 79 {
                if expect_char(srcs, st, 79, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 112, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 111, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("let: expected [\n"); return 4; }
                let t1 = parse_ty(srcs, st, n);
                if st[3] != 0 || t1 == 0 { write("let: bad Option type\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("let: expected ]\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("let: expected =\n"); return 4; }
                let voff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 8;
                opt_add(ps, vnm, ctxi[NF], 1 | (t1 << 8), voff);
                st[9] = mk_opt_ty(t1); st[10] = t1; st[11] = 0;
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("let: bad Option expr\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = voff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                st[9] = 0; st[10] = 0; st[11] = 0;
                if expect_char(srcs, st, 59, n) == 0 { write("let: expected ;\n"); return 4; }
            } else if st[0] < n && srcs[st[0]] == 82 {
                if expect_char(srcs, st, 82, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 115, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 117, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 108, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("let: expected [\n"); return 4; }
                let t1 = parse_ty(srcs, st, n);
                if st[3] != 0 || t1 == 0 { write("let: bad Result type\n"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("let: expected ,\n"); return 4; }
                let t2 = parse_ty(srcs, st, n);
                if st[3] != 0 || t2 == 0 { write("let: bad Result type\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("let: expected ]\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("let: expected =\n"); return 4; }
                let voff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 8;
                opt_add(ps, vnm, ctxi[NF], 2 | (t1 << 8) | (t2 << 16), voff);
                st[9] = mk_res_ty(t1, t2); st[10] = t1; st[11] = t2;
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("let: bad Result expr\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = voff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                st[9] = 0; st[10] = 0; st[11] = 0;
                if expect_char(srcs, st, 59, n) == 0 { write("let: expected ;\n"); return 4; }
            } else if st[0] < n && srcs[st[0]] == 83 && st[0] + 2 < n && srcs[st[0] + 1] == 116 && srcs[st[0] + 2] == 114 {
                if expect_char(srcs, st, 83, n) == 0 { write("str: expected Str\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("str: expected Str\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("str: expected Str\n"); return 4; }
                let soff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 24;
                str_add(ps, vnm, ctxi[NF], soff);
                if expect_char(srcs, st, 61, n) == 0 { write("str: expected =\n"); return 4; }
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 34 {
                    let slen = parse_str_lit(srcs, st, ds);
                    if st[3] != 0 { write("str: bad literal\n"); return 4; }
                    let chars = utf8_count(ds, st[7], slen);
                    emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = st[7];
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 184); emit4(c, cs, slen);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff + 8;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 184); emit4(c, cs, chars);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff + 16;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                } else {
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("str: bad let expr\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff + 16;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 88);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff + 8;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 88);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                }
                if expect_char(srcs, st, 59, n) == 0 { write("str: expected ;\n"); return 4; }
            } else if st[0] < n && srcs[st[0]] == 65 {
                if expect_char(srcs, st, 65, n) == 0 { write("slice: expected Array\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("slice: expected Array\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("slice: expected Array\n"); return 4; }
                if expect_char(srcs, st, 97, n) == 0 { write("slice: expected Array\n"); return 4; }
                if expect_char(srcs, st, 121, n) == 0 { write("slice: expected Array\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                skip(srcs, st, n);
                if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                    write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
                    return 4;
                }
                let elem = 0;
                if st[0] < n && srcs[st[0]] == 85 {
                    if expect_char(srcs, st, 85, n) == 0 { write("slice: expected U8\n"); return 4; }
                    if expect_char(srcs, st, 56, n) == 0 { write("slice: expected U8\n"); return 4; }
                    elem = 1;
                } else {
                    if expect_char(srcs, st, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
                    elem = 8;
                }
                if expect_char(srcs, st, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                skip(srcs, st, n);
                let cnt = 0;
                while st[0] < n && srcs[st[0]] >= 48 && srcs[st[0]] <= 57 {
                    cnt = cnt * 10 + (srcs[st[0]] - 48);
                    st[0] = st[0] + 1;
                }
                if expect_char(srcs, st, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("slice: expected =\n"); return 4; }
                if expect_char(srcs, st, 65, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 97, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 121, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 46, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 122, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 111, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 100, n) == 0 { write("slice: expected Array.zeroed\n"); return 4; }
                if expect_char(srcs, st, 40, n) == 0 { write("slice: expected (\n"); return 4; }
                if expect_char(srcs, st, 41, n) == 0 { write("slice: expected )\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                let aoff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + elem * cnt;
                add_arr(ps, vnm, aoff | (elem << 31) | (ctxi[NF] << 35) | (cnt << 42));
            } else if st[0] < n && srcs[st[0]] == 83 {
                if expect_char(srcs, st, 83, n) == 0 { write("slice: expected Slice\n"); return 4; }
                if expect_char(srcs, st, 108, n) == 0 { write("slice: expected Slice\n"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("slice: expected Slice\n"); return 4; }
                if expect_char(srcs, st, 99, n) == 0 { write("slice: expected Slice\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("slice: expected Slice\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                skip(srcs, st, n);
                if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                    write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
                    return 4;
                }
                let elem = 0;
                if st[0] < n && srcs[st[0]] == 85 {
                    if expect_char(srcs, st, 85, n) == 0 { write("slice: expected U8\n"); return 4; }
                    if expect_char(srcs, st, 56, n) == 0 { write("slice: expected U8\n"); return 4; }
                    elem = 1;
                } else {
                    if expect_char(srcs, st, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
                    elem = 8;
                }
                if expect_char(srcs, st, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("slice: expected =\n"); return 4; }
                skip(srcs, st, n);
                if st[0] + 7 < n && srcs[st[0]] == 115 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 105 && srcs[st[0] + 3] == 99 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 95 && srcs[st[0] + 6] == 97 && srcs[st[0] + 7] == 116 {
                // slice_at(src, off, len): sub-view; off is in elements.
                if expect_char(srcs, st, 115, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 108, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 99, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 95, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 97, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("slice_at: bad keyword
"); return 4; }
                if expect_char(srcs, st, 40, n) == 0 { write("slice_at: expected (
"); return 4; }
                skip(srcs, st, n);
                let snm = name_id(srcs, st, ps);
                if st[5] == 0 { write("slice_at: bad source name
"); return 4; }
                let sbase = 0;
                let ssi = sl_find(ps, snm, ctxi[NF]);
                if ssi >= 0 {
                    let smeta = ps[4610 + ssi * 2];
                    let selem = (smeta >> 31) & 15;
                    if selem != elem { write("slice_at: element size mismatch
"); return 4; }
                    sbase = smeta & 2147483647;
                } else {
                    let svi = str_find(ps, snm, ctxi[NF]);
                    if svi < 0 { write("slice_at: source is not a Slice or Str
"); return 4; }
                    if elem != 1 { write("slice_at: Str source needs Slice[U8]
"); return 4; }
                    sbase = ps[15003 + svi * 4];
                }
                if expect_char(srcs, st, 44, n) == 0 { write("slice_at: expected ,
"); return 4; }
                let soff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 16;
                add_sl(ps, vnm, soff | (elem << 31) | (ctxi[NF] << 35));
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("slice_at: bad offset
"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("slice_at: expected ,
"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                if elem == 8 {
                    emit1(c, cs, 72); emit1(c, cs, 193); emit1(c, cs, 224); emit1(c, cs, 3);
                }
                emit1(c, cs, 80); // push rax (off bytes)
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21); // mov rdx,[rip+src base]
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = sbase;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                emit1(c, cs, 88); // pop rax
                emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 208); // add rax,rdx
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = soff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("slice_at: bad length
"); return 4; }
                if expect_char(srcs, st, 41, n) == 0 { write("slice_at: expected )
"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("slice_at: expected ;
"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = soff + 8;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                } else if st[0] + 4 < n && srcs[st[0]] == 115 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 105 && srcs[st[0] + 3] == 99 && srcs[st[0] + 4] == 101 {
                if expect_char(srcs, st, 115, n) == 0 { write("slice: expected slice\n"); return 4; }
                if expect_char(srcs, st, 108, n) == 0 { write("slice: expected slice\n"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("slice: expected slice\n"); return 4; }
                if expect_char(srcs, st, 99, n) == 0 { write("slice: expected slice\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("slice: expected slice\n"); return 4; }
                if expect_char(srcs, st, 40, n) == 0 { write("slice: expected (\n"); return 4; }
                skip(srcs, st, n);
                let anm = name_id(srcs, st, ps);
                if st[5] == 0 { write("slice: bad array name\n"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                let ai = arr_find(ps, anm, ctxi[NF]);
                if ai < 0 { write("slice: unknown array\n"); return 4; }
                let ameta = ps[4098 + ai * 2];
                let aoff = ameta & 2147483647;
                let soff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 16;
                add_sl(ps, vnm, soff | (elem << 31) | (ctxi[NF] << 35));
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("slice: bad slice start\n"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 80); // start
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = aoff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                emit1(c, cs, 88); // start -> rax
                emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 208); // add rax,rdx
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = soff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("slice: bad slice len\n"); return 4; }
                if expect_char(srcs, st, 41, n) == 0 { write("slice: expected )\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = soff + 8;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                } else {
                    let soff = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 16;
                    add_sl(ps, vnm, soff | (elem << 31) | (ctxi[NF] << 35));
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("slice: bad slice expr\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff + 8;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                    emit1(c, cs, 88);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                    if expect_char(srcs, st, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                }
                } else {
                let save_pos = st[0];
                let ud = parse_user_desc(srcs, st, ps);
                if ud > 0 {
                    if expect_char(srcs, st, 61, n) == 0 { write("let: expected =\n"); return 4; }
                    let voff = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 8;
                    let vii = ty_t1(ud);
                    opt_add(ps, vnm, ctxi[NF], 8 | (vii << 8), voff);
                    st[9] = ud; st[10] = 0; st[11] = 0;
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("let: bad generic expr\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = voff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                    st[9] = 0; st[10] = 0; st[11] = 0;
                    if expect_char(srcs, st, 59, n) == 0 { write("let: expected ;\n"); return 4; }
                } else {
                    st[0] = save_pos;
                let tnm = name_id(srcs, st, ps);
                if st[5] == 0 { write("struct: bad type\n"); return 4; }
                let si = st_find(ps, tnm);
                if si < 0 { write("struct: unknown type\n"); return 4; }
                let sz = st_size(ps, si);
                let soff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + sz;
                sv_add(ps, vnm, ctxi[NF], soff, si);
                if expect_char(srcs, st, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
            }
                }
            }
        } else if srcs[st[0]] == 109 && st[0] + 4 < n && srcs[st[0] + 1] == 97 && srcs[st[0] + 2] == 116 && srcs[st[0] + 3] == 99 && srcs[st[0] + 4] == 104 {
            // match (tag + optional Int payload binding); each arm is
            // `Variant [ (name) ] => { return expr; }`.
            if expect_char(srcs, st, 109, n) == 0 { write("match: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 97, n) == 0 { write("match: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 116, n) == 0 { write("match: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 99, n) == 0 { write("match: bad keyword\n"); return 4; }
            if expect_char(srcs, st, 104, n) == 0 { write("match: bad keyword\n"); return 4; }
            skip(srcs, st, n);
            let mnm = name_id(srcs, st, ps);
            if st[5] == 0 { write("match: bad subject\n"); return 4; }
            let ovi = opt_find(ps, mnm, ctxi[NF]);
            if ovi >= 0 {
                let obase = 90001 + ovi * 6;
                let ometa = ps[obase + 2];
                let okind = ometa & 255;
                let ot1 = (ometa >> 8) & 255;
                let ot2 = (ometa >> 16) & 255;
                let moff = ps[obase + 5];
                if expect_char(srcs, st, 123, n) == 0 { write("match: expected {\n"); return 4; }
                while 1 {
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 125 { break; }
                    let enm = name_id(srcs, st, ps);
                    if st[5] == 0 { write("match: bad type\n"); return 4; }
                    if expect_char(srcs, st, 46, n) == 0 { write("match: expected .\n"); return 4; }
                    let vn = name_id(srcs, st, ps);
                    if st[5] == 0 { write("match: bad variant\n"); return 4; }
                    let tag = 0 - 1;
                    let ty = 0;
                    if okind == 8 {
                        let ii = (ometa >> 8) & 255;
                        let ti = inst_tmpl(ps, ii);
                        if enm != tmpl_name(ps, ti) { write("match: generic type mismatch\n"); return 4; }
                        let vk = inst_var_find(ps, ii, vn);
                        if vk < 0 { write("match: unknown generic variant\n"); return 4; }
                        tag = vk;
                        ty = inst_var_pty(ps, ii, vk);
                    } else if okind == 1 && enm == ps[17002] {
                        if vn == ps[17004] { tag = 0; ty = ot1; }
                        else if vn == ps[17005] { tag = 1; ty = 0; }
                        else { write("match: bad Option variant\n"); return 4; }
                    } else if okind == 2 && enm == ps[17003] {
                        if vn == ps[17006] { tag = 0; ty = ot1; }
                        else if vn == ps[17007] { tag = 1; ty = ot2; }
                        else { write("match: bad Result variant\n"); return 4; }
                    } else { write("match: type mismatch\n"); return 4; }
                    skip(srcs, st, n);
                    let hasbind = 0;
                    let bty = 0;
                    let boff = 0;
                    if st[0] < n && srcs[st[0]] == 40 {
                        if ty == 0 { write("match: unexpected binding\n"); return 4; }
                        st[0] = st[0] + 1;
                        skip(srcs, st, n);
                        let bname = name_id(srcs, st, ps);
                        if st[5] == 0 { write("match: bad binding\n"); return 4; }
                        if expect_char(srcs, st, 41, n) == 0 { write("match: expected )\n"); return 4; }
                        bty = ty;
                        if ty == 3 {
                            boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 24;
                            str_add(ps, bname, ctxi[NF], boff);
                        } else if ty == 4 || ty == 5 {
                            boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 16;
                            let elem = 8;
                            if ty == 4 { elem = 1; }
                            add_sl(ps, bname, boff | (elem << 31) | (ctxi[NF] << 35));
                        } else {
                            let bvi = var_find(ps, bname, ctxi[NF]);
                            if bvi >= 0 { boff = ps[9003 + bvi * 4]; }
                            else { boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8; var_add(ps, bname, ctxi[NF], boff); }
                        }
                        hasbind = 1;
                    }
                    if expect_char(srcs, st, 61, n) == 0 { write("match: expected =>\n"); return 4; }
                    if expect_char(srcs, st, 62, n) == 0 { write("match: expected =>\n"); return 4; }
                    if expect_char(srcs, st, 123, n) == 0 { write("match: expected {\n"); return 4; }
                    if expect_char(srcs, st, 114, n) == 0 { write("match: expected return\n"); return 4; }
                    if expect_char(srcs, st, 101, n) == 0 { write("match: expected return\n"); return 4; }
                    if expect_char(srcs, st, 116, n) == 0 { write("match: expected return\n"); return 4; }
                    if expect_char(srcs, st, 117, n) == 0 { write("match: expected return\n"); return 4; }
                    if expect_char(srcs, st, 114, n) == 0 { write("match: expected return\n"); return 4; }
                    if expect_char(srcs, st, 110, n) == 0 { write("match: expected return\n"); return 4; }
                    st[2] = 0;
                    st[9] = 0; st[10] = 0; st[11] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("match: bad expr\n"); return 4; }
                    if expect_char(srcs, st, 59, n) == 0 { write("match: expected ;\n"); return 4; }
                    if expect_char(srcs, st, 125, n) == 0 { write("match: expected }\n"); return 4; }
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = moff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 8);
                    emit1(c, cs, 131); emit1(c, cs, 249); emit1(c, cs, tag);
                    emit1(c, cs, 15); emit1(c, cs, 133);
                    let jp = cs[0];
                    emit4(c, cs, 0);
                    if hasbind == 1 {
                        if bty == 3 {
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 194);
                            emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 66); emit1(c, cs, 8);
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                            ps[cs[3] + cs[2] * 2] = cs[0];
                            ps[cs[3] + cs[2] * 2 + 1] = boff;
                            cs[2] = cs[2] + 1;
                            emit4(c, cs, 0);
                            emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 66); emit1(c, cs, 16);
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                            ps[cs[3] + cs[2] * 2] = cs[0];
                            ps[cs[3] + cs[2] * 2 + 1] = boff + 8;
                            cs[2] = cs[2] + 1;
                            emit4(c, cs, 0);
                            emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 66); emit1(c, cs, 24);
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                            ps[cs[3] + cs[2] * 2] = cs[0];
                            ps[cs[3] + cs[2] * 2 + 1] = boff + 16;
                            cs[2] = cs[2] + 1;
                            emit4(c, cs, 0);
                        } else if bty == 4 || bty == 5 {
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 194);
                            emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 66); emit1(c, cs, 8);
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                            ps[cs[3] + cs[2] * 2] = cs[0];
                            ps[cs[3] + cs[2] * 2 + 1] = boff;
                            cs[2] = cs[2] + 1;
                            emit4(c, cs, 0);
                            emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 66); emit1(c, cs, 16);
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                            ps[cs[3] + cs[2] * 2] = cs[0];
                            ps[cs[3] + cs[2] * 2 + 1] = boff + 8;
                            cs[2] = cs[2] + 1;
                            emit4(c, cs, 0);
                        } else {
                            emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 64); emit1(c, cs, 8);
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                            ps[cs[3] + cs[2] * 2] = cs[0];
                            ps[cs[3] + cs[2] * 2 + 1] = boff;
                            cs[2] = cs[2] + 1;
                            emit4(c, cs, 0);
                        }
                    }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit_ret(c, cs);
                    put32(c, jp, cs[0] - (jp + 4));
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                }
                if expect_char(srcs, st, 125, n) == 0 { write("match: expected }\n"); return 4; }
            } else {
            let mvi = var_find(ps, mnm, ctxi[NF]);
            if mvi < 0 { write("match: unknown subject\n"); return 4; }
            let moff = ps[9003 + mvi * 4];
            if expect_char(srcs, st, 123, n) == 0 { write("match: expected {\n"); return 4; }
            while 1 {
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 125 { break; }
                let enm = name_id(srcs, st, ps);
                if st[5] == 0 { write("match: bad enum\n"); return 4; }
                if expect_char(srcs, st, 46, n) == 0 { write("match: expected .\n"); return 4; }
                let vn = name_id(srcs, st, ps);
                if st[5] == 0 { write("match: bad variant\n"); return 4; }
                let ei = en_find(ps, enm);
                if ei < 0 { write("match: unknown enum\n"); return 4; }
                let tag = en_var_find(ps, ei, vn);
                if tag < 0 { write("match: unknown variant\n"); return 4; }
                let tval = tag & 255;
                let pay = (tag >> 8) & 1;
                skip(srcs, st, n);
                let hasbind = 0;
                let boff = 0;
                if st[0] < n && srcs[st[0]] == 40 {
                    if pay == 0 { write("match: unexpected binding\n"); return 4; }
                    st[0] = st[0] + 1;
                    skip(srcs, st, n);
                    let bname = name_id(srcs, st, ps);
                    if st[5] == 0 { write("match: bad binding\n"); return 4; }
                    if expect_char(srcs, st, 41, n) == 0 { write("match: expected )\n"); return 4; }
                    let bvi = var_find(ps, bname, ctxi[NF]);
                    if bvi >= 0 { boff = ps[9003 + bvi * 4]; }
                    else { boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8; var_add(ps, bname, ctxi[NF], boff); }
                    hasbind = 1;
                }
                if expect_char(srcs, st, 61, n) == 0 { write("match: expected =>\n"); return 4; }
                if expect_char(srcs, st, 62, n) == 0 { write("match: expected =>\n"); return 4; }
                if expect_char(srcs, st, 123, n) == 0 { write("match: expected {\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("match: expected return\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("match: expected return\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("match: expected return\n"); return 4; }
                if expect_char(srcs, st, 117, n) == 0 { write("match: expected return\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("match: expected return\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("match: expected return\n"); return 4; }
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("match: bad expr\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("match: expected ;\n"); return 4; }
                if expect_char(srcs, st, 125, n) == 0 { write("match: expected }\n"); return 4; }
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = moff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 193);
                emit1(c, cs, 129); emit1(c, cs, 225); emit4(c, cs, 255);
                emit1(c, cs, 131); emit1(c, cs, 249); emit1(c, cs, tval);
                emit1(c, cs, 15); emit1(c, cs, 133);
                let jp = cs[0];
                emit4(c, cs, 0);
                if hasbind == 1 {
                    emit1(c, cs, 72); emit1(c, cs, 193); emit1(c, cs, 248); emit1(c, cs, 8);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = boff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit_ret(c, cs);
                put32(c, jp, cs[0] - (jp + 4));
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
            }
            if expect_char(srcs, st, 125, n) == 0 { write("match: expected }\n"); return 4; }
            }
        } else {
            let nstart = st[0];
            let vnm = name_id(srcs, st, ps);
            if st[5] == 0 { write("slice: bad statement\n"); return 4; }
            skip(srcs, st, n);
            if st[0] < n && srcs[st[0]] == 40 {
                st[0] = nstart;
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("slice: bad expr statement\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
            } else if st[0] < n && srcs[st[0]] == 91 {
            st[0] = st[0] + 1;
            st[2] = 0;
            parse_index(srcs, st, ps);
            if st[3] != 0 { write("slice: bad index\n"); return 4; }
            if expect_char(srcs, st, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
            if expect_char(srcs, st, 61, n) == 0 { write("slice: expected =\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, cs, ps);
            emit1(c, cs, 80); // index
            st[2] = 0;
            st[12] = ctxi[DLEN];
            parse_expr(srcs, st, ps);
            ctxi[DLEN] = st[12];
            if st[3] != 0 { write("slice: bad value\n"); return 4; }
            if expect_char(srcs, st, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, cs, ps);
            emit1(c, cs, 89); // pop rcx = index
            let ai = arr_find(ps, vnm, ctxi[NF]);
            if ai >= 0 {
                let meta = ps[4098 + ai * 2];
                let off = meta & 2147483647;
                let elem = (meta >> 31) & 15;
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                if elem == 8 {
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 4); emit1(c, cs, 202);
                } else {
                    emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 209);
                    emit1(c, cs, 136); emit1(c, cs, 1);
                }
            } else {
                let si = sl_find(ps, vnm, ctxi[NF]);
                if si < 0 { write("slice: unknown index target\n"); return 4; }
                let meta = ps[4610 + si * 2];
                let off = meta & 2147483647;
                let elem = (meta >> 31) & 15;
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                if elem == 8 {
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 4); emit1(c, cs, 202);
                } else {
                    emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 209);
                    emit1(c, cs, 136); emit1(c, cs, 1);
                }
            }
            } else if st[0] < n && srcs[st[0]] == 46 {
                st[0] = st[0] + 1;
                skip(srcs, st, n);
                let fld = name_id(srcs, st, ps);
                if st[5] == 0 { write("struct: bad field\n"); return 4; }
                let svi = sv_find(ps, vnm, ctxi[NF]);
                if svi < 0 { write("struct: unknown variable\n"); return 4; }
                let sidx = ps[6404 + svi * 4];
                let fi = st_field_find(ps, sidx, fld);
                if fi < 0 { write("struct: unknown field\n"); return 4; }
                let fb = 5121 + sidx * 18;
                let fmeta = ps[fb + 3 + fi * 2];
                let off = ps[6403 + svi * 4] + (fmeta & 2147483647);
                let elem = (fmeta >> 31) & 15;
                if expect_char(srcs, st, 61, n) == 0 { write("struct: expected =\n"); return 4; }
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("struct: bad field value\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                if elem == 8 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5); }
                else { emit1(c, cs, 136); emit1(c, cs, 5); }
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
            } else {
                if expect_char(srcs, st, 61, n) == 0 { write("assign: expected =\n"); return 4; }
                skip(srcs, st, n);
                let svi2 = str_find(ps, vnm, ctxi[NF]);
                if svi2 >= 0 {
                    let soff2 = ps[15003 + svi2 * 4];
                    if st[0] < n && srcs[st[0]] == 34 {
                        let slen2 = parse_str_lit(srcs, st, ds);
                        if st[3] != 0 { write("str: bad literal\n"); return 4; }
                        let chars2 = utf8_count(ds, st[7], slen2);
                        emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = st[7];
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff2;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 184); emit4(c, cs, slen2);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff2 + 8;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    emit1(c, cs, 184); emit4(c, cs, chars2);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = soff2 + 16;
                    cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    } else {
                        st[2] = 0;
                        st[12] = ctxi[DLEN];
                        parse_expr(srcs, st, ps);
                        ctxi[DLEN] = st[12];
                        if st[3] != 0 { write("str: bad assign expr\n"); return 4; }
                        emit_expr(c, cs, ps);
                        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff2 + 16;
                        cs[2] = cs[2] + 1; emit4(c, cs, 0);
                        emit1(c, cs, 88);
                        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff2 + 8;
                        cs[2] = cs[2] + 1; emit4(c, cs, 0);
                        emit1(c, cs, 88);
                        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff2;
                        cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    }
                } else {
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("assign: bad expr\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                let vi = var_find(ps, vnm, ctxi[NF]);
                let voff = 0;
                if vi >= 0 { voff = ps[9003 + vi * 4]; }
                else { voff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8; vi = var_add(ps, vnm, ctxi[NF], voff); }
                ps[cs[3] + cs[2] * 2 + 1] = voff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                }
                if expect_char(srcs, st, 59, n) == 0 { write("assign: expected ;\n"); return 4; }
            }
        }
    }
    return 0;
}

fn emit_body(mem: Slice[U8], ps: Slice[Int], n: Int) -> Int {
    // post's tail is reserved for the packed Int state (see main).
    let ctxi: Slice[Int] = slice_at(ps, 198952, 2048);
    let st: Slice[Int] = slice_at(ctxi, 0, 16);
    let cs: Slice[Int] = slice_at(ctxi, 16, 16);
    let fname: Slice[Int] = slice_at(ctxi, 416, 128);
    let flabel: Slice[Int] = slice_at(ctxi, 544, 128);
    let fparams: Slice[Int] = slice_at(ctxi, 672, 16);
    let fpelem: Slice[Int] = slice_at(ctxi, 688, 16);
    let fret: Slice[Int] = slice_at(ctxi, 704, 128);
    let fret_t1: Slice[Int] = slice_at(ctxi, 832, 128);
    let fret_t2: Slice[Int] = slice_at(ctxi, 960, 128);
    let fret_ty: Slice[Int] = slice_at(ctxi, 1088, 128);
    let rname: Slice[Int] = slice_at(ctxi, 352, 64);
    let ck: Slice[Int] = slice_at(ctxi, 32, 64);
    let cje: Slice[Int] = slice_at(ctxi, 96, 64);
    let cstart: Slice[Int] = slice_at(ctxi, 160, 64);
    let cjmp: Slice[Int] = slice_at(ctxi, 1221, 64);
    let bpos: Slice[Int] = slice_at(ctxi, 288, 64);
    let bloop: Slice[Int] = slice_at(ctxi, 224, 64);
    let NF = 1216;
    let DLEN = 1217;
    let CD = 1218;
    let NBRK = 1219;
    let HAVE_RET = 1220;
    let RDEPTH = 1287;
    // membuf layout: src [0,294912), code [294912,1343488), data [1343488,1409024).
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let c: Slice[U8] = slice_at(mem, 294912, 1048576);
    let ds: Slice[U8] = slice_at(mem, 1343488, 65536);
    let i = 0;
    let done = 0;
    while done == 0 {
        skip(srcs, st, n);
        if st[0] >= n { done = 1; }
        else {
            if st[0] + 1 < n && srcs[st[0]] == 115 && srcs[st[0] + 1] == 116 {
                // struct Name { field: Int/U8, ... }
                if expect_char(srcs, st, 115, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 117, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 99, n) == 0 { write("struct: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("struct: bad keyword\n"); return 4; }
                skip(srcs, st, n);
                let snm = name_id(srcs, st, ps);
                if st[5] == 0 { write("struct: bad name\n"); return 4; }
                let si = st_add(ps, snm);
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 91 {
                    write("stage1: E-LS-UNSUPPORTED: generic struct parameters are not implemented in B-LS yet\n");
                    return 4;
                }
                if expect_char(srcs, st, 123, n) == 0 { write("struct: expected {\n"); return 4; }
                let foff = 0;
                while 1 {
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 125 { break; }
                    let fname = name_id(srcs, st, ps);
                    if st[5] == 0 { write("struct: bad field\n"); return 4; }
                    if expect_char(srcs, st, 58, n) == 0 { write("struct: expected :\n"); return 4; }
                    skip(srcs, st, n);
                    if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                        write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
                        return 4;
                    }
                    let elem = 0;
                    if st[0] < n && srcs[st[0]] == 85 {
                        if expect_char(srcs, st, 85, n) == 0 { write("struct: expected U8\n"); return 4; }
                        if expect_char(srcs, st, 56, n) == 0 { write("struct: expected U8\n"); return 4; }
                        elem = 1;
                    } else {
                        if expect_char(srcs, st, 73, n) == 0 { write("struct: expected Int\n"); return 4; }
                        if expect_char(srcs, st, 110, n) == 0 { write("struct: expected Int\n"); return 4; }
                        if expect_char(srcs, st, 116, n) == 0 { write("struct: expected Int\n"); return 4; }
                        elem = 8;
                    }
                    if foff > 2147483647 { write("struct: field offset exceeds 31 bits\n"); return 4; }
                    st_field_add(ps, si, fname, foff | (elem << 31));
                    foff = foff + elem;
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                }
                if expect_char(srcs, st, 125, n) == 0 { write("struct: expected }\n"); return 4; }
            } else if st[0] + 1 < n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 110 {
                // enum Name { A, B, C }
                if expect_char(srcs, st, 101, n) == 0 { write("enum: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("enum: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 117, n) == 0 { write("enum: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 109, n) == 0 { write("enum: bad keyword\n"); return 4; }
                skip(srcs, st, n);
                let enm = name_id(srcs, st, ps);
                if st[5] == 0 { write("enum: bad name\n"); return 4; }
                let is_gen = 0;
                let nparams = 0;
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 91 {
                    is_gen = 1;
                    if expect_char(srcs, st, 91, n) == 0 { write("enum: expected [\n"); return 4; }
                    skip(srcs, st, n);
                    if st[0] >= n || srcs[st[0]] != 84 {
                        write("stage1: E-LS-UNSUPPORTED: generic enum parameter names other than T are not implemented in B-LS yet\n");
                        return 4;
                    }
                    if expect_char(srcs, st, 84, n) == 0 { write("enum: expected T\n"); return 4; }
                    nparams = 1;
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 44 {
                        st[0] = st[0] + 1;
                        skip(srcs, st, n);
                        if expect_char(srcs, st, 69, n) == 0 { write("enum: expected E\n"); return 4; }
                        nparams = 2;
                    }
                    if expect_char(srcs, st, 93, n) == 0 { write("enum: expected ]\n"); return 4; }
                }
                let ei = 0;
                let ti = 0;
                if is_gen == 1 { ti = tmpl_add(ps, enm, nparams); }
                else { ei = en_add(ps, enm); }
                if expect_char(srcs, st, 123, n) == 0 { write("enum: expected {\n"); return 4; }
                let tag = 0;
                while 1 {
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 125 { break; }
                    let vname = name_id(srcs, st, ps);
                    if st[5] == 0 { write("enum: bad variant\n"); return 4; }
                    skip(srcs, st, n);
                    let pay = 0;
                    let pty = 0;
                    if st[0] < n && srcs[st[0]] == 40 {
                        if expect_char(srcs, st, 40, n) == 0 { write("enum: payload\n"); return 4; }
                        skip(srcs, st, n);
                        if is_gen == 1 && st[0] < n && srcs[st[0]] == 84 {
                            if expect_char(srcs, st, 84, n) == 0 { write("enum: expected T\n"); return 4; }
                            pty = 100;
                        } else if is_gen == 1 && st[0] < n && srcs[st[0]] == 69 {
                            if expect_char(srcs, st, 69, n) == 0 { write("enum: expected E\n"); return 4; }
                            pty = 101;
                        } else {
                            pty = parse_ty(srcs, st, n);
                            if pty == 0 { write("enum: bad payload type\n"); return 4; }
                        }
                        if expect_char(srcs, st, 41, n) == 0 { write("enum: payload\n"); return 4; }
                        pay = 1;
                    }
                    if is_gen == 1 {
                        tmpl_var_add(ps, ti, vname, pty);
                    } else {
                        en_var_add(ps, ei, vname, tag | (pay << 8));
                    }
                    tag = tag + 1;
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                }
                if expect_char(srcs, st, 125, n) == 0 { write("enum: expected }\n"); return 4; }
            } else {
            if expect_char(srcs, st, 102, n) == 0 { write("slice: expected fn\n"); return 4; }
            if expect_char(srcs, st, 110, n) == 0 { write("slice: expected fn\n"); return 4; }
            skip(srcs, st, n);
            let fnm = name_id(srcs, st, ps);
            if st[5] == 0 { write("slice: bad name\n"); return 4; }
            let is_gen = 0;
            skip(srcs, st, n);
            if st[0] < n && srcs[st[0]] == 91 {
                is_gen = 1;
                if expect_char(srcs, st, 91, n) == 0 { write("fn: expected [\n"); return 4; }
                skip(srcs, st, n);
                if st[0] >= n || srcs[st[0]] != 84 {
                    write("stage1: E-LS-UNSUPPORTED: generic parameter names other than T are not implemented in B-LS yet\n");
                    return 4;
                }
                if expect_char(srcs, st, 84, n) == 0 { write("fn: expected T\n"); return 4; }
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 44 {
                    write("stage1: E-LS-UNSUPPORTED: multiple generic parameters are not implemented in B-LS yet\n");
                    return 4;
                }
                if expect_char(srcs, st, 93, n) == 0 { write("fn: expected ]\n"); return 4; }
            }
            if expect_char(srcs, st, 40, n) == 0 { write("slice: expected (\n"); return 4; }
            let pc = 0;
            while 1 {
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                if pc >= 6 { write("names: too many params\n"); return 4; }
                if st[0] + 3 <= n && srcs[st[0]] == 118 && srcs[st[0] + 1] == 97 && srcs[st[0] + 2] == 108 && kw_end(srcs, st[0] + 3, n) == 1 {
                    let vp = st[0] + 3;
                    while vp < n && (srcs[vp] == 32 || srcs[vp] == 9 || srcs[vp] == 10 || srcs[vp] == 13) { vp = vp + 1; }
                    if vp < n && is_ident_byte(srcs[vp]) == 1 {
                        // B2: `val x: T` is an immutable by-value binding.
                        st[0] = st[0] + 3;
                        skip(srcs, st, n);
                    }
                }
                if st[0] + 3 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 {
                    write("stage1: E-LS-UNSUPPORTED: ref parameters are not implemented in B-LS yet\n");
                    return 4;
                }
                let pid = name_id(srcs, st, ps);
                if st[5] == 0 { write("names: bad param\n"); return 4; }
                fparams[pc] = pid;
                if expect_char(srcs, st, 58, n) == 0 { write("names: expected :\n"); return 4; }
                skip(srcs, st, n);
                let pe = 0;
                if is_gen == 1 && st[0] < n && srcs[st[0]] == 84 {
                    if expect_char(srcs, st, 84, n) == 0 { write("names: expected T\n"); return 4; }
                    pe = 100;
                } else if st[0] < n && srcs[st[0]] == 73 {
                    if expect_char(srcs, st, 73, n) == 0 { write("names: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 110, n) == 0 { write("names: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 116, n) == 0 { write("names: expected Int\n"); return 4; }
                    pe = 0;
                } else if st[0] < n && srcs[st[0]] == 83 && st[0] + 2 < n && srcs[st[0] + 1] == 116 && srcs[st[0] + 2] == 114 {
                    if expect_char(srcs, st, 83, n) == 0 { write("names: expected Str\n"); return 4; }
                    if expect_char(srcs, st, 116, n) == 0 { write("names: expected Str\n"); return 4; }
                    if expect_char(srcs, st, 114, n) == 0 { write("names: expected Str\n"); return 4; }
                    pe = 2;
                } else if st[0] < n && srcs[st[0]] == 83 {
                    if expect_char(srcs, st, 83, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, st, 108, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, st, 105, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, st, 99, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, st, 101, n) == 0 { write("names: expected Slice\n"); return 4; }
                    if expect_char(srcs, st, 91, n) == 0 { write("names: expected [\n"); return 4; }
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 85 {
                        if expect_char(srcs, st, 85, n) == 0 { write("names: expected U8\n"); return 4; }
                        if expect_char(srcs, st, 56, n) == 0 { write("names: expected U8\n"); return 4; }
                        pe = 1;
                    } else {
                        if expect_char(srcs, st, 73, n) == 0 { write("names: expected Int\n"); return 4; }
                        if expect_char(srcs, st, 110, n) == 0 { write("names: expected Int\n"); return 4; }
                        if expect_char(srcs, st, 116, n) == 0 { write("names: expected Int\n"); return 4; }
                        pe = 8;
                    }
                    if expect_char(srcs, st, 93, n) == 0 { write("names: expected ]\n"); return 4; }
                } else if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                    write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
                    return 4;
                } else {
                    write("names: unsupported param type\n"); return 4;
                }
                fpelem[pc] = pe;
                pc = pc + 1;
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                else if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                else { write("names: bad params\n"); return 4; }
            }
            if expect_char(srcs, st, 45, n) == 0 { write("slice: expected ->\n"); return 4; }
            if expect_char(srcs, st, 62, n) == 0 { write("slice: expected ->\n"); return 4; }
            skip(srcs, st, n);
            let fretv = 0;
            let ft1 = 0;
            let ft2 = 0;
            let fdesc = 0;
            let fgen = 0;
            let fret_t = 0;
            if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
                return 4;
            }
            if is_gen == 1 && st[0] < n && srcs[st[0]] == 84 {
                if expect_char(srcs, st, 84, n) == 0 { write("slice: expected T\n"); return 4; }
                fret_t = 1;
            } else if st[0] < n && srcs[st[0]] == 79 {
                if expect_char(srcs, st, 79, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 112, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 111, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                ft1 = parse_ty(srcs, st, n);
                if st[3] != 0 || ft1 == 0 { write("slice: bad Option type\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                fretv = 1;
            } else if st[0] < n && srcs[st[0]] == 82 {
                if expect_char(srcs, st, 82, n) == 0 { write("slice: expected Result\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("slice: expected Result\n"); return 4; }
                if expect_char(srcs, st, 115, n) == 0 { write("slice: expected Result\n"); return 4; }
                if expect_char(srcs, st, 117, n) == 0 { write("slice: expected Result\n"); return 4; }
                if expect_char(srcs, st, 108, n) == 0 { write("slice: expected Result\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("slice: expected Result\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                ft1 = parse_ty(srcs, st, n);
                if st[3] != 0 || ft1 == 0 { write("slice: bad Result type\n"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                ft2 = parse_ty(srcs, st, n);
                if st[3] != 0 || ft2 == 0 { write("slice: bad Result type\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                fretv = 2;
            } else if st[0] < n && srcs[st[0]] != 73 {
                fdesc = parse_user_desc(srcs, st, ps);
                if fdesc <= 0 { write("slice: bad generic return type\n"); return 4; }
                fgen = 1;
            } else {
                if expect_char(srcs, st, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
            }
            fret[ctxi[NF]] = fretv;
            fret_t1[ctxi[NF]] = ft1;
            fret_t2[ctxi[NF]] = ft2;
            if fgen == 1 { fret_ty[ctxi[NF]] = fdesc; }
            else if fretv == 1 { fret_ty[ctxi[NF]] = mk_opt_ty(ft1); }
            else if fretv == 2 { fret_ty[ctxi[NF]] = mk_res_ty(ft1, ft2); }
            else { fret_ty[ctxi[NF]] = 1; }
            if is_gen == 1 { ps[120000 + fnm] = 1073741824 | (fret_t << 29) | fret_ty[ctxi[NF]]; }
            else { ps[120000 + fnm] = fret_ty[ctxi[NF]]; }
            skip(srcs, st, n);
            if st[0] + 3 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 102 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 {
                write("stage1: E-LS-UNSUPPORTED: eff(...) clauses are not implemented in B-LS yet\n");
                return 4;
            }
            if st[0] + 8 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 113 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 105 && srcs[st[0] + 5] == 114 && srcs[st[0] + 6] == 101 && srcs[st[0] + 7] == 115 && kw_end(srcs, st[0] + 8, n) == 1 {
                write("stage1: E-LS-UNSUPPORTED: requires clauses are not implemented in B-LS yet\n");
                return 4;
            }
            if st[0] + 7 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 110 && srcs[st[0] + 2] == 115 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 114 && srcs[st[0] + 5] == 101 && srcs[st[0] + 6] == 115 && kw_end(srcs, st[0] + 7, n) == 1 {
                write("stage1: E-LS-UNSUPPORTED: ensures clauses are not implemented in B-LS yet\n");
                return 4;
            }
            if expect_char(srcs, st, 123, n) == 0 { write("slice: expected {\n"); return 4; }

            if ctxi[NF] >= 128 { write("slice: too many functions\n"); return 4; }
            fname[ctxi[NF]] = fnm;
            flabel[ctxi[NF]] = cs[0];
            emit1(c, cs, 85);
            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 229);
            cs[4] = ctxi[NF];
            st[4] = ctxi[NF];
            ps[125500 + ctxi[NF]] = 0;
            ps[125501 + ctxi[NF]] = 0;
            ps[125502 + ctxi[NF]] = 0;
            st[8] = fret_ty[ctxi[NF]];
            cs[10] = fret_ty[ctxi[NF]];
            cs[11] = fret_t1[ctxi[NF]];
            cs[12] = fret_t2[ctxi[NF]];

            // param stores, Slice uses two consecutive registers
            let reg = 0;
            i = 0;
            while i < pc {
                let pid = fparams[i];
                let pe = fpelem[i];
                if pe == 0 || pe == 100 {
                    let vi = var_find(ps, pid, ctxi[NF]);
                    let off = 0;
                    if vi >= 0 { off = ps[9003 + vi * 4]; }
                    else {
                        off = ctxi[DLEN];
                        ctxi[DLEN] = ctxi[DLEN] + 8;
                        vi = var_add(ps, pid, ctxi[NF], off);
                        if pe == 100 { ps[9004 + vi * 4] = 100; }
                        else { ps[9004 + vi * 4] = 1; }
                    }
                    if reg == 0 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 61); }
                    else if reg == 1 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 53); }
                    else if reg == 2 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21); }
                    else if reg == 3 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 13); }
                    else if reg == 4 { emit1(c, cs, 76); emit1(c, cs, 137); emit1(c, cs, 5); }
                    else { emit1(c, cs, 76); emit1(c, cs, 137); emit1(c, cs, 13); }
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = off;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                    reg = reg + 1;
                } else if pe == 2 {
                    let soff = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 24;
                    str_add(ps, pid, ctxi[NF], soff);
                    let k = 0;
                    while k < 3 {
                        if reg == 0 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 61); }
                        else if reg == 1 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 53); }
                        else if reg == 2 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21); }
                        else if reg == 3 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 13); }
                        else if reg == 4 { emit1(c, cs, 76); emit1(c, cs, 137); emit1(c, cs, 5); }
                        else { emit1(c, cs, 76); emit1(c, cs, 137); emit1(c, cs, 13); }
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff + k * 8;
                        cs[2] = cs[2] + 1;
                        emit4(c, cs, 0);
                        reg = reg + 1;
                        k = k + 1;
                    }
                } else {
                    let soff = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + 16;
                    add_sl(ps, pid, soff | (pe << 31) | (ctxi[NF] << 35));
                    let k = 0;
                    while k < 2 {
                        if reg == 0 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 61); }
                        else if reg == 1 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 53); }
                        else if reg == 2 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21); }
                        else if reg == 3 { emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 13); }
                        else if reg == 4 { emit1(c, cs, 76); emit1(c, cs, 137); emit1(c, cs, 5); }
                        else { emit1(c, cs, 76); emit1(c, cs, 137); emit1(c, cs, 13); }
                        ps[cs[3] + cs[2] * 2] = cs[0];
                        ps[cs[3] + cs[2] * 2 + 1] = soff + k * 8;
                        cs[2] = cs[2] + 1;
                        emit4(c, cs, 0);
                        reg = reg + 1;
                        k = k + 1;
                    }
                }
                i = i + 1;
            }

            ctxi[HAVE_RET] = 0;
            ctxi[CD] = 0;
            ctxi[NBRK] = 0;
            ctxi[RDEPTH] = 0;
            let body_after = scan_block_end(srcs, st[0] - 1, n);
            if body_after < 0 { write("slice: bad body\n"); return 4; }
            let eb = emit_stmt_list(mem, ps, n);
            if eb != 0 { return eb; }
            st[0] = body_after;
            if ctxi[HAVE_RET] == 0 {
                emit1(c, cs, 72); emit1(c, cs, 49); emit1(c, cs, 192);
                emit_ret(c, cs);
            }
            if ps[125500 + ctxi[NF]] != 0 { ps[120000 + fnm] = ps[120000 + fnm] | 268435456; }
            if ps[125501 + ctxi[NF]] != 0 { ps[120000 + fnm] = ps[120000 + fnm] | 134217728; }
            if ps[125502 + ctxi[NF]] != 0 { ps[120000 + fnm] = ps[120000 + fnm] | 67108864; }
            ctxi[NF] = ctxi[NF] + 1;
            }
        }
    }
    return 0;
}

fn main() -> Int {
    // B0.3b-2: source + code + data share one buffer so emit_body only needs
    // one Slice[U8] argument (the ABI has 6 argument slots, and each Slice
    // consumes two).
    let membuf: Array[U8, 1409024] = Array.zeroed();
    let out: Array[U8, 1048576] = Array.zeroed();
    let genop_str: Array[U8, 1085] = Array.zeroed();
    genop_str[0] = 139;
    genop_str[1] = 7;
    genop_str[2] = 59;
    genop_str[3] = 6;
    genop_str[4] = 15;
    genop_str[5] = 133;
    genop_str[6] = 39;
    genop_str[7] = 4;
    genop_str[8] = 0;
    genop_str[9] = 0;
    genop_str[10] = 131;
    genop_str[11] = 248;
    genop_str[12] = 3;
    genop_str[13] = 116;
    genop_str[14] = 23;
    genop_str[15] = 131;
    genop_str[16] = 248;
    genop_str[17] = 4;
    genop_str[18] = 15;
    genop_str[19] = 132;
    genop_str[20] = 31;
    genop_str[21] = 2;
    genop_str[22] = 0;
    genop_str[23] = 0;
    genop_str[24] = 131;
    genop_str[25] = 248;
    genop_str[26] = 5;
    genop_str[27] = 15;
    genop_str[28] = 132;
    genop_str[29] = 22;
    genop_str[30] = 2;
    genop_str[31] = 0;
    genop_str[32] = 0;
    genop_str[33] = 233;
    genop_str[34] = 11;
    genop_str[35] = 4;
    genop_str[36] = 0;
    genop_str[37] = 0;
    genop_str[38] = 131;
    genop_str[39] = 250;
    genop_str[40] = 1;
    genop_str[41] = 116;
    genop_str[42] = 23;
    genop_str[43] = 131;
    genop_str[44] = 250;
    genop_str[45] = 6;
    genop_str[46] = 15;
    genop_str[47] = 130;
    genop_str[48] = 253;
    genop_str[49] = 3;
    genop_str[50] = 0;
    genop_str[51] = 0;
    genop_str[52] = 131;
    genop_str[53] = 250;
    genop_str[54] = 11;
    genop_str[55] = 15;
    genop_str[56] = 135;
    genop_str[57] = 244;
    genop_str[58] = 3;
    genop_str[59] = 0;
    genop_str[60] = 0;
    genop_str[61] = 233;
    genop_str[62] = 134;
    genop_str[63] = 0;
    genop_str[64] = 0;
    genop_str[65] = 0;
    genop_str[66] = 76;
    genop_str[67] = 139;
    genop_str[68] = 87;
    genop_str[69] = 8;
    genop_str[70] = 76;
    genop_str[71] = 139;
    genop_str[72] = 95;
    genop_str[73] = 16;
    genop_str[74] = 76;
    genop_str[75] = 139;
    genop_str[76] = 119;
    genop_str[77] = 24;
    genop_str[78] = 76;
    genop_str[79] = 139;
    genop_str[80] = 102;
    genop_str[81] = 8;
    genop_str[82] = 76;
    genop_str[83] = 139;
    genop_str[84] = 110;
    genop_str[85] = 16;
    genop_str[86] = 72;
    genop_str[87] = 139;
    genop_str[88] = 70;
    genop_str[89] = 24;
    genop_str[90] = 73;
    genop_str[91] = 1;
    genop_str[92] = 198;
    genop_str[93] = 76;
    genop_str[94] = 137;
    genop_str[95] = 219;
    genop_str[96] = 76;
    genop_str[97] = 1;
    genop_str[98] = 235;
    genop_str[99] = 73;
    genop_str[100] = 139;
    genop_str[101] = 0;
    genop_str[102] = 73;
    genop_str[103] = 137;
    genop_str[104] = 199;
    genop_str[105] = 73;
    genop_str[106] = 1;
    genop_str[107] = 223;
    genop_str[108] = 77;
    genop_str[109] = 59;
    genop_str[110] = 57;
    genop_str[111] = 15;
    genop_str[112] = 135;
    genop_str[113] = 188;
    genop_str[114] = 3;
    genop_str[115] = 0;
    genop_str[116] = 0;
    genop_str[117] = 77;
    genop_str[118] = 137;
    genop_str[119] = 56;
    genop_str[120] = 73;
    genop_str[121] = 137;
    genop_str[122] = 199;
    genop_str[123] = 76;
    genop_str[124] = 137;
    genop_str[125] = 255;
    genop_str[126] = 76;
    genop_str[127] = 137;
    genop_str[128] = 214;
    genop_str[129] = 76;
    genop_str[130] = 137;
    genop_str[131] = 218;
    genop_str[132] = 72;
    genop_str[133] = 133;
    genop_str[134] = 210;
    genop_str[135] = 116;
    genop_str[136] = 15;
    genop_str[137] = 138;
    genop_str[138] = 6;
    genop_str[139] = 136;
    genop_str[140] = 7;
    genop_str[141] = 72;
    genop_str[142] = 255;
    genop_str[143] = 198;
    genop_str[144] = 72;
    genop_str[145] = 255;
    genop_str[146] = 199;
    genop_str[147] = 72;
    genop_str[148] = 255;
    genop_str[149] = 202;
    genop_str[150] = 235;
    genop_str[151] = 236;
    genop_str[152] = 76;
    genop_str[153] = 137;
    genop_str[154] = 230;
    genop_str[155] = 76;
    genop_str[156] = 137;
    genop_str[157] = 234;
    genop_str[158] = 72;
    genop_str[159] = 133;
    genop_str[160] = 210;
    genop_str[161] = 116;
    genop_str[162] = 15;
    genop_str[163] = 138;
    genop_str[164] = 6;
    genop_str[165] = 136;
    genop_str[166] = 7;
    genop_str[167] = 72;
    genop_str[168] = 255;
    genop_str[169] = 198;
    genop_str[170] = 72;
    genop_str[171] = 255;
    genop_str[172] = 199;
    genop_str[173] = 72;
    genop_str[174] = 255;
    genop_str[175] = 202;
    genop_str[176] = 235;
    genop_str[177] = 236;
    genop_str[178] = 199;
    genop_str[179] = 1;
    genop_str[180] = 3;
    genop_str[181] = 0;
    genop_str[182] = 0;
    genop_str[183] = 0;
    genop_str[184] = 76;
    genop_str[185] = 137;
    genop_str[186] = 121;
    genop_str[187] = 8;
    genop_str[188] = 72;
    genop_str[189] = 137;
    genop_str[190] = 89;
    genop_str[191] = 16;
    genop_str[192] = 76;
    genop_str[193] = 137;
    genop_str[194] = 113;
    genop_str[195] = 24;
    genop_str[196] = 72;
    genop_str[197] = 137;
    genop_str[198] = 200;
    genop_str[199] = 195;
    genop_str[200] = 76;
    genop_str[201] = 139;
    genop_str[202] = 71;
    genop_str[203] = 8;
    genop_str[204] = 72;
    genop_str[205] = 139;
    genop_str[206] = 71;
    genop_str[207] = 16;
    genop_str[208] = 76;
    genop_str[209] = 1;
    genop_str[210] = 192;
    genop_str[211] = 73;
    genop_str[212] = 137;
    genop_str[213] = 193;
    genop_str[214] = 76;
    genop_str[215] = 139;
    genop_str[216] = 86;
    genop_str[217] = 8;
    genop_str[218] = 72;
    genop_str[219] = 139;
    genop_str[220] = 70;
    genop_str[221] = 16;
    genop_str[222] = 76;
    genop_str[223] = 1;
    genop_str[224] = 208;
    genop_str[225] = 73;
    genop_str[226] = 137;
    genop_str[227] = 195;
    genop_str[228] = 77;
    genop_str[229] = 57;
    genop_str[230] = 200;
    genop_str[231] = 15;
    genop_str[232] = 131;
    genop_str[233] = 31;
    genop_str[234] = 1;
    genop_str[235] = 0;
    genop_str[236] = 0;
    genop_str[237] = 77;
    genop_str[238] = 57;
    genop_str[239] = 218;
    genop_str[240] = 15;
    genop_str[241] = 131;
    genop_str[242] = 29;
    genop_str[243] = 1;
    genop_str[244] = 0;
    genop_str[245] = 0;
    genop_str[246] = 65;
    genop_str[247] = 15;
    genop_str[248] = 182;
    genop_str[249] = 0;
    genop_str[250] = 73;
    genop_str[251] = 255;
    genop_str[252] = 192;
    genop_str[253] = 61;
    genop_str[254] = 128;
    genop_str[255] = 0;
    genop_str[256] = 0;
    genop_str[257] = 0;
    genop_str[258] = 114;
    genop_str[259] = 117;
    genop_str[260] = 61;
    genop_str[261] = 224;
    genop_str[262] = 0;
    genop_str[263] = 0;
    genop_str[264] = 0;
    genop_str[265] = 114;
    genop_str[266] = 57;
    genop_str[267] = 61;
    genop_str[268] = 240;
    genop_str[269] = 0;
    genop_str[270] = 0;
    genop_str[271] = 0;
    genop_str[272] = 114;
    genop_str[273] = 70;
    genop_str[274] = 131;
    genop_str[275] = 224;
    genop_str[276] = 7;
    genop_str[277] = 193;
    genop_str[278] = 224;
    genop_str[279] = 6;
    genop_str[280] = 65;
    genop_str[281] = 15;
    genop_str[282] = 182;
    genop_str[283] = 8;
    genop_str[284] = 73;
    genop_str[285] = 255;
    genop_str[286] = 192;
    genop_str[287] = 131;
    genop_str[288] = 225;
    genop_str[289] = 63;
    genop_str[290] = 9;
    genop_str[291] = 200;
    genop_str[292] = 193;
    genop_str[293] = 224;
    genop_str[294] = 6;
    genop_str[295] = 65;
    genop_str[296] = 15;
    genop_str[297] = 182;
    genop_str[298] = 8;
    genop_str[299] = 73;
    genop_str[300] = 255;
    genop_str[301] = 192;
    genop_str[302] = 131;
    genop_str[303] = 225;
    genop_str[304] = 63;
    genop_str[305] = 9;
    genop_str[306] = 200;
    genop_str[307] = 193;
    genop_str[308] = 224;
    genop_str[309] = 6;
    genop_str[310] = 65;
    genop_str[311] = 15;
    genop_str[312] = 182;
    genop_str[313] = 8;
    genop_str[314] = 73;
    genop_str[315] = 255;
    genop_str[316] = 192;
    genop_str[317] = 131;
    genop_str[318] = 225;
    genop_str[319] = 63;
    genop_str[320] = 9;
    genop_str[321] = 200;
    genop_str[322] = 235;
    genop_str[323] = 53;
    genop_str[324] = 131;
    genop_str[325] = 224;
    genop_str[326] = 31;
    genop_str[327] = 193;
    genop_str[328] = 224;
    genop_str[329] = 6;
    genop_str[330] = 65;
    genop_str[331] = 15;
    genop_str[332] = 182;
    genop_str[333] = 8;
    genop_str[334] = 73;
    genop_str[335] = 255;
    genop_str[336] = 192;
    genop_str[337] = 131;
    genop_str[338] = 225;
    genop_str[339] = 63;
    genop_str[340] = 9;
    genop_str[341] = 200;
    genop_str[342] = 235;
    genop_str[343] = 33;
    genop_str[344] = 131;
    genop_str[345] = 224;
    genop_str[346] = 15;
    genop_str[347] = 193;
    genop_str[348] = 224;
    genop_str[349] = 6;
    genop_str[350] = 65;
    genop_str[351] = 15;
    genop_str[352] = 182;
    genop_str[353] = 8;
    genop_str[354] = 73;
    genop_str[355] = 255;
    genop_str[356] = 192;
    genop_str[357] = 131;
    genop_str[358] = 225;
    genop_str[359] = 63;
    genop_str[360] = 9;
    genop_str[361] = 200;
    genop_str[362] = 193;
    genop_str[363] = 224;
    genop_str[364] = 6;
    genop_str[365] = 65;
    genop_str[366] = 15;
    genop_str[367] = 182;
    genop_str[368] = 8;
    genop_str[369] = 73;
    genop_str[370] = 255;
    genop_str[371] = 192;
    genop_str[372] = 131;
    genop_str[373] = 225;
    genop_str[374] = 63;
    genop_str[375] = 9;
    genop_str[376] = 200;
    genop_str[377] = 65;
    genop_str[378] = 137;
    genop_str[379] = 196;
    genop_str[380] = 65;
    genop_str[381] = 15;
    genop_str[382] = 182;
    genop_str[383] = 2;
    genop_str[384] = 73;
    genop_str[385] = 255;
    genop_str[386] = 194;
    genop_str[387] = 61;
    genop_str[388] = 128;
    genop_str[389] = 0;
    genop_str[390] = 0;
    genop_str[391] = 0;
    genop_str[392] = 114;
    genop_str[393] = 117;
    genop_str[394] = 61;
    genop_str[395] = 224;
    genop_str[396] = 0;
    genop_str[397] = 0;
    genop_str[398] = 0;
    genop_str[399] = 114;
    genop_str[400] = 57;
    genop_str[401] = 61;
    genop_str[402] = 240;
    genop_str[403] = 0;
    genop_str[404] = 0;
    genop_str[405] = 0;
    genop_str[406] = 114;
    genop_str[407] = 70;
    genop_str[408] = 131;
    genop_str[409] = 224;
    genop_str[410] = 7;
    genop_str[411] = 193;
    genop_str[412] = 224;
    genop_str[413] = 6;
    genop_str[414] = 65;
    genop_str[415] = 15;
    genop_str[416] = 182;
    genop_str[417] = 10;
    genop_str[418] = 73;
    genop_str[419] = 255;
    genop_str[420] = 194;
    genop_str[421] = 131;
    genop_str[422] = 225;
    genop_str[423] = 63;
    genop_str[424] = 9;
    genop_str[425] = 200;
    genop_str[426] = 193;
    genop_str[427] = 224;
    genop_str[428] = 6;
    genop_str[429] = 65;
    genop_str[430] = 15;
    genop_str[431] = 182;
    genop_str[432] = 10;
    genop_str[433] = 73;
    genop_str[434] = 255;
    genop_str[435] = 194;
    genop_str[436] = 131;
    genop_str[437] = 225;
    genop_str[438] = 63;
    genop_str[439] = 9;
    genop_str[440] = 200;
    genop_str[441] = 193;
    genop_str[442] = 224;
    genop_str[443] = 6;
    genop_str[444] = 65;
    genop_str[445] = 15;
    genop_str[446] = 182;
    genop_str[447] = 10;
    genop_str[448] = 73;
    genop_str[449] = 255;
    genop_str[450] = 194;
    genop_str[451] = 131;
    genop_str[452] = 225;
    genop_str[453] = 63;
    genop_str[454] = 9;
    genop_str[455] = 200;
    genop_str[456] = 235;
    genop_str[457] = 53;
    genop_str[458] = 131;
    genop_str[459] = 224;
    genop_str[460] = 31;
    genop_str[461] = 193;
    genop_str[462] = 224;
    genop_str[463] = 6;
    genop_str[464] = 65;
    genop_str[465] = 15;
    genop_str[466] = 182;
    genop_str[467] = 10;
    genop_str[468] = 73;
    genop_str[469] = 255;
    genop_str[470] = 194;
    genop_str[471] = 131;
    genop_str[472] = 225;
    genop_str[473] = 63;
    genop_str[474] = 9;
    genop_str[475] = 200;
    genop_str[476] = 235;
    genop_str[477] = 33;
    genop_str[478] = 131;
    genop_str[479] = 224;
    genop_str[480] = 15;
    genop_str[481] = 193;
    genop_str[482] = 224;
    genop_str[483] = 6;
    genop_str[484] = 65;
    genop_str[485] = 15;
    genop_str[486] = 182;
    genop_str[487] = 10;
    genop_str[488] = 73;
    genop_str[489] = 255;
    genop_str[490] = 194;
    genop_str[491] = 131;
    genop_str[492] = 225;
    genop_str[493] = 63;
    genop_str[494] = 9;
    genop_str[495] = 200;
    genop_str[496] = 193;
    genop_str[497] = 224;
    genop_str[498] = 6;
    genop_str[499] = 65;
    genop_str[500] = 15;
    genop_str[501] = 182;
    genop_str[502] = 10;
    genop_str[503] = 73;
    genop_str[504] = 255;
    genop_str[505] = 194;
    genop_str[506] = 131;
    genop_str[507] = 225;
    genop_str[508] = 63;
    genop_str[509] = 9;
    genop_str[510] = 200;
    genop_str[511] = 65;
    genop_str[512] = 137;
    genop_str[513] = 197;
    genop_str[514] = 69;
    genop_str[515] = 57;
    genop_str[516] = 236;
    genop_str[517] = 117;
    genop_str[518] = 14;
    genop_str[519] = 233;
    genop_str[520] = 216;
    genop_str[521] = 254;
    genop_str[522] = 255;
    genop_str[523] = 255;
    genop_str[524] = 77;
    genop_str[525] = 57;
    genop_str[526] = 218;
    genop_str[527] = 114;
    genop_str[528] = 8;
    genop_str[529] = 235;
    genop_str[530] = 28;
    genop_str[531] = 235;
    genop_str[532] = 15;
    genop_str[533] = 124;
    genop_str[534] = 2;
    genop_str[535] = 235;
    genop_str[536] = 11;
    genop_str[537] = 65;
    genop_str[538] = 190;
    genop_str[539] = 255;
    genop_str[540] = 255;
    genop_str[541] = 255;
    genop_str[542] = 255;
    genop_str[543] = 233;
    genop_str[544] = 176;
    genop_str[545] = 1;
    genop_str[546] = 0;
    genop_str[547] = 0;
    genop_str[548] = 65;
    genop_str[549] = 190;
    genop_str[550] = 1;
    genop_str[551] = 0;
    genop_str[552] = 0;
    genop_str[553] = 0;
    genop_str[554] = 233;
    genop_str[555] = 165;
    genop_str[556] = 1;
    genop_str[557] = 0;
    genop_str[558] = 0;
    genop_str[559] = 69;
    genop_str[560] = 49;
    genop_str[561] = 246;
    genop_str[562] = 233;
    genop_str[563] = 157;
    genop_str[564] = 1;
    genop_str[565] = 0;
    genop_str[566] = 0;
    genop_str[567] = 131;
    genop_str[568] = 250;
    genop_str[569] = 31;
    genop_str[570] = 116;
    genop_str[571] = 32;
    genop_str[572] = 131;
    genop_str[573] = 250;
    genop_str[574] = 32;
    genop_str[575] = 15;
    genop_str[576] = 132;
    genop_str[577] = 168;
    genop_str[578] = 0;
    genop_str[579] = 0;
    genop_str[580] = 0;
    genop_str[581] = 131;
    genop_str[582] = 250;
    genop_str[583] = 6;
    genop_str[584] = 15;
    genop_str[585] = 130;
    genop_str[586] = 227;
    genop_str[587] = 1;
    genop_str[588] = 0;
    genop_str[589] = 0;
    genop_str[590] = 131;
    genop_str[591] = 250;
    genop_str[592] = 11;
    genop_str[593] = 15;
    genop_str[594] = 135;
    genop_str[595] = 218;
    genop_str[596] = 1;
    genop_str[597] = 0;
    genop_str[598] = 0;
    genop_str[599] = 233;
    genop_str[600] = 4;
    genop_str[601] = 1;
    genop_str[602] = 0;
    genop_str[603] = 0;
    genop_str[604] = 68;
    genop_str[605] = 139;
    genop_str[606] = 47;
    genop_str[607] = 68;
    genop_str[608] = 59;
    genop_str[609] = 46;
    genop_str[610] = 15;
    genop_str[611] = 133;
    genop_str[612] = 201;
    genop_str[613] = 1;
    genop_str[614] = 0;
    genop_str[615] = 0;
    genop_str[616] = 68;
    genop_str[617] = 59;
    genop_str[618] = 41;
    genop_str[619] = 15;
    genop_str[620] = 133;
    genop_str[621] = 192;
    genop_str[622] = 1;
    genop_str[623] = 0;
    genop_str[624] = 0;
    genop_str[625] = 76;
    genop_str[626] = 139;
    genop_str[627] = 87;
    genop_str[628] = 8;
    genop_str[629] = 76;
    genop_str[630] = 139;
    genop_str[631] = 95;
    genop_str[632] = 16;
    genop_str[633] = 76;
    genop_str[634] = 139;
    genop_str[635] = 102;
    genop_str[636] = 8;
    genop_str[637] = 76;
    genop_str[638] = 139;
    genop_str[639] = 118;
    genop_str[640] = 16;
    genop_str[641] = 76;
    genop_str[642] = 139;
    genop_str[643] = 121;
    genop_str[644] = 8;
    genop_str[645] = 72;
    genop_str[646] = 139;
    genop_str[647] = 89;
    genop_str[648] = 16;
    genop_str[649] = 76;
    genop_str[650] = 137;
    genop_str[651] = 216;
    genop_str[652] = 76;
    genop_str[653] = 1;
    genop_str[654] = 240;
    genop_str[655] = 72;
    genop_str[656] = 57;
    genop_str[657] = 216;
    genop_str[658] = 15;
    genop_str[659] = 135;
    genop_str[660] = 141;
    genop_str[661] = 1;
    genop_str[662] = 0;
    genop_str[663] = 0;
    genop_str[664] = 76;
    genop_str[665] = 137;
    genop_str[666] = 255;
    genop_str[667] = 76;
    genop_str[668] = 137;
    genop_str[669] = 214;
    genop_str[670] = 76;
    genop_str[671] = 137;
    genop_str[672] = 218;
    genop_str[673] = 65;
    genop_str[674] = 131;
    genop_str[675] = 253;
    genop_str[676] = 4;
    genop_str[677] = 116;
    genop_str[678] = 4;
    genop_str[679] = 72;
    genop_str[680] = 107;
    genop_str[681] = 210;
    genop_str[682] = 8;
    genop_str[683] = 72;
    genop_str[684] = 133;
    genop_str[685] = 210;
    genop_str[686] = 116;
    genop_str[687] = 15;
    genop_str[688] = 138;
    genop_str[689] = 6;
    genop_str[690] = 136;
    genop_str[691] = 7;
    genop_str[692] = 72;
    genop_str[693] = 255;
    genop_str[694] = 198;
    genop_str[695] = 72;
    genop_str[696] = 255;
    genop_str[697] = 199;
    genop_str[698] = 72;
    genop_str[699] = 255;
    genop_str[700] = 202;
    genop_str[701] = 235;
    genop_str[702] = 236;
    genop_str[703] = 76;
    genop_str[704] = 137;
    genop_str[705] = 230;
    genop_str[706] = 76;
    genop_str[707] = 137;
    genop_str[708] = 242;
    genop_str[709] = 65;
    genop_str[710] = 131;
    genop_str[711] = 253;
    genop_str[712] = 4;
    genop_str[713] = 116;
    genop_str[714] = 4;
    genop_str[715] = 72;
    genop_str[716] = 107;
    genop_str[717] = 210;
    genop_str[718] = 8;
    genop_str[719] = 72;
    genop_str[720] = 133;
    genop_str[721] = 210;
    genop_str[722] = 116;
    genop_str[723] = 15;
    genop_str[724] = 138;
    genop_str[725] = 6;
    genop_str[726] = 136;
    genop_str[727] = 7;
    genop_str[728] = 72;
    genop_str[729] = 255;
    genop_str[730] = 198;
    genop_str[731] = 72;
    genop_str[732] = 255;
    genop_str[733] = 199;
    genop_str[734] = 72;
    genop_str[735] = 255;
    genop_str[736] = 202;
    genop_str[737] = 235;
    genop_str[738] = 236;
    genop_str[739] = 76;
    genop_str[740] = 137;
    genop_str[741] = 248;
    genop_str[742] = 76;
    genop_str[743] = 137;
    genop_str[744] = 218;
    genop_str[745] = 76;
    genop_str[746] = 1;
    genop_str[747] = 242;
    genop_str[748] = 195;
    genop_str[749] = 68;
    genop_str[750] = 139;
    genop_str[751] = 47;
    genop_str[752] = 68;
    genop_str[753] = 59;
    genop_str[754] = 41;
    genop_str[755] = 15;
    genop_str[756] = 133;
    genop_str[757] = 56;
    genop_str[758] = 1;
    genop_str[759] = 0;
    genop_str[760] = 0;
    genop_str[761] = 76;
    genop_str[762] = 139;
    genop_str[763] = 87;
    genop_str[764] = 8;
    genop_str[765] = 76;
    genop_str[766] = 139;
    genop_str[767] = 95;
    genop_str[768] = 16;
    genop_str[769] = 76;
    genop_str[770] = 139;
    genop_str[771] = 102;
    genop_str[772] = 8;
    genop_str[773] = 76;
    genop_str[774] = 139;
    genop_str[775] = 121;
    genop_str[776] = 8;
    genop_str[777] = 72;
    genop_str[778] = 139;
    genop_str[779] = 89;
    genop_str[780] = 16;
    genop_str[781] = 76;
    genop_str[782] = 137;
    genop_str[783] = 216;
    genop_str[784] = 72;
    genop_str[785] = 255;
    genop_str[786] = 192;
    genop_str[787] = 72;
    genop_str[788] = 57;
    genop_str[789] = 216;
    genop_str[790] = 15;
    genop_str[791] = 135;
    genop_str[792] = 9;
    genop_str[793] = 1;
    genop_str[794] = 0;
    genop_str[795] = 0;
    genop_str[796] = 76;
    genop_str[797] = 137;
    genop_str[798] = 255;
    genop_str[799] = 76;
    genop_str[800] = 137;
    genop_str[801] = 214;
    genop_str[802] = 76;
    genop_str[803] = 137;
    genop_str[804] = 218;
    genop_str[805] = 65;
    genop_str[806] = 131;
    genop_str[807] = 253;
    genop_str[808] = 4;
    genop_str[809] = 116;
    genop_str[810] = 4;
    genop_str[811] = 72;
    genop_str[812] = 107;
    genop_str[813] = 210;
    genop_str[814] = 8;
    genop_str[815] = 72;
    genop_str[816] = 133;
    genop_str[817] = 210;
    genop_str[818] = 116;
    genop_str[819] = 15;
    genop_str[820] = 138;
    genop_str[821] = 6;
    genop_str[822] = 136;
    genop_str[823] = 7;
    genop_str[824] = 72;
    genop_str[825] = 255;
    genop_str[826] = 198;
    genop_str[827] = 72;
    genop_str[828] = 255;
    genop_str[829] = 199;
    genop_str[830] = 72;
    genop_str[831] = 255;
    genop_str[832] = 202;
    genop_str[833] = 235;
    genop_str[834] = 236;
    genop_str[835] = 65;
    genop_str[836] = 131;
    genop_str[837] = 253;
    genop_str[838] = 4;
    genop_str[839] = 117;
    genop_str[840] = 7;
    genop_str[841] = 68;
    genop_str[842] = 136;
    genop_str[843] = 224;
    genop_str[844] = 136;
    genop_str[845] = 7;
    genop_str[846] = 235;
    genop_str[847] = 6;
    genop_str[848] = 76;
    genop_str[849] = 137;
    genop_str[850] = 224;
    genop_str[851] = 72;
    genop_str[852] = 137;
    genop_str[853] = 7;
    genop_str[854] = 76;
    genop_str[855] = 137;
    genop_str[856] = 248;
    genop_str[857] = 76;
    genop_str[858] = 137;
    genop_str[859] = 218;
    genop_str[860] = 72;
    genop_str[861] = 255;
    genop_str[862] = 194;
    genop_str[863] = 195;
    genop_str[864] = 76;
    genop_str[865] = 139;
    genop_str[866] = 71;
    genop_str[867] = 8;
    genop_str[868] = 76;
    genop_str[869] = 139;
    genop_str[870] = 86;
    genop_str[871] = 8;
    genop_str[872] = 76;
    genop_str[873] = 139;
    genop_str[874] = 95;
    genop_str[875] = 16;
    genop_str[876] = 76;
    genop_str[877] = 139;
    genop_str[878] = 102;
    genop_str[879] = 16;
    genop_str[880] = 77;
    genop_str[881] = 137;
    genop_str[882] = 221;
    genop_str[883] = 77;
    genop_str[884] = 57;
    genop_str[885] = 229;
    genop_str[886] = 77;
    genop_str[887] = 15;
    genop_str[888] = 71;
    genop_str[889] = 236;
    genop_str[890] = 49;
    genop_str[891] = 219;
    genop_str[892] = 139;
    genop_str[893] = 7;
    genop_str[894] = 76;
    genop_str[895] = 57;
    genop_str[896] = 235;
    genop_str[897] = 115;
    genop_str[898] = 43;
    genop_str[899] = 131;
    genop_str[900] = 248;
    genop_str[901] = 4;
    genop_str[902] = 116;
    genop_str[903] = 18;
    genop_str[904] = 77;
    genop_str[905] = 139;
    genop_str[906] = 52;
    genop_str[907] = 216;
    genop_str[908] = 77;
    genop_str[909] = 139;
    genop_str[910] = 60;
    genop_str[911] = 218;
    genop_str[912] = 77;
    genop_str[913] = 57;
    genop_str[914] = 254;
    genop_str[915] = 117;
    genop_str[916] = 34;
    genop_str[917] = 72;
    genop_str[918] = 255;
    genop_str[919] = 195;
    genop_str[920] = 235;
    genop_str[921] = 228;
    genop_str[922] = 69;
    genop_str[923] = 15;
    genop_str[924] = 182;
    genop_str[925] = 52;
    genop_str[926] = 24;
    genop_str[927] = 69;
    genop_str[928] = 15;
    genop_str[929] = 182;
    genop_str[930] = 60;
    genop_str[931] = 26;
    genop_str[932] = 69;
    genop_str[933] = 57;
    genop_str[934] = 254;
    genop_str[935] = 117;
    genop_str[936] = 18;
    genop_str[937] = 72;
    genop_str[938] = 255;
    genop_str[939] = 195;
    genop_str[940] = 235;
    genop_str[941] = 208;
    genop_str[942] = 77;
    genop_str[943] = 57;
    genop_str[944] = 227;
    genop_str[945] = 114;
    genop_str[946] = 12;
    genop_str[947] = 119;
    genop_str[948] = 18;
    genop_str[949] = 235;
    genop_str[950] = 24;
    genop_str[951] = 124;
    genop_str[952] = 6;
    genop_str[953] = 235;
    genop_str[954] = 12;
    genop_str[955] = 114;
    genop_str[956] = 2;
    genop_str[957] = 235;
    genop_str[958] = 8;
    genop_str[959] = 65;
    genop_str[960] = 190;
    genop_str[961] = 255;
    genop_str[962] = 255;
    genop_str[963] = 255;
    genop_str[964] = 255;
    genop_str[965] = 235;
    genop_str[966] = 13;
    genop_str[967] = 65;
    genop_str[968] = 190;
    genop_str[969] = 1;
    genop_str[970] = 0;
    genop_str[971] = 0;
    genop_str[972] = 0;
    genop_str[973] = 235;
    genop_str[974] = 5;
    genop_str[975] = 69;
    genop_str[976] = 49;
    genop_str[977] = 246;
    genop_str[978] = 235;
    genop_str[979] = 0;
    genop_str[980] = 131;
    genop_str[981] = 250;
    genop_str[982] = 6;
    genop_str[983] = 116;
    genop_str[984] = 29;
    genop_str[985] = 131;
    genop_str[986] = 250;
    genop_str[987] = 7;
    genop_str[988] = 116;
    genop_str[989] = 33;
    genop_str[990] = 131;
    genop_str[991] = 250;
    genop_str[992] = 8;
    genop_str[993] = 116;
    genop_str[994] = 37;
    genop_str[995] = 131;
    genop_str[996] = 250;
    genop_str[997] = 9;
    genop_str[998] = 116;
    genop_str[999] = 41;
    genop_str[1000] = 131;
    genop_str[1001] = 250;
    genop_str[1002] = 10;
    genop_str[1003] = 116;
    genop_str[1004] = 45;
    genop_str[1005] = 65;
    genop_str[1006] = 131;
    genop_str[1007] = 254;
    genop_str[1008] = 0;
    genop_str[1009] = 15;
    genop_str[1010] = 157;
    genop_str[1011] = 192;
    genop_str[1012] = 235;
    genop_str[1013] = 43;
    genop_str[1014] = 65;
    genop_str[1015] = 131;
    genop_str[1016] = 254;
    genop_str[1017] = 0;
    genop_str[1018] = 15;
    genop_str[1019] = 148;
    genop_str[1020] = 192;
    genop_str[1021] = 235;
    genop_str[1022] = 34;
    genop_str[1023] = 65;
    genop_str[1024] = 131;
    genop_str[1025] = 254;
    genop_str[1026] = 0;
    genop_str[1027] = 15;
    genop_str[1028] = 149;
    genop_str[1029] = 192;
    genop_str[1030] = 235;
    genop_str[1031] = 25;
    genop_str[1032] = 65;
    genop_str[1033] = 131;
    genop_str[1034] = 254;
    genop_str[1035] = 0;
    genop_str[1036] = 15;
    genop_str[1037] = 156;
    genop_str[1038] = 192;
    genop_str[1039] = 235;
    genop_str[1040] = 16;
    genop_str[1041] = 65;
    genop_str[1042] = 131;
    genop_str[1043] = 254;
    genop_str[1044] = 0;
    genop_str[1045] = 15;
    genop_str[1046] = 158;
    genop_str[1047] = 192;
    genop_str[1048] = 235;
    genop_str[1049] = 7;
    genop_str[1050] = 65;
    genop_str[1051] = 131;
    genop_str[1052] = 254;
    genop_str[1053] = 0;
    genop_str[1054] = 15;
    genop_str[1055] = 159;
    genop_str[1056] = 192;
    genop_str[1057] = 15;
    genop_str[1058] = 182;
    genop_str[1059] = 192;
    genop_str[1060] = 195;
    genop_str[1061] = 184;
    genop_str[1062] = 60;
    genop_str[1063] = 0;
    genop_str[1064] = 0;
    genop_str[1065] = 0;
    genop_str[1066] = 191;
    genop_str[1067] = 71;
    genop_str[1068] = 0;
    genop_str[1069] = 0;
    genop_str[1070] = 0;
    genop_str[1071] = 15;
    genop_str[1072] = 5;
    genop_str[1073] = 184;
    genop_str[1074] = 60;
    genop_str[1075] = 0;
    genop_str[1076] = 0;
    genop_str[1077] = 0;
    genop_str[1078] = 191;
    genop_str[1079] = 70;
    genop_str[1080] = 0;
    genop_str[1081] = 0;
    genop_str[1082] = 0;
    genop_str[1083] = 15;
    genop_str[1084] = 5;
    let path: Array[U8, 256] = Array.zeroed();
    let opath: Array[U8, 256] = Array.zeroed();
    let post: Array[Int, 201000] = Array.zeroed();
    let ps: Slice[Int] = slice(post, 0, 201000);
    // B0.3b-2/B0.3c: post[140000..141023] = fd (function table),
    // post[141024..198951] = sast (statement AST), post[198952..200999] = ctxi.
    // The views keep the old names; offsets below are relative to ctxi.
    //   0 st(16)  16 cs(16)  32 ck(64)  96 cje(64)  160 cstart(64)
    //   224 bloop(64)  288 bpos(64)  352 rname(64)  416 fname(128)
    //   544 flabel(128)  672 fparams(16)  688 fpelem(16)  704 fret(128)
    //   832 fret_t1(128)  960 fret_t2(128)  1088 fret_ty(128)
    //   1216 NF, 1217 DLEN, 1218 CD, 1219 NBRK, 1220 HAVE_RET (unused)
    //   1221 cjmp(64)
    let ctxi: Slice[Int] = slice_at(ps, 198952, 2048);
    let st: Slice[Int] = slice_at(ctxi, 0, 16);
    let cs: Slice[Int] = slice_at(ctxi, 16, 16);
    let fd: Slice[Int] = slice_at(ps, 140000, 1024);
    let fname: Slice[Int] = slice_at(ctxi, 416, 128);
    let flabel: Slice[Int] = slice_at(ctxi, 544, 128);
    let fparams: Slice[Int] = slice_at(ctxi, 672, 16);
    let fpelem: Slice[Int] = slice_at(ctxi, 688, 16);
    let fret: Slice[Int] = slice_at(ctxi, 704, 128);
    let fret_t1: Slice[Int] = slice_at(ctxi, 832, 128);
    let fret_t2: Slice[Int] = slice_at(ctxi, 960, 128);
    let fret_ty: Slice[Int] = slice_at(ctxi, 1088, 128);
    let rname: Slice[Int] = slice_at(ctxi, 352, 64);
    let ck: Slice[Int] = slice_at(ctxi, 32, 64);
    let cje: Slice[Int] = slice_at(ctxi, 96, 64);
    let cstart: Slice[Int] = slice_at(ctxi, 160, 64);
    let cjmp: Slice[Int] = slice_at(ctxi, 1221, 64);
    let bpos: Slice[Int] = slice_at(ctxi, 288, 64);
    let bloop: Slice[Int] = slice_at(ctxi, 224, 64);
    let NF = 1216;
    let DLEN = 1217;
    let mkbuf: Array[U8, 8] = Array.zeroed();
    let mkst: Array[Int, 8] = Array.zeroed();
    let nf = 0;
    let dlen = 65536;
    st[6] = 0;

    if argc() < 3 { write("slice: usage: stage1-slice <in> <out>\n"); return 2; }
    let plen = arg_len(1);
    let i = 0;
    while i < plen { path[i] = arg_byte(1, i); i = i + 1; }
    let inp: Slice[U8] = slice(path, 0, plen);
    let n = read_file(inp, membuf, 294912);
    if n <= 0 { write("slice: read failed\n"); return 3; }
    if n >= 294912 { write("stage1: source too large\n"); return 3; }
    let olen = arg_len(2);
    i = 0;
    while i < olen { opath[i] = arg_byte(2, i); i = i + 1; }
    let oup: Slice[U8] = slice(opath, 0, olen);

    // membuf layout: source [0,294912), code [294912,1343488), data [1343488,1409024).
    let mem: Slice[U8] = slice(membuf, 0, 1409024);
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let pf = preflight(srcs, n);
    if pf != 0 { return pf; }
    let sf = scan_funcs(srcs, n, fd);
    if sf != 0 { return sf; }
    let cd = check_decls(srcs, fd, ps);
    if cd != 0 { return cd; }
    let cc = check_calls(srcs, fd);
    if cc != 0 { return cc; }
    let ss = scan_stmts(mem, ps, n);
    if ss != 0 { return ss; }
    let ds: Slice[U8] = slice_at(mem, 1343488, 65536);
    st[0] = 0; st[1] = n; st[3] = 0; st[4] = 0;

    let c: Slice[U8] = slice_at(mem, 294912, 1048576);
    cs[0] = 0; cs[2] = 0; cs[3] = 60000; cs[5] = 0; cs[6] = 40000;

    // Runtime block: argc, argv, path buffer.
    let runtime_off = dlen;
    dlen = dlen + 16 + 256;
    cs[7] = runtime_off;
    let heap_ptr_off = dlen;
    dlen = dlen + 24;
    post[17010] = heap_ptr_off;
    post[17011] = heap_ptr_off + 8;
    post[17012] = heap_ptr_off + 16;

    // arg_byte(i, pos) helper: rdi=i, rsi=pos -> rax=byte. One fixed call target.
    let argb_helper = cs[0];
    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = runtime_off + 8;
    cs[2] = cs[2] + 1;
    emit4(c, cs, 0);
    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 4); emit1(c, cs, 248);
    emit1(c, cs, 15); emit1(c, cs, 182); emit1(c, cs, 4); emit1(c, cs, 48);
    emit1(c, cs, 195);
    cs[8] = argb_helper;

    // Runtime helper for generic Str + / comparisons (flat binary copied into code).
    let genop_label = cs[0];
    let genop_i = 0;
    while genop_i < 1085 {
        emit1(c, cs, genop_str[genop_i]);
        genop_i = genop_i + 1;
    }
    cs[15] = genop_label;

    // Intern "main" so the final trampoline can find it by name id.
    mkbuf[0] = 109; mkbuf[1] = 97; mkbuf[2] = 105; mkbuf[3] = 110;
    mkst[0] = 0; mkst[1] = 4;
    let mks: Slice[U8] = slice(mkbuf, 0, 4);
    let mksts: Slice[Int] = slice(mkst, 0, 8);
    let main_nid = name_id(mks, mksts, ps);

    // Intern built-in Option/Result vocabulary.
    mkbuf[0] = 79; mkbuf[1] = 112; mkbuf[2] = 116; mkbuf[3] = 105; mkbuf[4] = 111; mkbuf[5] = 110;
    mkst[0] = 0; mkst[1] = 6;
    post[17002] = name_id(mks, mksts, ps);
    mkbuf[0] = 82; mkbuf[1] = 101; mkbuf[2] = 115; mkbuf[3] = 117; mkbuf[4] = 108; mkbuf[5] = 116;
    mkst[0] = 0; mkst[1] = 6;
    post[17003] = name_id(mks, mksts, ps);
    mkbuf[0] = 83; mkbuf[1] = 111; mkbuf[2] = 109; mkbuf[3] = 101;
    mkst[0] = 0; mkst[1] = 4;
    post[17004] = name_id(mks, mksts, ps);
    mkbuf[0] = 78; mkbuf[1] = 111; mkbuf[2] = 110; mkbuf[3] = 101;
    mkst[0] = 0; mkst[1] = 4;
    post[17005] = name_id(mks, mksts, ps);
    mkbuf[0] = 79; mkbuf[1] = 107;
    mkst[0] = 0; mkst[1] = 2;
    post[17006] = name_id(mks, mksts, ps);
    mkbuf[0] = 69; mkbuf[1] = 114; mkbuf[2] = 114;
    mkst[0] = 0; mkst[1] = 3;
    post[17007] = name_id(mks, mksts, ps);

    ctxi[NF] = nf;
    ctxi[DLEN] = dlen;
    let eb = emit_body(mem, ps, n);
    if eb != 0 { return eb; }
    nf = ctxi[NF];
    dlen = ctxi[DLEN];
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
    if main_found == 0 { if nf == 0 { write("slice: missing main\n"); return 4; } main_i = nf - 1; }
    let entry_off = cs[0];
    // Initialise the runtime bump heap (BSS region after static data).
    let heap_start_off = dlen;
    emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = heap_start_off;
    cs[2] = cs[2] + 1;
    emit4(c, cs, 0);
    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = post[17011];
    cs[2] = cs[2] + 1;
    emit4(c, cs, 0);
    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = post[17010];
    cs[2] = cs[2] + 1;
    emit4(c, cs, 0);
    emit1(c, cs, 72); emit1(c, cs, 185);
    emit1(c, cs, 0); emit1(c, cs, 0); emit1(c, cs, 16); emit1(c, cs, 0);
    emit1(c, cs, 0); emit1(c, cs, 0); emit1(c, cs, 0); emit1(c, cs, 0);
    emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 200);
    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = post[17012];
    cs[2] = cs[2] + 1;
    emit4(c, cs, 0);

    // Save argc/argv before calling main.
    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 4); emit1(c, cs, 36); // rax=[rsp]
    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = cs[7];
    cs[2] = cs[2] + 1;
    emit4(c, cs, 0);
    emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 68); emit1(c, cs, 36); emit1(c, cs, 8); // lea rax,[rsp+8]
    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
    ps[cs[3] + cs[2] * 2] = cs[0];
    ps[cs[3] + cs[2] * 2 + 1] = cs[7] + 8;
    cs[2] = cs[2] + 1;
    emit4(c, cs, 0);
    emit1(c, cs, 232);
    let callpos = cs[0];
    emit4(c, cs, flabel[main_i] - (callpos + 4));
    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 199);
    emit1(c, cs, 184); emit4(c, cs, 60);
    emit1(c, cs, 15); emit1(c, cs, 5);

    let clen = cs[0];
    if dlen > 2147483647 {
        write("stage1: data layout exceeds 2GiB\n");
        return 4;
    }
    let code_vaddr = 4194424;
    let data_vaddr = code_vaddr + clen;
    i = 0;
    while i < cs[2] {
        let pos = ps[cs[3] + i * 2];
        let off = ps[cs[3] + i * 2 + 1];
        let disp = data_vaddr + off - (code_vaddr + pos + 4);
        if disp > 2147483647 || disp < 0 - 2147483648 {
            write("stage1: data offset exceeds RIP-relative disp32\n");
            return 4;
        }
        put32(c, pos, disp);
        i = i + 1;
    }
    let total = 120 + clen + dlen + 1048576;
    let filetotal = 120 + clen + st[6];
    let o: Slice[U8] = slice(out, 0, 1048576);
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
    let src_code: Slice[U8] = slice_at(c, 0, clen);
    copy(dst_code, src_code, clen);
    let dst_data: Slice[U8] = slice(out, 120 + clen, st[6]);
    let src_data: Slice[U8] = slice_at(ds, 0, st[6]);
    copy(dst_data, src_data, st[6]);
    if write_file(oup, out, filetotal) < 0 { write("slice: write failed\n"); return 5; }
    write("slice ok\n");
    return 0;
}
