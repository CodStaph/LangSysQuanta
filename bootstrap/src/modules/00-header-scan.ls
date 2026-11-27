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

// B5-10: effect / capability names -> bit.  The same vocabulary serves
// `eff(...)` clauses and `Cap[...]` tokens (a cap is the token for an effect).
//   1 read  2 write  4 alloc  8 io  16 panic  32 spawn  64 unsafe  128 pure
// Unknown names return -1.
fn eff_bit(src: Slice[U8], start: Int, len: Int) -> Int {
    let c0 = src[start] | 32;
    if len == 4 && c0 == 114 && src[start + 1] == 101 && src[start + 2] == 97 && src[start + 3] == 100 { return 1; }
    if len == 5 && c0 == 119 && src[start + 1] == 114 && src[start + 2] == 105 && src[start + 3] == 116 && src[start + 4] == 101 { return 2; }
    if len == 5 && c0 == 97 && src[start + 1] == 108 && src[start + 2] == 108 && src[start + 3] == 111 && src[start + 4] == 99 { return 4; }
    if len == 2 && c0 == 105 && src[start + 1] == 111 { return 8; }
    if len == 5 && c0 == 112 && src[start + 1] == 97 && src[start + 2] == 110 && src[start + 3] == 105 && src[start + 4] == 99 { return 16; }
    if len == 5 && c0 == 115 && src[start + 1] == 112 && src[start + 2] == 97 && src[start + 3] == 119 && src[start + 4] == 110 { return 32; }
    if len == 6 && c0 == 117 && src[start + 1] == 110 && src[start + 2] == 115 && src[start + 3] == 97 && src[start + 4] == 102 && src[start + 5] == 101 { return 64; }
    if len == 3 && c0 == 102 && src[start + 1] == 102 && src[start + 2] == 105 { return 64; }
    if len == 2 && c0 == 104 && src[start + 1] == 119 { return 64; }
    if len == 3 && c0 == 100 && src[start + 1] == 109 && src[start + 2] == 97 { return 64; }
    if len == 3 && c0 == 105 && src[start + 1] == 114 && src[start + 2] == 113 { return 64; }
    if len == 6 && c0 == 97 && src[start + 1] == 116 && src[start + 2] == 111 && src[start + 3] == 109 && src[start + 4] == 105 && src[start + 5] == 99 { return 2; }
    if len == 4 && c0 == 112 && src[start + 1] == 117 && src[start + 2] == 114 && src[start + 3] == 101 { return 128; }
    return 0 - 1;
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
            // B3-4c: region frames / Buffer owner ids need the runtime region state.
            if len == 6 && ((src[start] == 114 && src[start + 1] == 101 && src[start + 2] == 103 && src[start + 3] == 105 && src[start + 4] == 111 && src[start + 5] == 110) || (src[start] == 66 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114)) {
                post[17017] = 1;
            }
            if len >= 7 && src[start] == 98 && src[start + 1] == 117 && src[start + 2] == 102 && src[start + 3] == 102 && src[start + 4] == 101 && src[start + 5] == 114 && src[start + 6] == 95 {
                post[17017] = 1;
            }
            // R4.7: arena_* builtins may allocate handles / compact the arena,
            // so they need the region state and the handle table too.
            if len >= 6 && src[start] == 97 && src[start + 1] == 114 && src[start + 2] == 101 && src[start + 3] == 110 && src[start + 4] == 97 && src[start + 5] == 95 {
                post[17017] = 1;
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
fn scan_funcs(src: Slice[U8], n: Int, post: Slice[Int]) -> Int {
    // B7: fd travels as a slice of the post register (same derivation as
    // scan_stmts) so the call stays inside the 6-argument-slot ABI budget.
    let fd: Slice[Int] = slice_at(post, 140000, 1024);
    let i = 0;
    let count = 0;
    // B7 impl-walk state: in_end covers the impl block; its first fn is the
    // method linked to the current impl row (in_row) of trait in_tc.
    let in_end = -1;
    let in_row = -1;
    let in_tc = -1;
    let st2: Array[Int, 16] = Array.zeroed();
    let ss2: Slice[Int] = slice(st2, 0, 16);
    while i < n {
        if in_end >= 0 && i >= in_end { in_end = -1; in_row = -1; in_tc = -1; }
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
            // B7: pre-register struct names so impl headers and the emit walk
            // can resolve them before the struct item is reached.
            if len == 6 && src[start] == 115 && src[start + 1] == 116 && src[start + 2] == 114 && src[start + 3] == 117 && src[start + 4] == 99 && src[start + 5] == 116 {
                let q = i;
                while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                if q < n && is_ident_byte(src[q]) == 1 {
                    ss2[0] = q; ss2[1] = n;
                    let snid = name_id(src, ss2, post);
                    // name ids are indices: 0 is a legal id - trust ss2[5].
                    if ss2[5] != 0 && st_find(post, snid) < 0 { st_add(post, snid); }
                }
            }
            // B7: `trait Name[A] { fn sign; }` - declaration only; the block is
            // registered (name/len) and skipped; fn_signs are not functions.
            if len == 5 && src[start] == 116 && src[start + 1] == 114 && src[start + 2] == 97 && src[start + 3] == 105 && src[start + 4] == 116 {
                let q = i;
                while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                if q < n && is_ident_byte(src[q]) == 1 {
                    let tn0 = q;
                    while q < n && is_ident_byte(src[q]) == 1 { q = q + 1; }
                    let tnl = q - tn0;
                    // predeclared op-trait names and a full table are both rejections.
                    let bad = 0;
                    if (tnl == 2 && src[tn0] == 69 && src[tn0 + 1] == 113) || (tnl == 3 && src[tn0] == 79 && src[tn0 + 1] == 114 && src[tn0 + 2] == 100) || (tnl == 3 && src[tn0] == 78 && src[tn0 + 1] == 117 && src[tn0 + 2] == 109) || (tnl == 3 && src[tn0] == 65 && src[tn0 + 1] == 100 && src[tn0 + 2] == 100) || (tnl == 4 && src[tn0] == 67 && src[tn0 + 1] == 111 && src[tn0 + 2] == 112 && src[tn0 + 3] == 121) { bad = 1; }
                    if post[135690] >= 16 { bad = 1; }
                    if bad == 1 { write("stage1: E-LS-DUP: trait name is predefined or the trait table is full\n"); return 4; }
                    // rows are {source offset, length} so impl heads and bounds
                    // can byte-compare without another table copy.
                    post[135694 + post[135690] * 2] = tn0;
                    post[135695 + post[135690] * 2] = tnl;
                    post[135690] = post[135690] + 1;
                    while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    if q < n && src[q] == 91 { while q < n && src[q] != 93 { q = q + 1; } if q < n { q = q + 1; } }
                    while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    if q >= n || src[q] != 123 { write("stage1: E-LS-UNSUPPORTED: trait block is malformed\n"); return 4; }
                    let tbend = scan_block_end(src, q, n);
                    if tbend < 0 { write("stage1: E-LS-UNSUPPORTED: trait block is malformed\n"); return 4; }
                    i = tbend;
                    continue;
                }
            }
            // B7: `impl Trait for Ty { fn method(..) {..} }` - register an impl
            // row; the method inside is an ordinary fn in the flat namespace.
            if len == 4 && src[start] == 105 && src[start + 1] == 109 && src[start + 2] == 112 && src[start + 3] == 108 {
                let q = i;
                while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                if q < n && is_ident_byte(src[q]) == 1 {
                    let trn0 = q;
                    while q < n && is_ident_byte(src[q]) == 1 { q = q + 1; }
                    let trl = q - trn0;
                    let tc = 0;
                    if trl == 2 && src[trn0] == 69 && src[trn0 + 1] == 113 { tc = 2; }
                    if trl == 3 && src[trn0] == 79 && src[trn0 + 1] == 114 && src[trn0 + 2] == 100 { tc = 1; }
                    if trl == 4 && src[trn0] == 67 && src[trn0 + 1] == 111 && src[trn0 + 2] == 112 && src[trn0 + 3] == 121 { tc = 5; }
                    // R2.6-C: `impl Add for <struct>` — the `+` operator may be
                    // provided by a user impl (method must return Int).
                    if trl == 3 && src[trn0] == 65 && src[trn0 + 1] == 100 && src[trn0 + 2] == 100 { tc = 4; }
                    if tc == 0 {
                        let ts = 0;
                        while ts < post[135690] {
                            if post[135695 + ts * 2] == trl {
                                let tw = 0;
                                let tsame = 1;
                                while tw < trl { if src[post[135694 + ts * 2] + tw] != src[trn0 + tw] { tsame = 0; break; } tw = tw + 1; }
                                if tsame == 1 { tc = 16 + ts; }
                            }
                            ts = ts + 1;
                        }
                    }
                    while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    if q + 3 > n || src[q] != 102 || src[q + 1] != 111 || src[q + 2] != 114 || (q + 3 < n && is_ident_byte(src[q + 3]) == 1) { tc = 0; }
                    q = q + 3;
                    while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    let tyn0 = q;
                    if q >= n || is_ident_byte(src[q]) != 1 { tc = 0; } else {
                        while q < n && is_ident_byte(src[q]) == 1 { q = q + 1; }
                    }
                    let tyl = q - tyn0;
                    let ty = 0;
                    if tyl == 3 && src[tyn0] == 73 && src[tyn0 + 1] == 110 && src[tyn0 + 2] == 116 { ty = 1; }
                    if tyl == 2 && src[tyn0] == 85 && src[tyn0 + 1] == 56 { ty = 2; }
                    if ty == 0 {
                        ss2[0] = tyn0; ss2[1] = n;
                        let ysi = st_find(post, name_id(src, ss2, post));
                        if ysi >= 0 { ty = 30 + ysi; }
                    }
                    // op traits keep to user structs; custom traits also take Int/U8.
                    let ok = 0;
                    if (tc == 1 || tc == 2 || tc == 5 || tc == 4) && ty >= 30 { ok = 1; }
                    if tc >= 16 && (ty == 1 || ty == 2 || ty >= 30) { ok = 1; }
                    if ok == 0 { write("stage1: E-LS-UNSUPPORTED: impl target - Eq/Ord/Copy/Add go to user structs, custom traits to Int/U8/structs\n"); return 4; }
                    if post[135748] >= 12 { write("stage1: E-LS-COHERENCE: impl table full (limit 12)\n"); return 4; }
                    let rs = 0;
                    while rs < post[135748] {
                        if post[135752 + rs * 4] == tc && post[135753 + rs * 4] == ty { write("stage1: E-LS-COHERENCE: duplicate impl - each (trait, type) pair may have at most one impl\n"); return 4; }
                        rs = rs + 1;
                    }
                    let rrow = 135752 + post[135748] * 4;
                    post[rrow] = tc;
                    post[rrow + 1] = ty;
                    post[rrow + 2] = 0;
                    post[rrow + 3] = 0 - 1;
                    post[135748] = post[135748] + 1;
                    in_row = post[135748] - 1;
                    in_tc = tc;
                    while q < n && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    if q >= n || src[q] != 123 { write("stage1: E-LS-UNSUPPORTED: impl block is malformed\n"); return 4; }
                    let ibend = scan_block_end(src, q, n);
                    if ibend < 0 { write("stage1: E-LS-UNSUPPORTED: impl block is malformed\n"); return 4; }
                    in_end = ibend;
                    i = q + 1;
                    continue;
                }
            }
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
                    // B7: the first fn of an impl block is its method; link it to
                    // the impl row (name id at +2, fd index at +3) and enforce the
                    // canonical method name for the op traits.
                    if in_row >= 0 {
                        let rbase = 135752 + in_row * 4;
                        ss2[0] = ns; ss2[1] = ns + nl;
                        post[rbase + 2] = name_id(src, ss2, post);
                        post[rbase + 3] = count;
                        if in_tc == 2 && (nl != 2 || src[ns] != 101 || src[ns + 1] != 113) { write("stage1: E-LS-UNSUPPORTED: impl of Eq must define fn eq\n"); return 4; }
                        if in_tc == 1 && (nl != 2 || src[ns] != 108 || src[ns + 1] != 116) { write("stage1: E-LS-UNSUPPORTED: impl of Ord must define fn lt\n"); return 4; }
                        in_row = -1;
                    }
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

// B4: bound names -> capability codes.
//   1 Ord, 2 Eq, 3 Num, 4 Add; B7 adds 5 Copy and 16+ti for user traits.
fn bound_code(src: Slice[U8], start: Int, len: Int, post: Slice[Int]) -> Int {
    if len == 3 && src[start] == 79 && src[start + 1] == 114 && src[start + 2] == 100 { return 1; }
    if len == 2 && src[start] == 69 && src[start + 1] == 113 { return 2; }
    if len == 3 && src[start] == 78 && src[start + 1] == 117 && src[start + 2] == 109 { return 3; }
    if len == 3 && src[start] == 65 && src[start + 1] == 100 && src[start + 2] == 100 { return 4; }
    if len == 4 && src[start] == 67 && src[start + 1] == 111 && src[start + 2] == 112 && src[start + 3] == 121 { return 5; }
    let ti = 0;
    while ti < post[135690] {
        if post[135695 + ti * 2] == len {
            let w = 0;
            let same = 1;
            while w < len { if src[post[135694 + ti * 2] + w] != src[start + w] { same = 0; break; } w = w + 1; }
            if same == 1 { return 16 + ti; }
        }
        ti = ti + 1;
    }
    return 0 - 1;
}

// Parse `[A: Ord, B: Eq]` (or just `[A, B]`) into the current generic table.
// fi >= 0 stores inline bounds in the function table; fi < 0 (enum) rejects
// bounds because enum instances do not carry constraint checks yet.
fn scan_generic_list(src: Slice[U8], st: Slice[Int], post: Slice[Int]) -> Int {
    let n = st[1];
    let fi = post[135899];
    let count = 0;
    post[135900] = 0;
    if st[0] >= n || src[st[0]] != 91 { return 0; }
    skip(src, st, n);
    st[0] = st[0] + 1;
    while 1 {
        skip(src, st, n);
        if st[0] < n && src[st[0]] == 93 { st[0] = st[0] + 1; break; }
        let ns = st[0];
        let gn = name_id(src, st, post);
        let nl = st[0] - ns;
        if st[5] == 0 || nl == 0 { write("generic: bad parameter name\n"); st[3] = 1; return 0 - 1; }
        if count >= 2 {
            write("stage1: E-LS-UNSUPPORTED: more than 2 generic parameters are not implemented in B-LS yet\n");
            st[3] = 1;
            return 0 - 1;
        }
        let j = 0;
        while j < count {
            if post[135901 + j] == gn { write("generic: duplicate parameter\n"); st[3] = 1; return 0 - 1; }
            j = j + 1;
        }
        post[135901 + count] = gn;
        count = count + 1;
        skip(src, st, n);
        if st[0] < n && src[st[0]] == 58 {
            st[0] = st[0] + 1;
            skip(src, st, n);
            let bs = st[0];
            let bn = name_id(src, st, post);
            let bl = st[0] - bs;
            if st[5] == 0 || bl == 0 { write("generic: bad bound\n"); st[3] = 1; return 0 - 1; }
            let bc = bound_code(src, bs, bl, post);
            if bc < 0 {
                write("stage1: E-LS-UNSUPPORTED: unsupported generic bound (use Ord/Eq/Num/Add)\n");
                st[3] = 1;
                return 0 - 1;
            }
            if fi < 0 {
                write("stage1: E-LS-UNSUPPORTED: bounds on generic enum parameters are not implemented in B-LS yet\n");
                st[3] = 1;
                return 0 - 1;
            }
            post[133024 + fi * 8 + count - 1] = bc;
            skip(src, st, n);
        }
        if st[0] < n && src[st[0]] == 44 { st[0] = st[0] + 1; }
        else if st[0] < n && src[st[0]] == 93 { st[0] = st[0] + 1; break; }
        else { write("generic: expected , or ]\n"); st[3] = 1; return 0 - 1; }
    }
    post[135900] = count;
    return count;
}

// B4 signature pass: for generic functions, record parameter type descriptors,
// inline/where bounds, generic arity and the symbolic return parameter. This
// runs before emit_body so calls may precede the callee definition.
fn scan_sigs(src: Slice[U8], fd: Slice[Int], post: Slice[Int]) -> Int {
    let st: Array[Int, 16] = Array.zeroed();
    let ss: Slice[Int] = slice(st, 0, 16);
    let count = fd[0];
    let fi = 0;
    while fi < count {
        let base = 1 + fi * 8;
        let bs = fd[base + 4];
        ss[0] = fd[base] + fd[base + 1];
        ss[1] = bs;
        ss[2] = 0; ss[3] = 0; ss[4] = fi; ss[5] = 0; ss[12] = 65536;
        post[135584 + fi] = 0;
        post[135072 + fi * 4] = 0;
        post[135072 + fi * 4 + 1] = 0;
        post[135072 + fi * 4 + 2] = 0;
        post[135900] = 0;
        post[135899] = fi;
        let gc = scan_generic_list(src, ss, post);
        if ss[3] != 0 { return 4; }
        post[135072 + fi * 4] = gc;
        if gc > 0 {
            ss[0] = fd[base];
            ss[1] = bs;
            ss[3] = 0; ss[5] = 0;
            let nid = name_id(src, ss, post);
            post[135584 + fi] = nid;
            // Parameter type descriptors.
            ss[0] = fd[base + 6];
            ss[1] = fd[base + 7];
            ss[3] = 0;
            let pc = 0;
            while pc < 6 {
                skip(src, ss, ss[1]);
                if ss[0] >= ss[1] || src[ss[0]] == 41 { break; }
                if ss[0] + 3 <= ss[1] && src[ss[0]] == 118 && src[ss[0] + 1] == 97 && src[ss[0] + 2] == 108 && kw_end(src, ss[0] + 3, ss[1]) == 1 { ss[0] = ss[0] + 3; skip(src, ss, ss[1]); }
                if ss[0] + 3 <= ss[1] && src[ss[0]] == 109 && src[ss[0] + 1] == 117 && src[ss[0] + 2] == 116 && kw_end(src, ss[0] + 3, ss[1]) == 1 { ss[0] = ss[0] + 3; skip(src, ss, ss[1]); }
                if ss[0] + 3 <= ss[1] && src[ss[0]] == 114 && src[ss[0] + 1] == 101 && src[ss[0] + 2] == 102 && kw_end(src, ss[0] + 3, ss[1]) == 1 { ss[0] = ss[0] + 3; skip(src, ss, ss[1]); }
                let pid = name_id(src, ss, post);
                if ss[5] == 0 { write("generic: bad parameter\n"); return 4; }
                if expect_char(src, ss, 58, ss[1]) == 0 { write("generic: expected :\n"); return 4; }
                let pt = parse_ty(src, ss, post);
                if pt == 0 || ss[3] != 0 { write("generic: unsupported parameter type\n"); return 4; }
                post[132000 + fi * 8 + pc] = pt;
                pc = pc + 1;
                skip(src, ss, ss[1]);
                if ss[0] < ss[1] && src[ss[0]] == 44 { ss[0] = ss[0] + 1; }
                else { break; }
            }
            // Return type (symbolic, or a simple concrete type).
            ss[0] = fd[base + 7] + 1;
            ss[1] = bs;
            ss[3] = 0;
            skip(src, ss, ss[1]);
            if ss[0] + 1 < ss[1] && src[ss[0]] == 45 && src[ss[0] + 1] == 62 {
                ss[0] = ss[0] + 2;
                skip(src, ss, ss[1]);
                let rt = parse_ty(src, ss, post);
                if rt == 0 || ss[3] != 0 {
                    write("stage1: E-LS-UNSUPPORTED: generic function return type must be a parameter or a scalar/Slice type\n");
                    return 4;
                }
                if rt >= 100 { post[135072 + fi * 4 + 1] = rt; }
                else { post[135072 + fi * 4 + 2] = rt; }
                skip(src, ss, ss[1]);
            }
            // Optional `where A: Ord, B: Eq` clause.
            if ss[0] + 5 <= ss[1] && src[ss[0]] == 119 && src[ss[0] + 1] == 104 && src[ss[0] + 2] == 101 && src[ss[0] + 3] == 114 && src[ss[0] + 4] == 101 && kw_end(src, ss[0] + 5, ss[1]) == 1 {
                ss[0] = ss[0] + 5;
                while 1 {
                    skip(src, ss, ss[1]);
                    if ss[0] >= ss[1] || src[ss[0]] == 123 { break; }
                    let gn = name_id(src, ss, post);
                    if ss[5] == 0 { write("generic: bad where parameter\n"); return 4; }
                    let gi = gen_find(post, gn);
                    if gi < 0 { write("generic: where parameter is not generic\n"); return 4; }
                    if expect_char(src, ss, 58, ss[1]) == 0 { write("generic: expected :\n"); return 4; }
                    skip(src, ss, ss[1]);
                    let bs2 = ss[0];
                    let bn = name_id(src, ss, post);
                    let bl = ss[0] - bs2;
                    let bc = bound_code(src, bs2, bl, post);
                    if bc < 0 {
                        write("stage1: E-LS-UNSUPPORTED: unsupported generic bound (use Ord/Eq/Num/Add)\n");
                        return 4;
                    }
                    post[133024 + fi * 8 + gi] = bc;
                    skip(src, ss, ss[1]);
                    if ss[0] < ss[1] && src[ss[0]] == 44 { ss[0] = ss[0] + 1; }
                    else { break; }
                }
            }
            // Publish the generic call flag early (forward calls).
            let rv = post[135072 + fi * 4 + 1];
            if rv == 0 { rv = post[135072 + fi * 4 + 2]; }
            if rv == 0 { rv = 1; }
            let flag = 1073741824;
            if post[135072 + fi * 4 + 1] >= 100 { flag = flag | 536870912; }
            post[120000 + nid] = flag | rv;
        }
        post[135900] = 0;
        fi = fi + 1;
    }
    return 0;
}

// B5-6: parse a ref[T] type (T = Int/Str/Slice[U8]/Slice[Int]/Buffer[Int]).
// Returns 11/12/13/14/15 and consumes the type; 0 on error.
fn parse_ref_ty(src: Slice[U8], st: Slice[Int], n: Int) -> Int {
    if expect_char(src, st, 114, n) == 0 { return 0; }
    if expect_char(src, st, 101, n) == 0 { return 0; }
    if expect_char(src, st, 102, n) == 0 { return 0; }
    if expect_char(src, st, 91, n) == 0 { return 0; }
    skip(src, st, n);
    let r = 0;
    if st[0] < n && src[st[0]] == 73 {
        if expect_char(src, st, 73, n) == 0 { return 0; }
        if expect_char(src, st, 110, n) == 0 { return 0; }
        if expect_char(src, st, 116, n) == 0 { return 0; }
        r = 11;
    } else if st[0] < n && src[st[0]] == 83 && st[0] + 2 < n && src[st[0] + 1] == 116 && src[st[0] + 2] == 114 {
        if expect_char(src, st, 83, n) == 0 { return 0; }
        if expect_char(src, st, 116, n) == 0 { return 0; }
        if expect_char(src, st, 114, n) == 0 { return 0; }
        r = 12;
    } else if st[0] < n && src[st[0]] == 83 {
        if expect_char(src, st, 83, n) == 0 { return 0; }
        if expect_char(src, st, 108, n) == 0 { return 0; }
        if expect_char(src, st, 105, n) == 0 { return 0; }
        if expect_char(src, st, 99, n) == 0 { return 0; }
        if expect_char(src, st, 101, n) == 0 { return 0; }
        if expect_char(src, st, 91, n) == 0 { return 0; }
        skip(src, st, n);
        if st[0] < n && src[st[0]] == 85 {
            if expect_char(src, st, 85, n) == 0 { return 0; }
            if expect_char(src, st, 56, n) == 0 { return 0; }
            r = 13;
        } else {
            if expect_char(src, st, 73, n) == 0 { return 0; }
            if expect_char(src, st, 110, n) == 0 { return 0; }
            if expect_char(src, st, 116, n) == 0 { return 0; }
            r = 14;
        }
        if expect_char(src, st, 93, n) == 0 { return 0; }
    } else if st[0] + 6 <= n && src[st[0]] == 66 && src[st[0] + 1] == 117 && src[st[0] + 2] == 102 && src[st[0] + 3] == 102 && src[st[0] + 4] == 101 && src[st[0] + 5] == 114 {
        if expect_char(src, st, 66, n) == 0 { return 0; }
        if expect_char(src, st, 117, n) == 0 { return 0; }
        if expect_char(src, st, 102, n) == 0 { return 0; }
        if expect_char(src, st, 102, n) == 0 { return 0; }
        if expect_char(src, st, 101, n) == 0 { return 0; }
        if expect_char(src, st, 114, n) == 0 { return 0; }
        if expect_char(src, st, 91, n) == 0 { return 0; }
        if expect_char(src, st, 73, n) == 0 { return 0; }
        if expect_char(src, st, 110, n) == 0 { return 0; }
        if expect_char(src, st, 116, n) == 0 { return 0; }
        if expect_char(src, st, 93, n) == 0 { return 0; }
        r = 15;
    } else { return 0; }
    if expect_char(src, st, 93, n) == 0 { return 0; }
    return r;
}

// B5: classify a ref parameter type: 11 Int, 12 Str, 13 Slice[U8], 14 Slice[Int].
fn ref_type_code(src: Slice[U8], pos: Int, e: Int) -> Int {
    if pos + 3 <= e && src[pos] == 73 && src[pos + 1] == 110 && src[pos + 2] == 116 { return 11; }
    if pos + 3 <= e && src[pos] == 83 && src[pos + 1] == 116 && src[pos + 2] == 114 { return 12; }
    if pos + 11 <= e && src[pos] == 66 && src[pos + 1] == 117 && src[pos + 2] == 102 && src[pos + 3] == 102 && src[pos + 4] == 101 && src[pos + 5] == 114 && src[pos + 6] == 91 && src[pos + 7] == 73 && src[pos + 8] == 110 && src[pos + 9] == 116 && src[pos + 10] == 93 { return 15; }
    if pos + 9 <= e && src[pos] == 83 && src[pos + 1] == 108 && src[pos + 2] == 105 && src[pos + 3] == 99 && src[pos + 4] == 101 && src[pos + 5] == 91 {
        if src[pos + 6] == 85 && src[pos + 7] == 56 && src[pos + 8] == 93 { return 13; }
        if pos + 10 <= e && src[pos + 6] == 73 && src[pos + 7] == 110 && src[pos + 8] == 116 && src[pos + 9] == 93 { return 14; }
    }
    return 0;
}

// B5-1: record which parameters are `ref` (bit i = parameter i), keyed by
// function index. check_decls packs this into post[30000+name_id] high bits.
fn scan_refmask(src: Slice[U8], fd: Slice[Int], post: Slice[Int]) -> Int {
    let count = fd[0];
    let fi = 0;
    while fi < count {
        let base = 1 + fi * 8;
        let i = fd[base + 6];
        let e = fd[base + 7];
        let mask = 0;
        let pc = 0;
        let depth = 0;
        let start = 1;
        while i < e {
            let c = src[i];
            if depth == 0 && start == 1 {
                if c == 32 || c == 9 || c == 10 || c == 13 { i = i + 1; }
                else if c == 114 && i + 3 <= e && src[i + 1] == 101 && src[i + 2] == 102 && kw_end(src, i + 3, e) == 1 {
                    mask = mask | (1 << pc);
                    let q = i + 3;
                    while q < e && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    while q < e && is_ident_byte(src[q]) == 1 { q = q + 1; }
                    while q < e && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    if q < e && src[q] == 58 { q = q + 1; }
                    while q < e && (src[q] == 32 || src[q] == 9 || src[q] == 10 || src[q] == 13) { q = q + 1; }
                    post[130600 + fi * 8 + pc] = ref_type_code(src, q, e);
                    i = i + 3;
                    start = 0;
                } else { start = 0; }
            } else {
                if c == 91 || c == 40 { depth = depth + 1; }
                else if c == 93 || c == 41 { depth = depth - 1; }
                else if c == 44 && depth == 0 { pc = pc + 1; start = 1; }
                i = i + 1;
            }
        }
        post[130000 + fi] = mask;
        fi = fi + 1;
    }
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
        nsts[0] = ns;
        nsts[1] = nl;
        let nid = name_id(src, nsts, post);
        post[130500 + nid] = (fd[base + 2] + 1) | (post[130000 + k] << 8);
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
// R3.6: structured-diagnostics emission helper (single function: the seed's
// MAX_FUNCS table is exactly full - 127 existing + this one = 128 limit).
//   mode 0: print "line:col: " for source offset `off` (1-based line; 1-based
//           column counting Unicode scalar values - UTF-8 continuation bytes
//           10xxxxxx do not advance the column); `src` must cover [0, off).
//   mode 1: print the decimal form of the non-negative integer `off`.
// Diagnostic paths only - runs once before exit, cost is irrelevant.
fn diag_pos(src: Slice[U8], off: Int, mode: Int) -> Int {
    if mode != 0 {
        let w = off;
        if w == 0 { write("0"); return 0; }
        let p = 1;
        while p <= w / 10 { p = p * 10; }
        while p > 0 {
            let d = (w / p) % 10;
            if d == 0 { write("0"); }
            else if d == 1 { write("1"); }
            else if d == 2 { write("2"); }
            else if d == 3 { write("3"); }
            else if d == 4 { write("4"); }
            else if d == 5 { write("5"); }
            else if d == 6 { write("6"); }
            else if d == 7 { write("7"); }
            else if d == 8 { write("8"); }
            else { write("9"); }
            p = p / 10;
        }
        return 0;
    }
    let ln = 1;
    let i = 0;
    while i < off { if src[i] == 10 { ln = ln + 1; } i = i + 1; }
    let cs = off;
    while cs > 0 { if src[cs - 1] == 10 { break; } cs = cs - 1; }
    let col = 1;
    let j = cs;
    while j < off { let b = src[j]; if b < 128 || b > 191 { col = col + 1; } j = j + 1; }
    let p = 1;
    while p <= ln / 10 { p = p * 10; }
    while p > 0 {
        let d = (ln / p) % 10;
        if d == 0 { write("0"); }
        else if d == 1 { write("1"); }
        else if d == 2 { write("2"); }
        else if d == 3 { write("3"); }
        else if d == 4 { write("4"); }
        else if d == 5 { write("5"); }
        else if d == 6 { write("6"); }
        else if d == 7 { write("7"); }
        else if d == 8 { write("8"); }
        else { write("9"); }
        p = p / 10;
    }
    write(":");
    let q = 1;
    while q <= col / 10 { q = q * 10; }
    while q > 0 {
        let d = (col / q) % 10;
        if d == 0 { write("0"); }
        else if d == 1 { write("1"); }
        else if d == 2 { write("2"); }
        else if d == 3 { write("3"); }
        else if d == 4 { write("4"); }
        else if d == 5 { write("5"); }
        else if d == 6 { write("6"); }
        else if d == 7 { write("7"); }
        else if d == 8 { write("8"); }
        else { write("9"); }
        q = q / 10;
    }
    write(": ");
    return 0;
}

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
                // R2.6-C: `x.method(...)` — an identifier directly after `.`
                // is a member call (receiver is not a caller-supplied argument);
                // the textual arity pre-scan must not count its args.
                if s > 0 && src[s - 1] == 46 { continue; }
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
                            write("stage1: E-LS-ARITY: ");
                            diag_pos(src, s, 0);
                            write("function call argument count mismatch\n");
                            write("  fix-it: expected ");
                            diag_pos(src, fd[kbase + 2], 1);
                            write(" argument(s), call has ");
                            diag_pos(src, actual, 1);
                            write(" - add the missing argument or align the signature\n");
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

