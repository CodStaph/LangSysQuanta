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
    let sast: Slice[Int] = slice_at(ps, 141024, 125000);
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
                    if sast[0] >= 20000 { write("stmts: too many statements\n"); return 4; }
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
