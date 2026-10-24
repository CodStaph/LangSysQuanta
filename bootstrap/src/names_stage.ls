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
fn preflight(src: Slice[U8], n: Int, post: Slice[Int]) -> Int {
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
            // B3-4c: region frames / Buffer owner ids need the runtime region state.
            if len == 6 && ((src[start] == 114 && src[start + 1] == 101 && src[start + 2] == 103 && src[start + 3] == 105 && src[start + 4] == 111 && src[start + 5] == 110) || (src[start] == 66 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114)) {
                post[17017] = 1;
            }
            if len >= 7 && src[start] == 98 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 && src[start + 6] == 95 {
                post[17017] = 1;
            }
            if len == 7 && src[start] == 101 && src[start + 1] == 110 && src[start + 2] == 115 && src[start + 3] == 117 && src[start + 4] == 114 && src[start + 5] == 101 && src[start + 6] == 115 {
                write("stage1: E-LS-UNSUPPORTED: ensures clauses are not implemented in B-LS yet\n");
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
    if vi >= 0 && (post[50004 + vi * 4] & 255) == 9 { return 1; }
    return 0;
}

fn var_span(dpos: Int, send: Int, val: Int) -> Int {
    return (dpos << 10) | (send << 30) | (val << 8);
}

fn var_set_ty(post: Slice[Int], vi: Int, ty: Int) -> Int {
    let meta = post[50004 + vi * 4];
    post[50004 + vi * 4] = (meta - (meta & 255)) | ty;
    return 0;
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

// Parse a concrete payload type: Int, U8, Str, Slice[U8], Slice[Int],
// Buffer[Int] (type 9; handle-sized, used by Buffer.try_new's Result).
fn parse_ty(src: Slice[U8], st: Slice[Int], n: Int) -> Int {
    skip(src, st, n);
    if st[0] >= n { st[3] = 1; return 0; }
    let c = src[st[0]];
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
    // R4.3: direct Str/Slice `+` used to be an integer add; require the
    // fallible builtins (str_try_concat / concat_into) instead.
    if op == 1 && (t1 == 3 || t1 == 4 || t1 == 5 || t2 == 3 || t2 == 4 || t2 == 5) {
        write("stage1: E-LS-UNSUPPORTED: Str/Slice + needs str_try_concat or concat_into\n");
        st[3] = 1;
        return 0;
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
            let vi = var_find(post, nid, st[4], st[0]);
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
                let vi = var_find(post, nid, st[4], st[0]);
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
                let vi = var_find(post, nid, st[4], st[0]);
                if vi >= 0 {
                    // R4.5: use the variable's real type so Buffer[Int] handles
                    // (type 9) survive parse_index (e.g. `Result.Ok(b)`).
                    let vty = post[50004 + vi * 4] & 255;
                    if vty == 0 { vty = 1; }
                    push_post(post, st, 1, vi);
                    set_ty(post, st, vty);
                } else {
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
            if st[5] == 6 && src[nstart] == 66 && src[nstart + 1] == 117 && src[nstart + 2] == 102 && src[nstart + 3] == 102 && src[nstart + 4] == 101 && src[nstart + 5] == 114 {
                // B3-2b/B3-3: Buffer.new[Int](cap, region) -> Buffer[Int] handle;
                // Buffer.try_new[Int](cap, region) -> Result[Buffer[Int], Int].
                if st[0] < n && src[st[0]] == 46 {
                    st[0] = st[0] + 1;
                    skip(src, st, n);
                    let cstart = st[0];
                    let ctor = name_id(src, st, post);
                    if st[5] == 3 && src[cstart] == 110 && src[cstart + 1] == 101 && src[cstart + 2] == 119 {
                        if st[13] == 0 { write("stage1: E-LS-UNSUPPORTED: Buffer.new is only allowed in a Buffer let initializer\n"); st[3] = 1; return 0; }
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
            } else if st[0] < n && src[st[0]] == 91 && var_is_buffer(post, name, st[4], st[0]) == 1 {
                // B3-4a: b[i] reads element i through buffer_get; out of range is -1.
                st[0] = st[0] + 1;
                skip(src, st, n);
                let bvi = var_find(post, name, st[4], st[0]);
                push_post(post, st, 1, bvi);
                parse_index(src, st, post);
                if st[3] != 0 { return 0; }
                let ity = post[110000 + st[2] - 1];
                if ity != 1 && ity != 2 { st[3] = 1; return 0; }
                if expect_char(src, st, 93, n) == 0 { st[3] = 1; return 0; }
                push_post(post, st, 60, 0);
                set_ty(post, st, 1);
                expect = 0;
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
            } else if st[0] < n && src[st[0]] == 46 && var_is_buffer(post, name, st[4], st[0]) == 1 {
                st[0] = st[0] + 1;
                skip(src, st, n);
                let fstart = st[0];
                let vf = name_id(src, st, post);
                if st[5] == 0 { st[3] = 1; return 0; }
                let bvi = var_find(post, name, st[4], st[0]);
                if st[5] == 3 && src[fstart] == 108 && src[fstart + 1] == 101 && src[fstart + 2] == 110 {
                    push_post(post, st, 1, bvi);
                    push_post(post, st, 57, 0);
                    set_ty(post, st, 1);
                    expect = 0;
                } else if st[5] == 3 && src[fstart] == 99 && src[fstart + 1] == 97 && src[fstart + 2] == 112 {
                    push_post(post, st, 1, bvi);
                    push_post(post, st, 58, 0);
                    set_ty(post, st, 1);
                    expect = 0;
                } else if st[5] == 4 && src[fstart] == 112 && src[fstart + 1] == 117 && src[fstart + 2] == 115 && src[fstart + 3] == 104 {
                    push_post(post, st, 1, bvi);
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
                    push_post(post, st, 1, bvi);
                    push_post(post, st, 62, 0);
                    set_ty(post, st, 1);
                    expect = 0;
                } else { st[3] = 1; return 0; }
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
                        let vi = var_find(post, name, st[4], st[0]);
                        if vi >= 0 {
                            let vty = post[50004 + vi * 4] & 255;
                            if vty == 0 { vty = 1; }
                            push_post(post, st, 1, vi);
                            set_ty(post, st, vty);
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
        post[cst[3] + cst[2] * 2 + 1] = post[50003 + val * 4];
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
    if kind == 54 {
        // arena_used(): current - base.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 55 {
        // arena_budget(): end - base.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17012]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 48 {
        // arena_alloc(n): 8-byte aligned bump allocation; -1 on exhaustion.
        emit1(code, cst, 88); // pop rax (n)
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 7); // add rax,7
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 224); emit1(code, cst, 248); // and rax,-8
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[current]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 202); // mov rdx,rcx
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 194); // add rdx,rax
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 29); // mov rbx,[end]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17012]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 218); // cmp rdx,rbx
        emit1(code, cst, 15); emit1(code, cst, 135);
        let jfail = cst[0]; emit4(code, cst, 0); // ja fail
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 21); // mov [current],rdx
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        // R4.2: high_water = max(high_water, current-base); allocs += 1.
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 208); // mov rax,rdx
        emit1(code, cst, 72); emit1(code, cst, 43); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // sub rax,[base]
        emit1(code, cst, 72); emit1(code, cst, 59); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17018]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // cmp rax,[high]
        emit1(code, cst, 15); emit1(code, cst, 134);
        let hw1 = cst[0]; emit4(code, cst, 0); // jbe
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17018]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [high]=rax
        patch_jump(code, hw1, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17019]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[allocs]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17019]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [allocs]=rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 200); // mov rax,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200); // sub rax,rcx
        emit1(code, cst, 80); // push offset
        emit1(code, cst, 233);
        let jdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, jfail, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17020]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[rejects]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17020]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [rejects]=rax
        emit1(code, cst, 72); emit1(code, cst, 184);
        let z = 0;
        while z < 8 { emit1(code, cst, 255); z = z + 1; }
        emit1(code, cst, 80);
        patch_jump(code, jdone, cst[0]);
        return 0;
    }
    if kind == 56 {
        // buffer_new(cap): header {data_off,len,cap,owner} (32 B) + data; -1 on failure.
        emit1(code, cst, 88); // pop rax (cap)
        emit1(code, cst, 80); // push cap for header init
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 224); emit1(code, cst, 3); // shl rax,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 32); // add rax,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 199); // mov rdi,rax
        emit1(code, cst, 232);
        let bcall = cst[0]; emit4(code, cst, 0);
        let bcn = post[217024 + 1399]; post[217024 + 1400 + bcn] = bcall; post[217024 + 1399] = bcn + 1;
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let bnfail = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194); // mov rdx,rax
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 198); emit1(code, cst, 32); // add rsi,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 49); // mov [rcx],rsi
        emit1(code, cst, 72); emit1(code, cst, 190);
        let z = 0; while z < 8 { emit1(code, cst, 0); z = z + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 113); emit1(code, cst, 8); // mov [rcx+8],rsi
        emit1(code, cst, 94); // pop rsi (cap)
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 113); emit1(code, cst, 16); // mov [rcx+16],rsi
        // B3-4c: owner = innermost region seq (0 at root).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17013]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[depth]
        emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 255); // xor rdi,rdi
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 132);
        let bnown = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 232); emit1(code, cst, 1); // sub rax,1
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17016]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rsi,[seq]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 60); emit1(code, cst, 198); // mov rdi,[rsi+rax*8]
        patch_jump(code, bnown, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 121); emit1(code, cst, 24); // mov [rcx+24],rdi
        emit1(code, cst, 82); // push handle
        emit1(code, cst, 233);
        let bndone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, bnfail, cst[0]);
        emit1(code, cst, 94); // pop cap
        emit1(code, cst, 72); emit1(code, cst, 184);
        z = 0; while z < 8 { emit1(code, cst, 255); z = z + 1; }
        emit1(code, cst, 80);
        patch_jump(code, bndone, cst[0]);
        return 0;
    }
    if kind == 57 || kind == 58 {
        // buffer_len(handle) / buffer_cap(handle).
        emit1(code, cst, 88); // pop rax (handle)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); // add rax,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 64);
        if kind == 57 { emit1(code, cst, 8); } else { emit1(code, cst, 16); }
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 59 {
        // buffer_push(handle, value): returns new len or -1 when full.
        emit1(code, cst, 90); // pop rdx (value)
        emit1(code, cst, 88); // pop rax (handle)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); // add rax,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 112); emit1(code, cst, 8); // mov rsi,[rax+8]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 120); emit1(code, cst, 16); // mov rdi,[rax+16]
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 254); // cmp rsi,rdi
        emit1(code, cst, 15); emit1(code, cst, 131);
        let bpfail = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 56); // mov rdi,[rax]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 207); // add rdi,rcx
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 20); emit1(code, cst, 247); // mov [rdi+rsi*8],rdx
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 198); emit1(code, cst, 1); // add rsi,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 112); emit1(code, cst, 8); // mov [rax+8],rsi
        emit1(code, cst, 86); // push rsi
        emit1(code, cst, 233);
        let bpdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, bpfail, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let q = 0; while q < 8 { emit1(code, cst, 255); q = q + 1; }
        emit1(code, cst, 80);
        patch_jump(code, bpdone, cst[0]);
        return 0;
    }
    if kind == 60 {
        // buffer_get(handle, index): value or -1 when out of range.
        emit1(code, cst, 90); // pop rdx (index)
        emit1(code, cst, 88); // pop rax (handle)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); // add rax,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 120); emit1(code, cst, 8); // mov rdi,[rax+8]
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 250); // cmp rdx,rdi
        emit1(code, cst, 15); emit1(code, cst, 131);
        let bgfail = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 56); // mov rdi,[rax]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 207); // add rdi,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 215); // mov rax,[rdi+rdx*8]
        emit1(code, cst, 80);
        emit1(code, cst, 233);
        let bgdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, bgfail, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let g = 0; while g < 8 { emit1(code, cst, 255); g = g + 1; }
        emit1(code, cst, 80);
        patch_jump(code, bgdone, cst[0]);
        return 0;
    }
    if kind == 61 {
        // B3-3: Buffer.try_new -> Result<Buffer[Int], Int> block at `val`.
        // Allocate header{data_off,len,cap} + data exactly like Buffer.new,
        // then write tag 0 (Ok, payload = handle) or tag 1 (Err, payload = -1).
        emit1(code, cst, 88); // pop rax (cap)
        emit1(code, cst, 80); // push cap (needed for the header init)
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 224); emit1(code, cst, 3); // shl rax,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 32); // add rax,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 199); // mov rdi,rax
        emit1(code, cst, 232);
        let tcall = cst[0]; emit4(code, cst, 0);
        let tcn = post[217024 + 1399]; post[217024 + 1400 + tcn] = tcall; post[217024 + 1399] = tcn + 1;
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let tfail = cst[0]; emit4(code, cst, 0);
        // Ok: header {handle+32, 0, cap, owner}; Result payload = handle (rdx).
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194); // mov rdx,rax
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 198); emit1(code, cst, 32); // add rsi,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 49); // mov [rcx],rsi
        emit1(code, cst, 72); emit1(code, cst, 190);
        let zz = 0; while zz < 8 { emit1(code, cst, 0); zz = zz + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 113); emit1(code, cst, 8); // mov [rcx+8],rsi
        emit1(code, cst, 94); // pop rsi (cap)
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 113); emit1(code, cst, 16); // mov [rcx+16],rsi
        // B3-4c: owner = innermost region seq (0 at root).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17013]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[depth]
        emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 255); // xor rdi,rdi
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 132);
        let tnown = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 232); emit1(code, cst, 1); // sub rax,1
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17016]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rsi,[seq]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 60); emit1(code, cst, 198); // mov rdi,[rsi+rax*8]
        patch_jump(code, tnown, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 121); emit1(code, cst, 24); // mov [rcx+24],rdi
        emit1(code, cst, 72); emit1(code, cst, 184);
        zz = 0; while zz < 8 { emit1(code, cst, 0); zz = zz + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 0
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=handle
        emit1(code, cst, 233);
        let tdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, tfail, cst[0]);
        // Err: drop cap, write tag 1 and the runtime failure code -1.
        emit1(code, cst, 94); // pop cap
        emit1(code, cst, 72); emit1(code, cst, 184);
        emit1(code, cst, 1);
        zz = 0; while zz < 7 { emit1(code, cst, 0); zz = zz + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 1
        emit1(code, cst, 72); emit1(code, cst, 184);
        zz = 0; while zz < 8 { emit1(code, cst, 255); zz = zz + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=-1
        patch_jump(code, tdone, cst[0]);
        // The Result value is the address of its block.
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rax,[blk]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 62 {
        // B3-4c: buffer_release(handle): owner must match the current region and the
        // allocation must be the arena top. 0 on success, -1 otherwise.
        emit1(code, cst, 88); // pop rax (handle)
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let rneg = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax (header)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 121); emit1(code, cst, 24); // mov rdi,[rcx+24] (owner)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17013]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rdx,[depth]
        emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 246); // xor rsi,rsi
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 250); emit1(code, cst, 0); // cmp rdx,0
        emit1(code, cst, 15); emit1(code, cst, 132);
        let rown = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 234); emit1(code, cst, 1); // sub rdx,1
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17016]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rsi,[seq]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 52); emit1(code, cst, 214); // mov rsi,[rsi+rdx*8]
        patch_jump(code, rown, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 254); // cmp rdi,rsi
        emit1(code, cst, 15); emit1(code, cst, 133);
        let rowner = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax (header)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 81); emit1(code, cst, 16); // mov rdx,[rcx+16] (cap)
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 226); emit1(code, cst, 3); // shl rdx,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 194); emit1(code, cst, 32); // add rdx,32
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 194); // add rdx,rax (end offset)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 202); // add rdx,rcx (end absolute)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rsi,[current]
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 214); // cmp rdx,rsi
        emit1(code, cst, 15); emit1(code, cst, 133);
        let rnottop = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov [current],rcx
        // R4.2: a successful LIFO release is a reclamation.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[reclaims]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [reclaims]=rax
        emit1(code, cst, 72); emit1(code, cst, 184);
        let rz = 0; while rz < 8 { emit1(code, cst, 0); rz = rz + 1; }
        emit1(code, cst, 233);
        let rdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, rneg, cst[0]);
        patch_jump(code, rnottop, cst[0]);
        patch_jump(code, rowner, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let rf = 0; while rf < 8 { emit1(code, cst, 255); rf = rf + 1; }
        patch_jump(code, rdone, cst[0]);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 63 {
        // B3-5a: buffer_set(handle, index, value): 0 on success, -1 when index >= len.
        emit1(code, cst, 90); // pop rdx (value)
        emit1(code, cst, 89); // pop rcx (index)
        emit1(code, cst, 88); // pop rax (handle)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rsi,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 240); // add rax,rsi (header)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 120); emit1(code, cst, 8); // mov rdi,[rax+8] (len)
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 249); // cmp rcx,rdi
        emit1(code, cst, 15); emit1(code, cst, 131);
        let bsfail = cst[0]; emit4(code, cst, 0); // jae fail (unsigned: negative -> fail)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 56); // mov rdi,[rax] (data_off)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rsi,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 247); // add rdi,rsi
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 20); emit1(code, cst, 207); // mov [rdi+rcx*8],rdx
        emit1(code, cst, 72); emit1(code, cst, 184);
        let sz = 0; while sz < 8 { emit1(code, cst, 0); sz = sz + 1; }
        emit1(code, cst, 233);
        let bsdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, bsfail, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let sf = 0; while sf < 8 { emit1(code, cst, 255); sf = sf + 1; }
        patch_jump(code, bsdone, cst[0]);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 64 {
        // R4.3: str_try_concat(a, b) -> Result<Str, AllocError>.
        // Str box at `val`; Result block at `val+32`; helper sets tag 9 on OOM.
        emit1(code, cst, 94); // pop rsi (box B)
        emit1(code, cst, 95); // pop rdi (box A)
        emit1(code, cst, 186); emit4(code, cst, 1); // mov edx,1 (op concat)
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rcx,[val]
        emit1(code, cst, 76); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea r8,[current]
        emit1(code, cst, 76); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17012]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea r9,[end]
        emit1(code, cst, 232);
        let scall = cst[0]; emit4(code, cst, cst[15] - (scall + 4));
        emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov eax,[val] (tag)
        emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 3); // cmp eax,3
        emit1(code, cst, 15); emit1(code, cst, 133);
        let serr = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 191);
        let so = 0; while so < 8 { emit1(code, cst, 0); so = so + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 32; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 0
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[strbox+8]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 40; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=ptr
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 16; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[strbox+16]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 48; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+16]=bytes
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 24; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[strbox+24]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 56; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+24]=chars
        emit1(code, cst, 233);
        let sdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, serr, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 191);
        emit1(code, cst, 1);
        let se = 0; while se < 7 { emit1(code, cst, 0); se = se + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 32; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 1
        emit1(code, cst, 72); emit1(code, cst, 191);
        let sf = 0; while sf < 8 { emit1(code, cst, 255); sf = sf + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 40; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=-1
        patch_jump(code, sdone, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val + 32; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rax,[blk]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 65 {
        // R4.2: arena_stat(sel) reads high_water/allocs/rejects/reclaims.
        let aslot = post[17018 + val];
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = aslot; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 66 {
        // R4.4: region_used() = current - (innermost region mark, else base).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17013]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[depth]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 132);
        let rug = cst[0]; emit4(code, cst, 0); // je root
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 232); emit1(code, cst, 1); // sub rax,1
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17015]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rcx,[mark]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 193); // mov rax,[rcx+rax*8]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[current]
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 193); // sub rcx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 200); // mov rax,rcx
        emit1(code, cst, 233);
        let rud = cst[0]; emit4(code, cst, 0);
        patch_jump(code, rug, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[current]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200); // sub rax,rcx
        patch_jump(code, rud, cst[0]);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 67 {
        // R4.4: arena_mark() = current - base (rewind token).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[current]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200); // sub rax,rcx
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 68 {
        // R4.4: arena_rewind(m): 0 on success, -1 when m > used or below the
        // innermost region mark (region accounting stays consistent).
        emit1(code, cst, 88); // pop rax (m)
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let rwneg = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[current]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rdx,[base]
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 209); // sub rcx,rdx
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 200); // cmp rax,rcx
        emit1(code, cst, 15); emit1(code, cst, 135);
        let rwabove = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17013]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[depth]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 249); emit1(code, cst, 0); // cmp rcx,0
        emit1(code, cst, 15); emit1(code, cst, 132);
        let rwdone = cst[0]; emit4(code, cst, 0); // je ok
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 233); emit1(code, cst, 1); // sub rcx,1
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17015]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rsi,[mark]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 52); emit1(code, cst, 206); // mov rsi,[rsi+rcx*8]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 194); // add rdx,rax (target abs)
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 242); // cmp rdx,rsi
        emit1(code, cst, 15); emit1(code, cst, 130);
        let rwbelow = cst[0]; emit4(code, cst, 0); // jb fail
        patch_jump(code, rwdone, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rdx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 194); // add rdx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov [current],rdx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[reclaims]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [reclaims]=rax
        emit1(code, cst, 72); emit1(code, cst, 184);
        let rwz = 0; while rwz < 8 { emit1(code, cst, 0); rwz = rwz + 1; }
        emit1(code, cst, 233);
        let rwok = cst[0]; emit4(code, cst, 0);
        patch_jump(code, rwneg, cst[0]);
        patch_jump(code, rwabove, cst[0]);
        patch_jump(code, rwbelow, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let rwf = 0; while rwf < 8 { emit1(code, cst, 255); rwf = rwf + 1; }
        patch_jump(code, rwok, cst[0]);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 69 {
        // R4.5: Result/Option variable load (block pointer; feeds `?`).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = val; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 32 {
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        // R4.2: reset is a reclamation event.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[reclaims]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [reclaims]=rax
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
        // R4.3: helper sets the output box tag to 9 when the destination is too
        // small (all-or-nothing); otherwise it returns (data, new_len) in rax/rdx.
        let rblk = post[100204 + cst[9]];
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = boxOut; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rcx,[boxOut]
        emit1(code, cst, 139); emit1(code, cst, 9); // mov ecx,[rcx] (tag)
        emit1(code, cst, 131); emit1(code, cst, 249); emit1(code, cst, 9); // cmp ecx,9
        emit1(code, cst, 15); emit1(code, cst, 132);
        let berr = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 191);
        let bo = 0; while bo < 8 { emit1(code, cst, 0); bo = bo + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = rblk; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [rblk]=tag 0
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = rblk + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [rblk+8]=base
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = rblk + 16; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [rblk+16]=len
        emit1(code, cst, 233);
        let bdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, berr, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 191);
        emit1(code, cst, 1);
        let be = 0; while be < 7 { emit1(code, cst, 0); be = be + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = rblk; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [rblk]=tag 1
        emit1(code, cst, 72); emit1(code, cst, 191);
        let bf = 0; while bf < 8 { emit1(code, cst, 255); bf = bf + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = rblk + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [rblk+8]=-1
        patch_jump(code, bdone, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = rblk; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rax,[rblk]
        emit1(code, cst, 80);
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
    let sast: Slice[Int] = slice_at(ps, 141024, 76000);
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
                    if sast[0] >= 12400 { write("stmts: too many statements\n"); return 4; }
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
    let ctxi: Slice[Int] = slice_at(ps, 217024, 2112);
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
    let lrd: Slice[Int] = slice_at(ctxi, 2048, 64);
    let NF = 1216;
    let DLEN = 1217;
    let CD = 1218;
    let NBRK = 1219;
    let SPAN_START = 1285;
    let SPAN_END = 1286;
    let RDEPTH = 1287;
    let CUR_SEND = 1368;
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let c: Slice[U8] = slice_at(mem, 393216, 786432);
    let ds: Slice[U8] = slice_at(mem, 1179648, 65536);
    let sast: Slice[Int] = slice_at(ps, 141024, 76000);
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
                // B3-4c: push a runtime region frame {mark, unique owner seq}.
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[depth]
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17015]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[mark]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rdx,[current]
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 20); emit1(c, cs, 193); // mov [rcx+rax*8],rdx
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17014]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rdx,[next]
                emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 194); emit1(c, cs, 1); // add rdx,1
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17014]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [next],rdx
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17016]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[seq]
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 20); emit1(c, cs, 193); // mov [rcx+rax*8],rdx
                emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 192); emit1(c, cs, 1); // add rax,1
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [depth],rax
                rname[rd] = rns;
                rlen[rd] = rnl;
                ctxi[RDEPTH] = rd + 1;
                fphase[top] = 1;
                let rblk = sast[noff + 3];
                if sp >= 256 { write("ast: too deep\n"); return 4; }
                fnodes[sp] = rblk; fphase[sp] = 0; fchild[sp] = 0 - 1; fd1[sp] = 0; fd2[sp] = 0; sp = sp + 1;
            } else {
                // B3-4c: pop the frame and rewind the arena to its entry mark.
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[depth]
                emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 232); emit1(c, cs, 1); // sub rax,1
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [depth],rax
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17015]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[mark]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 20); emit1(c, cs, 193); // mov rdx,[rcx+rax*8]
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [current],rdx
                // R4.2: closing a region frame is a reclamation event.
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17021]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[reclaims]
                emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 192); emit1(c, cs, 1); // add rax,1
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17021]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // [reclaims]=rax
                ctxi[RDEPTH] = ctxi[RDEPTH] - 1;
                sp = sp - 1;
            }
        } else if kind == K_BLOCK {
            if fphase[top] == 0 {
                fd2[top] = ctxi[CUR_SEND];
                ctxi[CUR_SEND] = sast[noff + 2];
                fphase[top] = 1;
                fchild[top] = sast[noff + 3];
            }
            if fchild[top] >= 0 {
                let child = fchild[top];
                fchild[top] = sast[257 + child * 6 + 4];
                if sp >= 256 { write("ast: too deep\n"); return 4; }
                fnodes[sp] = child; fphase[sp] = 0; fchild[sp] = 0 - 1; fd1[sp] = 0; fd2[sp] = 0; sp = sp + 1;
            } else {
                ctxi[CUR_SEND] = fd2[top];
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
                lrd[level] = ctxi[RDEPTH];
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
            if ctxi[RDEPTH] > lrd[ctxi[CD] - 1] { write("stage1: E-LS-UNSUPPORTED: break out of a region block is not implemented in B-LS yet\n"); return 4; }
            let jp = emit_jmp(c, cs);
            if ctxi[NBRK] >= 64 { write("ctl: too many breaks\n"); return 4; }
            bpos[ctxi[NBRK]] = jp;
            bloop[ctxi[NBRK]] = ctxi[CD] - 1;
            ctxi[NBRK] = ctxi[NBRK] + 1;
            sp = sp - 1;
        } else if kind == K_CONTINUE {
            if ctxi[CD] == 0 { write("ctl: continue outside loop\n"); return 4; }
            if ctxi[RDEPTH] > lrd[ctxi[CD] - 1] { write("stage1: E-LS-UNSUPPORTED: continue out of a region block is not implemented in B-LS yet\n"); return 4; }
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
    let ctxi: Slice[Int] = slice_at(ps, 217024, 2112);
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
    let lrd: Slice[Int] = slice_at(ctxi, 2048, 64);
    let NF = 1216;
    let DLEN = 1217;
    let CD = 1218;
    let NBRK = 1219;
    let HAVE_RET = 1220;
    let SPAN_START = 1285;
    let SPAN_END = 1286;
    let RDEPTH = 1287;
    let CUR_SEND = 1368;
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let c: Slice[U8] = slice_at(mem, 393216, 786432);
    let ds: Slice[U8] = slice_at(mem, 1179648, 65536);
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
            if ctxi[RDEPTH] > 0 {
                // B3-5c: `-> Int` functions unwind their region frames on return.
                if fret_ty[ctxi[NF]] != 1 { write("stage1: E-LS-UNSUPPORTED: return inside a region block is only implemented for -> Int functions\n"); return 4; }
                let ru = 0;
                while ru < ctxi[RDEPTH] {
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[depth]
                    emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 232); emit1(c, cs, 1); // sub rax,1
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [depth],rax
                    emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17015]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[mark]
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 20); emit1(c, cs, 193); // mov rdx,[rcx+rax*8]
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [current],rdx
                    ru = ru + 1;
                }
            }
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
            lrd[ctxi[CD]] = ctxi[RDEPTH];
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
            if ctxi[RDEPTH] > lrd[li] { write("stage1: E-LS-UNSUPPORTED: break out of a region block is not implemented in B-LS yet\n"); return 4; }
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
            if ctxi[RDEPTH] > lrd[li] { write("stage1: E-LS-UNSUPPORTED: continue out of a region block is not implemented in B-LS yet\n"); return 4; }
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
                    let vact = var_find(ps, vnm, ctxi[NF], st[0]);
                    let voff = 0;
                    if vact >= 0 {
                        voff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8;
                    } else {
                        let vi0 = var_find_any(ps, vnm, ctxi[NF]);
                        if vi0 >= 0 { voff = ps[50003 + vi0 * 4]; }
                        else { voff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8; }
                    }
                    let vi = var_add(ps, vnm, ctxi[NF], voff, var_span(st[0], ctxi[CUR_SEND], 0));
                    if rty == 100 { var_set_ty(ps, vi, 100); }
                    else { var_set_ty(ps, vi, 1); }
                    ps[cs[3] + cs[2] * 2 + 1] = voff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                }
                }
            } else {
            if expect_char(srcs, st, 58, n) == 0 { write("slice: expected :\n"); return 4; }
            skip(srcs, st, n);
            if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                // B3-2b: Buffer[Int] let, initializer is Buffer.new[Int](cap, rgn).
                if expect_char(srcs, st, 66, n) == 0 { write("let: expected Buffer\n"); return 4; }
                if expect_char(srcs, st, 117, n) == 0 { write("let: expected Buffer\n"); return 4; }
                if expect_char(srcs, st, 102, n) == 0 { write("let: expected Buffer\n"); return 4; }
                if expect_char(srcs, st, 102, n) == 0 { write("let: expected Buffer\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("let: expected Buffer\n"); return 4; }
                if expect_char(srcs, st, 114, n) == 0 { write("let: expected Buffer\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("let: expected [\n"); return 4; }
                if expect_char(srcs, st, 73, n) == 0 { write("let: expected Int\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("let: expected Int\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("let: expected Int\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("let: expected ]\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("let: expected =\n"); return 4; }
                let voff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 8;
                let vi = var_add(ps, vnm, ctxi[NF], voff, var_span(st[0], ctxi[CUR_SEND], 0));
                var_set_ty(ps, vi, 9);
                st[2] = 0;
                st[12] = ctxi[DLEN];
                st[13] = 1;
                parse_expr(srcs, st, ps);
                st[13] = 0;
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("let: bad Buffer expr\n"); return 4; }
                let rty = ps[110000 + st[2] - 1];
                if rty != 9 { write("stage1: E-LS-UNSUPPORTED: Buffer[Int] initializer must be Buffer.new\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = voff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                if expect_char(srcs, st, 59, n) == 0 { write("let: expected ;\n"); return 4; }
            } else if st[0] < n && srcs[st[0]] == 79 {

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
                            let bvi = var_find(ps, bname, ctxi[NF], st[0]);
                            if bvi >= 0 {
                                boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8;
                            } else {
                                let bany = var_find_any(ps, bname, ctxi[NF]);
                                if bany >= 0 { boff = ps[50003 + bany * 4]; }
                                else { boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8; }
                            }
                            let bvi2 = var_add(ps, bname, ctxi[NF], boff, var_span(st[0], ctxi[CUR_SEND], 0));
                            // B3-3: Result.Ok(b) over Buffer[Int] must remember the
                            // handle type so b.len/.cap/.push keep working in the arm.
                            if bty == 9 { var_set_ty(ps, bvi2, 9); }
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
            let mvi = var_find(ps, mnm, ctxi[NF], st[0]);
            if mvi < 0 { write("match: unknown subject\n"); return 4; }
            let moff = ps[50003 + mvi * 4];
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
                    let bvi = var_find(ps, bname, ctxi[NF], st[0]);
                    if bvi >= 0 {
                        boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8;
                    } else {
                        let bany = var_find_any(ps, bname, ctxi[NF]);
                        if bany >= 0 { boff = ps[50003 + bany * 4]; }
                        else { boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + 8; }
                    }
                    var_add(ps, bname, ctxi[NF], boff, var_span(st[0], ctxi[CUR_SEND], 0));
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
            if st[5] == 4 && srcs[nstart] == 100 && srcs[nstart + 1] == 114 && srcs[nstart + 2] == 111 && srcs[nstart + 3] == 112 && kw_end(srcs, nstart + 4, n) == 1 {
                // B3-4b: drop b; -> buffer_release(b) (LIFO only; status discarded).
                skip(srcs, st, n);
                let dnm = name_id(srcs, st, ps);
                if st[5] == 0 { write("drop: bad variable\n"); return 4; }
                let dvi = var_find(ps, dnm, ctxi[NF], st[0]);
                if dvi < 0 || (ps[50004 + dvi * 4] & 255) != 9 {
                    write("stage1: E-LS-UNSUPPORTED: drop is only implemented for Buffer[Int]\n");
                    return 4;
                }
                if expect_char(srcs, st, 59, n) == 0 { write("drop: expected ;\n"); return 4; }
                st[2] = 0;
                push_post(ps, st, 1, dvi);
                push_post(ps, st, 62, 0);
                set_ty(ps, st, 1);
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                // No longer a Buffer: later Buffer operations fail at compile time.
                var_set_ty(ps, dvi, 1);
                continue;
            }
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
            if var_is_buffer(ps, vnm, ctxi[NF], st[0]) == 1 {
                // B3-5a: b[i] = v -> buffer_set; status 0, or -1 when i >= len.
                let bvi = var_find(ps, vnm, ctxi[NF], st[0]);
                st[0] = st[0] + 1;
                st[2] = 0;
                push_post(ps, st, 1, bvi);
                parse_index(srcs, st, ps);
                if st[3] != 0 { write("buffer: bad index\n"); return 4; }
                let bity = ps[110000 + st[2] - 1];
                if bity != 1 && bity != 2 { write("buffer: index must be Int\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("buffer: expected ]\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("buffer: expected =\n"); return 4; }
                skip(srcs, st, n);
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("buffer: bad value\n"); return 4; }
                let bvty = ps[110000 + st[2] - 1];
                if bvty != 1 && bvty != 2 { write("buffer: value must be Int\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("buffer: expected ;\n"); return 4; }
                push_post(ps, st, 63, 0);
                set_ty(ps, st, 1);
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                continue;
            }
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
                let bvi = var_find(ps, vnm, ctxi[NF], st[0]);
                if bvi >= 0 && (ps[50004 + bvi * 4] & 255) == 9 {
                    st[0] = nstart;
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("buffer: bad expression\n"); return 4; }
                    if expect_char(srcs, st, 59, n) == 0 { write("buffer: expected ;\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    continue;
                }
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
                let vi = var_find(ps, vnm, ctxi[NF], st[0]);
                if vi < 0 { write("assign: unknown variable\n"); return 4; }
                // B3-4c: copying a Buffer handle could let a region-local allocation escape.
                if (ps[50004 + vi * 4] & 255) == 9 { write("stage1: E-LS-UNSUPPORTED: Buffer[Int] assignment is not implemented in B-LS yet\n"); return 4; }
                if ((ps[50004 + vi * 4] >> 8) & 1) == 1 { write("assign: val binding is immutable\n"); return 4; }
                let voff = ps[50003 + vi * 4];
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
    let ctxi: Slice[Int] = slice_at(ps, 217024, 2112);
    let st: Slice[Int] = slice_at(ctxi, 0, 16);
    let cs: Slice[Int] = slice_at(ctxi, 16, 16);
    let fname: Slice[Int] = slice_at(ctxi, 416, 128);
    let flabel: Slice[Int] = slice_at(ctxi, 544, 128);
    let fparams: Slice[Int] = slice_at(ctxi, 672, 16);
    let fpelem: Slice[Int] = slice_at(ctxi, 688, 16);
    let fval: Slice[Int] = slice_at(ctxi, 1352, 16);
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
    let CUR_SEND = 1368;
    // membuf layout: src [0,393216), code [393216,1179648), data [1179648,1245184).
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let c: Slice[U8] = slice_at(mem, 393216, 786432);
    let ds: Slice[U8] = slice_at(mem, 1179648, 65536);
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
                let vmode = 0;
                if st[0] + 3 <= n && srcs[st[0]] == 118 && srcs[st[0] + 1] == 97 && srcs[st[0] + 2] == 108 && kw_end(srcs, st[0] + 3, n) == 1 {
                    let vp = st[0] + 3;
                    while vp < n && (srcs[vp] == 32 || srcs[vp] == 9 || srcs[vp] == 10 || srcs[vp] == 13) { vp = vp + 1; }
                    if vp < n && is_ident_byte(srcs[vp]) == 1 {
                        // B2: `val x: T` is an immutable by-value binding.
                        vmode = 1;
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
                fval[pc] = vmode;
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
                    let vi0 = var_find_any(ps, pid, ctxi[NF]);
                    let off = 0;
                    if vi0 >= 0 { off = ps[50003 + vi0 * 4]; }
                    else {
                        off = ctxi[DLEN];
                        ctxi[DLEN] = ctxi[DLEN] + 8;
                    }
                    let vi = var_add(ps, pid, ctxi[NF], off, var_span(0, n, fval[i]));
                    if pe == 100 { var_set_ty(ps, vi, 100); }
                    else { var_set_ty(ps, vi, 1); }
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
    let membuf: Array[U8, 1245184] = Array.zeroed();
    let out: Array[U8, 610000] = Array.zeroed();
    let genop_str: Array[U8, 1160] = Array.zeroed();
    genop_str[0] = 139;
    genop_str[1] = 7;
    genop_str[2] = 59;
    genop_str[3] = 6;
    genop_str[4] = 15;
    genop_str[5] = 133;
    genop_str[6] = 114;
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
    genop_str[20] = 100;
    genop_str[21] = 2;
    genop_str[22] = 0;
    genop_str[23] = 0;
    genop_str[24] = 131;
    genop_str[25] = 248;
    genop_str[26] = 5;
    genop_str[27] = 15;
    genop_str[28] = 132;
    genop_str[29] = 91;
    genop_str[30] = 2;
    genop_str[31] = 0;
    genop_str[32] = 0;
    genop_str[33] = 233;
    genop_str[34] = 86;
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
    genop_str[48] = 72;
    genop_str[49] = 4;
    genop_str[50] = 0;
    genop_str[51] = 0;
    genop_str[52] = 131;
    genop_str[53] = 250;
    genop_str[54] = 11;
    genop_str[55] = 15;
    genop_str[56] = 135;
    genop_str[57] = 63;
    genop_str[58] = 4;
    genop_str[59] = 0;
    genop_str[60] = 0;
    genop_str[61] = 233;
    genop_str[62] = 203;
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
    genop_str[99] = 72;
    genop_str[100] = 137;
    genop_str[101] = 216;
    genop_str[102] = 72;
    genop_str[103] = 131;
    genop_str[104] = 192;
    genop_str[105] = 7;
    genop_str[106] = 72;
    genop_str[107] = 131;
    genop_str[108] = 224;
    genop_str[109] = 248;
    genop_str[110] = 77;
    genop_str[111] = 139;
    genop_str[112] = 56;
    genop_str[113] = 76;
    genop_str[114] = 137;
    genop_str[115] = 250;
    genop_str[116] = 72;
    genop_str[117] = 1;
    genop_str[118] = 194;
    genop_str[119] = 73;
    genop_str[120] = 59;
    genop_str[121] = 17;
    genop_str[122] = 119;
    genop_str[123] = 109;
    genop_str[124] = 73;
    genop_str[125] = 137;
    genop_str[126] = 16;
    genop_str[127] = 72;
    genop_str[128] = 137;
    genop_str[129] = 208;
    genop_str[130] = 73;
    genop_str[131] = 43;
    genop_str[132] = 64;
    genop_str[133] = 248;
    genop_str[134] = 73;
    genop_str[135] = 59;
    genop_str[136] = 65;
    genop_str[137] = 8;
    genop_str[138] = 118;
    genop_str[139] = 4;
    genop_str[140] = 73;
    genop_str[141] = 137;
    genop_str[142] = 65;
    genop_str[143] = 8;
    genop_str[144] = 73;
    genop_str[145] = 139;
    genop_str[146] = 65;
    genop_str[147] = 16;
    genop_str[148] = 72;
    genop_str[149] = 131;
    genop_str[150] = 192;
    genop_str[151] = 1;
    genop_str[152] = 73;
    genop_str[153] = 137;
    genop_str[154] = 65;
    genop_str[155] = 16;
    genop_str[156] = 76;
    genop_str[157] = 137;
    genop_str[158] = 255;
    genop_str[159] = 76;
    genop_str[160] = 137;
    genop_str[161] = 214;
    genop_str[162] = 76;
    genop_str[163] = 137;
    genop_str[164] = 218;
    genop_str[165] = 72;
    genop_str[166] = 133;
    genop_str[167] = 210;
    genop_str[168] = 116;
    genop_str[169] = 15;
    genop_str[170] = 138;
    genop_str[171] = 6;
    genop_str[172] = 136;
    genop_str[173] = 7;
    genop_str[174] = 72;
    genop_str[175] = 255;
    genop_str[176] = 198;
    genop_str[177] = 72;
    genop_str[178] = 255;
    genop_str[179] = 199;
    genop_str[180] = 72;
    genop_str[181] = 255;
    genop_str[182] = 202;
    genop_str[183] = 235;
    genop_str[184] = 236;
    genop_str[185] = 76;
    genop_str[186] = 137;
    genop_str[187] = 230;
    genop_str[188] = 76;
    genop_str[189] = 137;
    genop_str[190] = 234;
    genop_str[191] = 72;
    genop_str[192] = 133;
    genop_str[193] = 210;
    genop_str[194] = 116;
    genop_str[195] = 15;
    genop_str[196] = 138;
    genop_str[197] = 6;
    genop_str[198] = 136;
    genop_str[199] = 7;
    genop_str[200] = 72;
    genop_str[201] = 255;
    genop_str[202] = 198;
    genop_str[203] = 72;
    genop_str[204] = 255;
    genop_str[205] = 199;
    genop_str[206] = 72;
    genop_str[207] = 255;
    genop_str[208] = 202;
    genop_str[209] = 235;
    genop_str[210] = 236;
    genop_str[211] = 199;
    genop_str[212] = 1;
    genop_str[213] = 3;
    genop_str[214] = 0;
    genop_str[215] = 0;
    genop_str[216] = 0;
    genop_str[217] = 76;
    genop_str[218] = 137;
    genop_str[219] = 121;
    genop_str[220] = 8;
    genop_str[221] = 72;
    genop_str[222] = 137;
    genop_str[223] = 89;
    genop_str[224] = 16;
    genop_str[225] = 76;
    genop_str[226] = 137;
    genop_str[227] = 113;
    genop_str[228] = 24;
    genop_str[229] = 72;
    genop_str[230] = 137;
    genop_str[231] = 200;
    genop_str[232] = 195;
    genop_str[233] = 73;
    genop_str[234] = 139;
    genop_str[235] = 65;
    genop_str[236] = 24;
    genop_str[237] = 72;
    genop_str[238] = 131;
    genop_str[239] = 192;
    genop_str[240] = 1;
    genop_str[241] = 73;
    genop_str[242] = 137;
    genop_str[243] = 65;
    genop_str[244] = 24;
    genop_str[245] = 199;
    genop_str[246] = 1;
    genop_str[247] = 9;
    genop_str[248] = 0;
    genop_str[249] = 0;
    genop_str[250] = 0;
    genop_str[251] = 49;
    genop_str[252] = 192;
    genop_str[253] = 72;
    genop_str[254] = 137;
    genop_str[255] = 65;
    genop_str[256] = 8;
    genop_str[257] = 72;
    genop_str[258] = 137;
    genop_str[259] = 65;
    genop_str[260] = 16;
    genop_str[261] = 72;
    genop_str[262] = 137;
    genop_str[263] = 65;
    genop_str[264] = 24;
    genop_str[265] = 72;
    genop_str[266] = 137;
    genop_str[267] = 200;
    genop_str[268] = 195;
    genop_str[269] = 76;
    genop_str[270] = 139;
    genop_str[271] = 71;
    genop_str[272] = 8;
    genop_str[273] = 72;
    genop_str[274] = 139;
    genop_str[275] = 71;
    genop_str[276] = 16;
    genop_str[277] = 76;
    genop_str[278] = 1;
    genop_str[279] = 192;
    genop_str[280] = 73;
    genop_str[281] = 137;
    genop_str[282] = 193;
    genop_str[283] = 76;
    genop_str[284] = 139;
    genop_str[285] = 86;
    genop_str[286] = 8;
    genop_str[287] = 72;
    genop_str[288] = 139;
    genop_str[289] = 70;
    genop_str[290] = 16;
    genop_str[291] = 76;
    genop_str[292] = 1;
    genop_str[293] = 208;
    genop_str[294] = 73;
    genop_str[295] = 137;
    genop_str[296] = 195;
    genop_str[297] = 77;
    genop_str[298] = 57;
    genop_str[299] = 200;
    genop_str[300] = 15;
    genop_str[301] = 131;
    genop_str[302] = 31;
    genop_str[303] = 1;
    genop_str[304] = 0;
    genop_str[305] = 0;
    genop_str[306] = 77;
    genop_str[307] = 57;
    genop_str[308] = 218;
    genop_str[309] = 15;
    genop_str[310] = 131;
    genop_str[311] = 29;
    genop_str[312] = 1;
    genop_str[313] = 0;
    genop_str[314] = 0;
    genop_str[315] = 65;
    genop_str[316] = 15;
    genop_str[317] = 182;
    genop_str[318] = 0;
    genop_str[319] = 73;
    genop_str[320] = 255;
    genop_str[321] = 192;
    genop_str[322] = 61;
    genop_str[323] = 128;
    genop_str[324] = 0;
    genop_str[325] = 0;
    genop_str[326] = 0;
    genop_str[327] = 114;
    genop_str[328] = 117;
    genop_str[329] = 61;
    genop_str[330] = 224;
    genop_str[331] = 0;
    genop_str[332] = 0;
    genop_str[333] = 0;
    genop_str[334] = 114;
    genop_str[335] = 57;
    genop_str[336] = 61;
    genop_str[337] = 240;
    genop_str[338] = 0;
    genop_str[339] = 0;
    genop_str[340] = 0;
    genop_str[341] = 114;
    genop_str[342] = 70;
    genop_str[343] = 131;
    genop_str[344] = 224;
    genop_str[345] = 7;
    genop_str[346] = 193;
    genop_str[347] = 224;
    genop_str[348] = 6;
    genop_str[349] = 65;
    genop_str[350] = 15;
    genop_str[351] = 182;
    genop_str[352] = 8;
    genop_str[353] = 73;
    genop_str[354] = 255;
    genop_str[355] = 192;
    genop_str[356] = 131;
    genop_str[357] = 225;
    genop_str[358] = 63;
    genop_str[359] = 9;
    genop_str[360] = 200;
    genop_str[361] = 193;
    genop_str[362] = 224;
    genop_str[363] = 6;
    genop_str[364] = 65;
    genop_str[365] = 15;
    genop_str[366] = 182;
    genop_str[367] = 8;
    genop_str[368] = 73;
    genop_str[369] = 255;
    genop_str[370] = 192;
    genop_str[371] = 131;
    genop_str[372] = 225;
    genop_str[373] = 63;
    genop_str[374] = 9;
    genop_str[375] = 200;
    genop_str[376] = 193;
    genop_str[377] = 224;
    genop_str[378] = 6;
    genop_str[379] = 65;
    genop_str[380] = 15;
    genop_str[381] = 182;
    genop_str[382] = 8;
    genop_str[383] = 73;
    genop_str[384] = 255;
    genop_str[385] = 192;
    genop_str[386] = 131;
    genop_str[387] = 225;
    genop_str[388] = 63;
    genop_str[389] = 9;
    genop_str[390] = 200;
    genop_str[391] = 235;
    genop_str[392] = 53;
    genop_str[393] = 131;
    genop_str[394] = 224;
    genop_str[395] = 31;
    genop_str[396] = 193;
    genop_str[397] = 224;
    genop_str[398] = 6;
    genop_str[399] = 65;
    genop_str[400] = 15;
    genop_str[401] = 182;
    genop_str[402] = 8;
    genop_str[403] = 73;
    genop_str[404] = 255;
    genop_str[405] = 192;
    genop_str[406] = 131;
    genop_str[407] = 225;
    genop_str[408] = 63;
    genop_str[409] = 9;
    genop_str[410] = 200;
    genop_str[411] = 235;
    genop_str[412] = 33;
    genop_str[413] = 131;
    genop_str[414] = 224;
    genop_str[415] = 15;
    genop_str[416] = 193;
    genop_str[417] = 224;
    genop_str[418] = 6;
    genop_str[419] = 65;
    genop_str[420] = 15;
    genop_str[421] = 182;
    genop_str[422] = 8;
    genop_str[423] = 73;
    genop_str[424] = 255;
    genop_str[425] = 192;
    genop_str[426] = 131;
    genop_str[427] = 225;
    genop_str[428] = 63;
    genop_str[429] = 9;
    genop_str[430] = 200;
    genop_str[431] = 193;
    genop_str[432] = 224;
    genop_str[433] = 6;
    genop_str[434] = 65;
    genop_str[435] = 15;
    genop_str[436] = 182;
    genop_str[437] = 8;
    genop_str[438] = 73;
    genop_str[439] = 255;
    genop_str[440] = 192;
    genop_str[441] = 131;
    genop_str[442] = 225;
    genop_str[443] = 63;
    genop_str[444] = 9;
    genop_str[445] = 200;
    genop_str[446] = 65;
    genop_str[447] = 137;
    genop_str[448] = 196;
    genop_str[449] = 65;
    genop_str[450] = 15;
    genop_str[451] = 182;
    genop_str[452] = 2;
    genop_str[453] = 73;
    genop_str[454] = 255;
    genop_str[455] = 194;
    genop_str[456] = 61;
    genop_str[457] = 128;
    genop_str[458] = 0;
    genop_str[459] = 0;
    genop_str[460] = 0;
    genop_str[461] = 114;
    genop_str[462] = 117;
    genop_str[463] = 61;
    genop_str[464] = 224;
    genop_str[465] = 0;
    genop_str[466] = 0;
    genop_str[467] = 0;
    genop_str[468] = 114;
    genop_str[469] = 57;
    genop_str[470] = 61;
    genop_str[471] = 240;
    genop_str[472] = 0;
    genop_str[473] = 0;
    genop_str[474] = 0;
    genop_str[475] = 114;
    genop_str[476] = 70;
    genop_str[477] = 131;
    genop_str[478] = 224;
    genop_str[479] = 7;
    genop_str[480] = 193;
    genop_str[481] = 224;
    genop_str[482] = 6;
    genop_str[483] = 65;
    genop_str[484] = 15;
    genop_str[485] = 182;
    genop_str[486] = 10;
    genop_str[487] = 73;
    genop_str[488] = 255;
    genop_str[489] = 194;
    genop_str[490] = 131;
    genop_str[491] = 225;
    genop_str[492] = 63;
    genop_str[493] = 9;
    genop_str[494] = 200;
    genop_str[495] = 193;
    genop_str[496] = 224;
    genop_str[497] = 6;
    genop_str[498] = 65;
    genop_str[499] = 15;
    genop_str[500] = 182;
    genop_str[501] = 10;
    genop_str[502] = 73;
    genop_str[503] = 255;
    genop_str[504] = 194;
    genop_str[505] = 131;
    genop_str[506] = 225;
    genop_str[507] = 63;
    genop_str[508] = 9;
    genop_str[509] = 200;
    genop_str[510] = 193;
    genop_str[511] = 224;
    genop_str[512] = 6;
    genop_str[513] = 65;
    genop_str[514] = 15;
    genop_str[515] = 182;
    genop_str[516] = 10;
    genop_str[517] = 73;
    genop_str[518] = 255;
    genop_str[519] = 194;
    genop_str[520] = 131;
    genop_str[521] = 225;
    genop_str[522] = 63;
    genop_str[523] = 9;
    genop_str[524] = 200;
    genop_str[525] = 235;
    genop_str[526] = 53;
    genop_str[527] = 131;
    genop_str[528] = 224;
    genop_str[529] = 31;
    genop_str[530] = 193;
    genop_str[531] = 224;
    genop_str[532] = 6;
    genop_str[533] = 65;
    genop_str[534] = 15;
    genop_str[535] = 182;
    genop_str[536] = 10;
    genop_str[537] = 73;
    genop_str[538] = 255;
    genop_str[539] = 194;
    genop_str[540] = 131;
    genop_str[541] = 225;
    genop_str[542] = 63;
    genop_str[543] = 9;
    genop_str[544] = 200;
    genop_str[545] = 235;
    genop_str[546] = 33;
    genop_str[547] = 131;
    genop_str[548] = 224;
    genop_str[549] = 15;
    genop_str[550] = 193;
    genop_str[551] = 224;
    genop_str[552] = 6;
    genop_str[553] = 65;
    genop_str[554] = 15;
    genop_str[555] = 182;
    genop_str[556] = 10;
    genop_str[557] = 73;
    genop_str[558] = 255;
    genop_str[559] = 194;
    genop_str[560] = 131;
    genop_str[561] = 225;
    genop_str[562] = 63;
    genop_str[563] = 9;
    genop_str[564] = 200;
    genop_str[565] = 193;
    genop_str[566] = 224;
    genop_str[567] = 6;
    genop_str[568] = 65;
    genop_str[569] = 15;
    genop_str[570] = 182;
    genop_str[571] = 10;
    genop_str[572] = 73;
    genop_str[573] = 255;
    genop_str[574] = 194;
    genop_str[575] = 131;
    genop_str[576] = 225;
    genop_str[577] = 63;
    genop_str[578] = 9;
    genop_str[579] = 200;
    genop_str[580] = 65;
    genop_str[581] = 137;
    genop_str[582] = 197;
    genop_str[583] = 69;
    genop_str[584] = 57;
    genop_str[585] = 236;
    genop_str[586] = 117;
    genop_str[587] = 14;
    genop_str[588] = 233;
    genop_str[589] = 216;
    genop_str[590] = 254;
    genop_str[591] = 255;
    genop_str[592] = 255;
    genop_str[593] = 77;
    genop_str[594] = 57;
    genop_str[595] = 218;
    genop_str[596] = 114;
    genop_str[597] = 8;
    genop_str[598] = 235;
    genop_str[599] = 28;
    genop_str[600] = 235;
    genop_str[601] = 15;
    genop_str[602] = 124;
    genop_str[603] = 2;
    genop_str[604] = 235;
    genop_str[605] = 11;
    genop_str[606] = 65;
    genop_str[607] = 190;
    genop_str[608] = 255;
    genop_str[609] = 255;
    genop_str[610] = 255;
    genop_str[611] = 255;
    genop_str[612] = 233;
    genop_str[613] = 194;
    genop_str[614] = 1;
    genop_str[615] = 0;
    genop_str[616] = 0;
    genop_str[617] = 65;
    genop_str[618] = 190;
    genop_str[619] = 1;
    genop_str[620] = 0;
    genop_str[621] = 0;
    genop_str[622] = 0;
    genop_str[623] = 233;
    genop_str[624] = 183;
    genop_str[625] = 1;
    genop_str[626] = 0;
    genop_str[627] = 0;
    genop_str[628] = 69;
    genop_str[629] = 49;
    genop_str[630] = 246;
    genop_str[631] = 233;
    genop_str[632] = 175;
    genop_str[633] = 1;
    genop_str[634] = 0;
    genop_str[635] = 0;
    genop_str[636] = 131;
    genop_str[637] = 250;
    genop_str[638] = 31;
    genop_str[639] = 116;
    genop_str[640] = 32;
    genop_str[641] = 131;
    genop_str[642] = 250;
    genop_str[643] = 32;
    genop_str[644] = 15;
    genop_str[645] = 132;
    genop_str[646] = 177;
    genop_str[647] = 0;
    genop_str[648] = 0;
    genop_str[649] = 0;
    genop_str[650] = 131;
    genop_str[651] = 250;
    genop_str[652] = 6;
    genop_str[653] = 15;
    genop_str[654] = 130;
    genop_str[655] = 233;
    genop_str[656] = 1;
    genop_str[657] = 0;
    genop_str[658] = 0;
    genop_str[659] = 131;
    genop_str[660] = 250;
    genop_str[661] = 11;
    genop_str[662] = 15;
    genop_str[663] = 135;
    genop_str[664] = 224;
    genop_str[665] = 1;
    genop_str[666] = 0;
    genop_str[667] = 0;
    genop_str[668] = 233;
    genop_str[669] = 22;
    genop_str[670] = 1;
    genop_str[671] = 0;
    genop_str[672] = 0;
    genop_str[673] = 68;
    genop_str[674] = 139;
    genop_str[675] = 47;
    genop_str[676] = 68;
    genop_str[677] = 59;
    genop_str[678] = 46;
    genop_str[679] = 15;
    genop_str[680] = 133;
    genop_str[681] = 207;
    genop_str[682] = 1;
    genop_str[683] = 0;
    genop_str[684] = 0;
    genop_str[685] = 68;
    genop_str[686] = 59;
    genop_str[687] = 41;
    genop_str[688] = 15;
    genop_str[689] = 133;
    genop_str[690] = 198;
    genop_str[691] = 1;
    genop_str[692] = 0;
    genop_str[693] = 0;
    genop_str[694] = 76;
    genop_str[695] = 139;
    genop_str[696] = 87;
    genop_str[697] = 8;
    genop_str[698] = 76;
    genop_str[699] = 139;
    genop_str[700] = 95;
    genop_str[701] = 16;
    genop_str[702] = 76;
    genop_str[703] = 139;
    genop_str[704] = 102;
    genop_str[705] = 8;
    genop_str[706] = 76;
    genop_str[707] = 139;
    genop_str[708] = 118;
    genop_str[709] = 16;
    genop_str[710] = 76;
    genop_str[711] = 139;
    genop_str[712] = 121;
    genop_str[713] = 8;
    genop_str[714] = 72;
    genop_str[715] = 139;
    genop_str[716] = 89;
    genop_str[717] = 16;
    genop_str[718] = 76;
    genop_str[719] = 137;
    genop_str[720] = 216;
    genop_str[721] = 76;
    genop_str[722] = 1;
    genop_str[723] = 240;
    genop_str[724] = 72;
    genop_str[725] = 57;
    genop_str[726] = 216;
    genop_str[727] = 119;
    genop_str[728] = 85;
    genop_str[729] = 76;
    genop_str[730] = 137;
    genop_str[731] = 255;
    genop_str[732] = 76;
    genop_str[733] = 137;
    genop_str[734] = 214;
    genop_str[735] = 76;
    genop_str[736] = 137;
    genop_str[737] = 218;
    genop_str[738] = 65;
    genop_str[739] = 131;
    genop_str[740] = 253;
    genop_str[741] = 4;
    genop_str[742] = 116;
    genop_str[743] = 4;
    genop_str[744] = 72;
    genop_str[745] = 107;
    genop_str[746] = 210;
    genop_str[747] = 8;
    genop_str[748] = 72;
    genop_str[749] = 133;
    genop_str[750] = 210;
    genop_str[751] = 116;
    genop_str[752] = 15;
    genop_str[753] = 138;
    genop_str[754] = 6;
    genop_str[755] = 136;
    genop_str[756] = 7;
    genop_str[757] = 72;
    genop_str[758] = 255;
    genop_str[759] = 198;
    genop_str[760] = 72;
    genop_str[761] = 255;
    genop_str[762] = 199;
    genop_str[763] = 72;
    genop_str[764] = 255;
    genop_str[765] = 202;
    genop_str[766] = 235;
    genop_str[767] = 236;
    genop_str[768] = 76;
    genop_str[769] = 137;
    genop_str[770] = 230;
    genop_str[771] = 76;
    genop_str[772] = 137;
    genop_str[773] = 242;
    genop_str[774] = 65;
    genop_str[775] = 131;
    genop_str[776] = 253;
    genop_str[777] = 4;
    genop_str[778] = 116;
    genop_str[779] = 4;
    genop_str[780] = 72;
    genop_str[781] = 107;
    genop_str[782] = 210;
    genop_str[783] = 8;
    genop_str[784] = 72;
    genop_str[785] = 133;
    genop_str[786] = 210;
    genop_str[787] = 116;
    genop_str[788] = 15;
    genop_str[789] = 138;
    genop_str[790] = 6;
    genop_str[791] = 136;
    genop_str[792] = 7;
    genop_str[793] = 72;
    genop_str[794] = 255;
    genop_str[795] = 198;
    genop_str[796] = 72;
    genop_str[797] = 255;
    genop_str[798] = 199;
    genop_str[799] = 72;
    genop_str[800] = 255;
    genop_str[801] = 202;
    genop_str[802] = 235;
    genop_str[803] = 236;
    genop_str[804] = 76;
    genop_str[805] = 137;
    genop_str[806] = 248;
    genop_str[807] = 76;
    genop_str[808] = 137;
    genop_str[809] = 218;
    genop_str[810] = 76;
    genop_str[811] = 1;
    genop_str[812] = 242;
    genop_str[813] = 195;
    genop_str[814] = 199;
    genop_str[815] = 1;
    genop_str[816] = 9;
    genop_str[817] = 0;
    genop_str[818] = 0;
    genop_str[819] = 0;
    genop_str[820] = 76;
    genop_str[821] = 137;
    genop_str[822] = 248;
    genop_str[823] = 72;
    genop_str[824] = 137;
    genop_str[825] = 218;
    genop_str[826] = 195;
    genop_str[827] = 68;
    genop_str[828] = 139;
    genop_str[829] = 47;
    genop_str[830] = 68;
    genop_str[831] = 59;
    genop_str[832] = 41;
    genop_str[833] = 15;
    genop_str[834] = 133;
    genop_str[835] = 53;
    genop_str[836] = 1;
    genop_str[837] = 0;
    genop_str[838] = 0;
    genop_str[839] = 76;
    genop_str[840] = 139;
    genop_str[841] = 87;
    genop_str[842] = 8;
    genop_str[843] = 76;
    genop_str[844] = 139;
    genop_str[845] = 95;
    genop_str[846] = 16;
    genop_str[847] = 76;
    genop_str[848] = 139;
    genop_str[849] = 102;
    genop_str[850] = 8;
    genop_str[851] = 76;
    genop_str[852] = 139;
    genop_str[853] = 121;
    genop_str[854] = 8;
    genop_str[855] = 72;
    genop_str[856] = 139;
    genop_str[857] = 89;
    genop_str[858] = 16;
    genop_str[859] = 76;
    genop_str[860] = 137;
    genop_str[861] = 216;
    genop_str[862] = 72;
    genop_str[863] = 255;
    genop_str[864] = 192;
    genop_str[865] = 72;
    genop_str[866] = 57;
    genop_str[867] = 216;
    genop_str[868] = 119;
    genop_str[869] = 68;
    genop_str[870] = 76;
    genop_str[871] = 137;
    genop_str[872] = 255;
    genop_str[873] = 76;
    genop_str[874] = 137;
    genop_str[875] = 214;
    genop_str[876] = 76;
    genop_str[877] = 137;
    genop_str[878] = 218;
    genop_str[879] = 65;
    genop_str[880] = 131;
    genop_str[881] = 253;
    genop_str[882] = 4;
    genop_str[883] = 116;
    genop_str[884] = 4;
    genop_str[885] = 72;
    genop_str[886] = 107;
    genop_str[887] = 210;
    genop_str[888] = 8;
    genop_str[889] = 72;
    genop_str[890] = 133;
    genop_str[891] = 210;
    genop_str[892] = 116;
    genop_str[893] = 15;
    genop_str[894] = 138;
    genop_str[895] = 6;
    genop_str[896] = 136;
    genop_str[897] = 7;
    genop_str[898] = 72;
    genop_str[899] = 255;
    genop_str[900] = 198;
    genop_str[901] = 72;
    genop_str[902] = 255;
    genop_str[903] = 199;
    genop_str[904] = 72;
    genop_str[905] = 255;
    genop_str[906] = 202;
    genop_str[907] = 235;
    genop_str[908] = 236;
    genop_str[909] = 65;
    genop_str[910] = 131;
    genop_str[911] = 253;
    genop_str[912] = 4;
    genop_str[913] = 117;
    genop_str[914] = 7;
    genop_str[915] = 68;
    genop_str[916] = 136;
    genop_str[917] = 224;
    genop_str[918] = 136;
    genop_str[919] = 7;
    genop_str[920] = 235;
    genop_str[921] = 6;
    genop_str[922] = 76;
    genop_str[923] = 137;
    genop_str[924] = 224;
    genop_str[925] = 72;
    genop_str[926] = 137;
    genop_str[927] = 7;
    genop_str[928] = 76;
    genop_str[929] = 137;
    genop_str[930] = 248;
    genop_str[931] = 76;
    genop_str[932] = 137;
    genop_str[933] = 218;
    genop_str[934] = 72;
    genop_str[935] = 255;
    genop_str[936] = 194;
    genop_str[937] = 195;
    genop_str[938] = 199;
    genop_str[939] = 1;
    genop_str[940] = 9;
    genop_str[941] = 0;
    genop_str[942] = 0;
    genop_str[943] = 0;
    genop_str[944] = 76;
    genop_str[945] = 137;
    genop_str[946] = 248;
    genop_str[947] = 72;
    genop_str[948] = 137;
    genop_str[949] = 218;
    genop_str[950] = 195;
    genop_str[951] = 76;
    genop_str[952] = 139;
    genop_str[953] = 71;
    genop_str[954] = 8;
    genop_str[955] = 76;
    genop_str[956] = 139;
    genop_str[957] = 86;
    genop_str[958] = 8;
    genop_str[959] = 76;
    genop_str[960] = 139;
    genop_str[961] = 95;
    genop_str[962] = 16;
    genop_str[963] = 76;
    genop_str[964] = 139;
    genop_str[965] = 102;
    genop_str[966] = 16;
    genop_str[967] = 77;
    genop_str[968] = 137;
    genop_str[969] = 221;
    genop_str[970] = 77;
    genop_str[971] = 57;
    genop_str[972] = 229;
    genop_str[973] = 77;
    genop_str[974] = 15;
    genop_str[975] = 71;
    genop_str[976] = 236;
    genop_str[977] = 49;
    genop_str[978] = 219;
    genop_str[979] = 139;
    genop_str[980] = 7;
    genop_str[981] = 76;
    genop_str[982] = 57;
    genop_str[983] = 235;
    genop_str[984] = 115;
    genop_str[985] = 43;
    genop_str[986] = 131;
    genop_str[987] = 248;
    genop_str[988] = 4;
    genop_str[989] = 116;
    genop_str[990] = 18;
    genop_str[991] = 77;
    genop_str[992] = 139;
    genop_str[993] = 52;
    genop_str[994] = 216;
    genop_str[995] = 77;
    genop_str[996] = 139;
    genop_str[997] = 60;
    genop_str[998] = 218;
    genop_str[999] = 77;
    genop_str[1000] = 57;
    genop_str[1001] = 254;
    genop_str[1002] = 117;
    genop_str[1003] = 34;
    genop_str[1004] = 72;
    genop_str[1005] = 255;
    genop_str[1006] = 195;
    genop_str[1007] = 235;
    genop_str[1008] = 228;
    genop_str[1009] = 69;
    genop_str[1010] = 15;
    genop_str[1011] = 182;
    genop_str[1012] = 52;
    genop_str[1013] = 24;
    genop_str[1014] = 69;
    genop_str[1015] = 15;
    genop_str[1016] = 182;
    genop_str[1017] = 60;
    genop_str[1018] = 26;
    genop_str[1019] = 69;
    genop_str[1020] = 57;
    genop_str[1021] = 254;
    genop_str[1022] = 117;
    genop_str[1023] = 18;
    genop_str[1024] = 72;
    genop_str[1025] = 255;
    genop_str[1026] = 195;
    genop_str[1027] = 235;
    genop_str[1028] = 208;
    genop_str[1029] = 77;
    genop_str[1030] = 57;
    genop_str[1031] = 227;
    genop_str[1032] = 114;
    genop_str[1033] = 12;
    genop_str[1034] = 119;
    genop_str[1035] = 18;
    genop_str[1036] = 235;
    genop_str[1037] = 24;
    genop_str[1038] = 124;
    genop_str[1039] = 6;
    genop_str[1040] = 235;
    genop_str[1041] = 12;
    genop_str[1042] = 114;
    genop_str[1043] = 2;
    genop_str[1044] = 235;
    genop_str[1045] = 8;
    genop_str[1046] = 65;
    genop_str[1047] = 190;
    genop_str[1048] = 255;
    genop_str[1049] = 255;
    genop_str[1050] = 255;
    genop_str[1051] = 255;
    genop_str[1052] = 235;
    genop_str[1053] = 13;
    genop_str[1054] = 65;
    genop_str[1055] = 190;
    genop_str[1056] = 1;
    genop_str[1057] = 0;
    genop_str[1058] = 0;
    genop_str[1059] = 0;
    genop_str[1060] = 235;
    genop_str[1061] = 5;
    genop_str[1062] = 69;
    genop_str[1063] = 49;
    genop_str[1064] = 246;
    genop_str[1065] = 235;
    genop_str[1066] = 0;
    genop_str[1067] = 131;
    genop_str[1068] = 250;
    genop_str[1069] = 6;
    genop_str[1070] = 116;
    genop_str[1071] = 29;
    genop_str[1072] = 131;
    genop_str[1073] = 250;
    genop_str[1074] = 7;
    genop_str[1075] = 116;
    genop_str[1076] = 33;
    genop_str[1077] = 131;
    genop_str[1078] = 250;
    genop_str[1079] = 8;
    genop_str[1080] = 116;
    genop_str[1081] = 37;
    genop_str[1082] = 131;
    genop_str[1083] = 250;
    genop_str[1084] = 9;
    genop_str[1085] = 116;
    genop_str[1086] = 41;
    genop_str[1087] = 131;
    genop_str[1088] = 250;
    genop_str[1089] = 10;
    genop_str[1090] = 116;
    genop_str[1091] = 45;
    genop_str[1092] = 65;
    genop_str[1093] = 131;
    genop_str[1094] = 254;
    genop_str[1095] = 0;
    genop_str[1096] = 15;
    genop_str[1097] = 157;
    genop_str[1098] = 192;
    genop_str[1099] = 235;
    genop_str[1100] = 43;
    genop_str[1101] = 65;
    genop_str[1102] = 131;
    genop_str[1103] = 254;
    genop_str[1104] = 0;
    genop_str[1105] = 15;
    genop_str[1106] = 148;
    genop_str[1107] = 192;
    genop_str[1108] = 235;
    genop_str[1109] = 34;
    genop_str[1110] = 65;
    genop_str[1111] = 131;
    genop_str[1112] = 254;
    genop_str[1113] = 0;
    genop_str[1114] = 15;
    genop_str[1115] = 149;
    genop_str[1116] = 192;
    genop_str[1117] = 235;
    genop_str[1118] = 25;
    genop_str[1119] = 65;
    genop_str[1120] = 131;
    genop_str[1121] = 254;
    genop_str[1122] = 0;
    genop_str[1123] = 15;
    genop_str[1124] = 156;
    genop_str[1125] = 192;
    genop_str[1126] = 235;
    genop_str[1127] = 16;
    genop_str[1128] = 65;
    genop_str[1129] = 131;
    genop_str[1130] = 254;
    genop_str[1131] = 0;
    genop_str[1132] = 15;
    genop_str[1133] = 158;
    genop_str[1134] = 192;
    genop_str[1135] = 235;
    genop_str[1136] = 7;
    genop_str[1137] = 65;
    genop_str[1138] = 131;
    genop_str[1139] = 254;
    genop_str[1140] = 0;
    genop_str[1141] = 15;
    genop_str[1142] = 159;
    genop_str[1143] = 192;
    genop_str[1144] = 15;
    genop_str[1145] = 182;
    genop_str[1146] = 192;
    genop_str[1147] = 195;
    genop_str[1148] = 184;
    genop_str[1149] = 60;
    genop_str[1150] = 0;
    genop_str[1151] = 0;
    genop_str[1152] = 0;
    genop_str[1153] = 191;
    genop_str[1154] = 70;
    genop_str[1155] = 0;
    genop_str[1156] = 0;
    genop_str[1157] = 0;
    genop_str[1158] = 15;
    genop_str[1159] = 5;
    let path: Array[U8, 256] = Array.zeroed();
    let opath: Array[U8, 256] = Array.zeroed();
    let post: Array[Int, 287000] = Array.zeroed();
    let ps: Slice[Int] = slice(post, 0, 287000);
    // B0.3b-2/B0.3c: post[140000..141023] = fd (function table),
    // post[141024..217023] = sast (statement AST), post[217024..219135] = ctxi.
    // The views keep the old names; offsets below are relative to ctxi.
    //   0 st(16)  16 cs(16)  32 ck(64)  96 cje(64)  160 cstart(64)
    //   224 bloop(64)  288 bpos(64)  352 rname(64)  416 fname(128)
    //   544 flabel(128)  672 fparams(16)  688 fpelem(16)  704 fret(128)
    //   832 fret_t1(128)  960 fret_t2(128)  1088 fret_ty(128)
    //   1216 NF, 1217 DLEN, 1218 CD, 1219 NBRK, 1220 HAVE_RET (unused)
    //   1221 cjmp(64)
    let ctxi: Slice[Int] = slice_at(ps, 217024, 2112);
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
    let n = read_file(inp, membuf, 393216);
    if n <= 0 { write("slice: read failed\n"); return 3; }
    if n >= 393216 { write("stage1: source too large\n"); return 3; }
    let olen = arg_len(2);
    i = 0;
    while i < olen { opath[i] = arg_byte(2, i); i = i + 1; }
    let oup: Slice[U8] = slice(opath, 0, olen);

    // membuf layout: source [0,393216), code [393216,1179648), data [1179648,1245184).
    let mem: Slice[U8] = slice(membuf, 0, 1245184);
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let pf = preflight(srcs, n, ps);
    if pf != 0 { return pf; }
    let sf = scan_funcs(srcs, n, fd);
    if sf != 0 { return sf; }
    let cd = check_decls(srcs, fd, ps);
    if cd != 0 { return cd; }
    let cc = check_calls(srcs, fd);
    if cc != 0 { return cc; }
    let ss = scan_stmts(mem, ps, n);
    if ss != 0 { return ss; }
    let ds: Slice[U8] = slice_at(mem, 1179648, 65536);
    st[0] = 0; st[1] = n; st[3] = 0; st[4] = 0;

    let c: Slice[U8] = slice_at(mem, 393216, 786432);
    // cs[3] = data-relocation patch base (post[220000..287000));
    // cs[6] = function-call patch base (post[40000..50000)).
    cs[0] = 0; cs[2] = 0; cs[3] = 220000; cs[5] = 0; cs[6] = 40000;

    // Runtime block: argc, argv, path buffer.
    let runtime_off = dlen;
    dlen = dlen + 16 + 256;
    cs[7] = runtime_off;
    let heap_ptr_off = dlen;
    dlen = dlen + 56;
    post[17010] = heap_ptr_off;
    post[17011] = heap_ptr_off + 8;
    post[17012] = heap_ptr_off + 16;
    // R4.2: arena accounting ({base,current,end,high_water,allocs,rejects,reclaims}).
    post[17018] = heap_ptr_off + 24;
    post[17019] = heap_ptr_off + 32;
    post[17020] = heap_ptr_off + 40;
    post[17021] = heap_ptr_off + 48;
    // B3-4c: region frame state in data memory (zero-initialised BSS).
    //   depth: active region count; next: last owner seq;
    //   mark[64]: arena top at region entry; seq[64]: owner id of the frame.
    // Only programs that mention `region`/`Buffer` pay for it, so the byte
    // output of everything else stays identical.
    post[17013] = heap_ptr_off;
    post[17014] = heap_ptr_off;
    post[17015] = heap_ptr_off;
    post[17016] = heap_ptr_off;
    if post[17017] == 1 {
        post[17013] = dlen;
        dlen = dlen + 8;
        post[17014] = dlen;
        dlen = dlen + 8;
        post[17015] = dlen;
        dlen = dlen + 512;
        post[17016] = dlen;
        dlen = dlen + 512;
    }

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
    while genop_i < 1160 {
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
    // B3-2: emit the arena allocation helper only when buffer_new was used.
    if post[217024 + 1399] > 0 {
        let ba_label = cs[0];
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 248); // mov rax,rdi
        emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 192); emit1(c, cs, 7); // add rax,7
        emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 224); emit1(c, cs, 248); // and rax,-8
        emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 13);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0);
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 202); // mov rdx,rcx
        emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 194); // add rdx,rax
        emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 53);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17012]; cs[2] = cs[2] + 1; emit4(c, cs, 0);
        emit1(c, cs, 72); emit1(c, cs, 57); emit1(c, cs, 242); // cmp rdx,rsi
        emit1(c, cs, 15); emit1(c, cs, 135);
        let bafail = cs[0]; emit4(c, cs, 0);
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0);
        // R4.2: high_water = max(high_water, current-base); allocs += 1.
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 208); // mov rax,rdx
        emit1(c, cs, 72); emit1(c, cs, 43); emit1(c, cs, 5);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17010]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // sub rax,[base]
        emit1(c, cs, 72); emit1(c, cs, 59); emit1(c, cs, 5);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17018]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // cmp rax,[high]
        emit1(c, cs, 15); emit1(c, cs, 134);
        let bhw = cs[0]; emit4(c, cs, 0); // jbe
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17018]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // [high]=rax
        patch_jump(c, bhw, cs[0]);
        emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17019]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[allocs]
        emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 192); emit1(c, cs, 1); // add rax,1
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17019]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // [allocs]=rax
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 200); // mov rax,rcx
        emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 13);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17010]; cs[2] = cs[2] + 1; emit4(c, cs, 0);
        emit1(c, cs, 72); emit1(c, cs, 41); emit1(c, cs, 200); // sub rax,rcx
        emit1(c, cs, 195); // ret
        patch_jump(c, bafail, cs[0]);
        emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17020]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[rejects]
        emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 192); emit1(c, cs, 1); // add rax,1
        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = post[17020]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // [rejects]=rax
        emit1(c, cs, 72); emit1(c, cs, 184);
        let bz = 0; while bz < 8 { emit1(c, cs, 255); bz = bz + 1; }
        emit1(c, cs, 195); // ret
        let bk = 0;
        while bk < post[217024 + 1399] {
            let bp = post[217024 + 1400 + bk];
            put32(c, bp, ba_label - (bp + 4));
            bk = bk + 1;
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
    if filetotal > 610000 { write("stage1: output too large
"); return 4; }
    let o: Slice[U8] = slice(out, 0, 610000);
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
