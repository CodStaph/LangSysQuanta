fn emit_stmt_list(mem: Slice[U8], ps: Slice[Int], n: Int) -> Int {
    let ctxi: Slice[Int] = slice_at(ps, 266336, 2112);
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
    let c: Slice[U8] = slice_at(mem, 655360, 1572864);
    let ds: Slice[U8] = slice_at(mem, 2228224, 65536);
    let sast: Slice[Int] = slice_at(ps, 141024, 125000);
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
    let cstk: Array[Int, 32] = Array.zeroed();
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
            if cblk < 0 { sp = sp - 1; }
            else {
                // B5-11: `comptime { <const-expr>; }` is folded at compile time.
                // A zero result is a compile-time assertion failure.
                let cbs = sast[257 + cblk * 6 + 1] + 1;
                let cbe = sast[257 + cblk * 6 + 2] - 1;
                st[0] = cbs; st[1] = cbe; st[2] = 0; st[3] = 0; st[12] = ctxi[DLEN];
                skip(srcs, st, cbe);
                st[1] = n;
                if st[0] >= cbe {
                    sp = sp - 1;
                } else {
                    parse_index1(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("stage1: E-LS-UNSUPPORTED: comptime blocks with non-empty bodies are not implemented in B-LS yet\n"); return 4; }
                    let cn = st[2];
                    let cs0 = 0;
                    let ctop = 0;
                    let cbad = 0;
                    while cs0 < cn {
                        let ck = ps[cs0 * 2];
                        let cv = ps[cs0 * 2 + 1];
                        if ck == 0 {
                            if ctop >= 32 { cbad = 1; break; }
                            cstk[ctop] = cv;
                            ctop = ctop + 1;
                        } else if ck == 2 {
                            if cv == 20 {
                                if ctop < 1 { cbad = 1; break; }
                                cstk[ctop - 1] = 0 - cstk[ctop - 1];
                            } else {
                                if ctop < 2 { cbad = 1; break; }
                                let b2 = cstk[ctop - 1];
                                let a2 = cstk[ctop - 2];
                                ctop = ctop - 2;
                                if cv == 1 { cstk[ctop] = a2 + b2; }
                                else if cv == 2 { cstk[ctop] = a2 - b2; }
                                else if cv == 3 { cstk[ctop] = a2 * b2; }
                                else if cv == 4 { if b2 == 0 { cbad = 1; break; } cstk[ctop] = a2 / b2; }
                                else if cv == 5 { if b2 == 0 { cbad = 1; break; } cstk[ctop] = a2 % b2; }
                                else if cv == 6 { if a2 == b2 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } }
                                else if cv == 7 { if a2 != b2 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } }
                                else if cv == 8 { if a2 < b2 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } }
                                else if cv == 9 { if a2 <= b2 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } }
                                else if cv == 10 { if a2 > b2 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } }
                                else if cv == 11 { if a2 >= b2 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } }
                                else if cv == 12 { if a2 != 0 { cstk[ctop] = 1; } else if b2 != 0 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } }
                                else if cv == 13 { if a2 != 0 { if b2 != 0 { cstk[ctop] = 1; } else { cstk[ctop] = 0; } } else { cstk[ctop] = 0; } }
                                else if cv == 14 { cstk[ctop] = a2 | b2; }
                                else if cv == 15 { cstk[ctop] = a2 ^ b2; }
                                else if cv == 16 { cstk[ctop] = a2 & b2; }
                                else if cv == 17 { cstk[ctop] = a2 << b2; }
                                else if cv == 18 { cstk[ctop] = a2 >> b2; }
                                else { cbad = 1; break; }
                                ctop = ctop + 1;
                            }
                        } else { cbad = 1; break; }
                        cs0 = cs0 + 1;
                    }
                    if cbad != 0 || ctop != 1 {
                        write("stage1: E-LS-COMPTIME: ");
                        diag_pos(srcs, sast[noff + 1], 0);
                        write("comptime block needs a constant expression\n");
                        write("  fix-it: comptime folds literals and constant arithmetic only - move reads and variables out of the block\n");
                        return 4;
                    }
                    if cstk[0] == 0 {
                        write("stage1: E-LS-COMPTIME: ");
                        diag_pos(srcs, sast[noff + 1], 0);
                        write("comptime assertion failed\n");
                        write("  fix-it: the constant folded to 0 - adjust the expression or delete the assertion\n");
                        return 4;
                    }
                    sp = sp - 1;
                }
            }

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
                // R4.7: optional hard quota `region r(cap) { ... }`. The quota is
                // a runtime Int expression, evaluated before the frame is pushed.
                let rcap = 0;
                let rq = scan_skip(srcs, rp, n);
                if rq < n && srcs[rq] == 40 {
                    st[0] = rq + 1; st[1] = n; st[2] = 0; st[3] = 0; st[12] = ctxi[DLEN];
                    parse_index1(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    st[1] = n;
                    if st[3] != 0 { write("region: bad quota expression\n"); return 4; }
                    let rqty = ps[110000 + st[2] - 1];
                    if rqty != 1 && rqty != 2 { write("region: quota must be Int\n"); return 4; }
                    if expect_char(srcs, st, 41, n) == 0 { write("region: expected )\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 80); // push cap (emit_expr leaves it in rax)
                    rcap = 1;
                }
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
                // R4.7: save the previous arena end, then apply the hard quota.
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17041]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[lim]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17012]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rdx,[end]
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 20); emit1(c, cs, 193); // mov [rcx+rax*8],rdx
                if rcap == 1 {
                    emit1(c, cs, 88); // pop rax (cap)
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rdx,[current]
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 209); // mov rcx,rdx
                    emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 193); // add rcx,rax
                    emit1(c, cs, 72); emit1(c, cs, 57); emit1(c, cs, 209); // cmp rcx,rdx
                    emit1(c, cs, 15); emit1(c, cs, 141);
                    let rqlo = cs[0]; emit4(c, cs, 0); // jge ok (cap >= 0)
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 209); // mov rcx,rdx
                    patch_jump(c, rqlo, cs[0]);
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17012]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[end]
                    emit1(c, cs, 72); emit1(c, cs, 57); emit1(c, cs, 193); // cmp rcx,rax
                    emit1(c, cs, 15); emit1(c, cs, 142);
                    let rqhi = cs[0]; emit4(c, cs, 0); // jle ok
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 193); // mov rcx,rax
                    patch_jump(c, rqhi, cs[0]);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 13);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17012]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [end],rcx
                }
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[depth]
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
                // B3-4c/R4.7: pop the frame, restore the previous end, rewind the
                // arena to the entry mark and drop stale holes/handles.
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[depth]
                emit1(c, cs, 72); emit1(c, cs, 131); emit1(c, cs, 232); emit1(c, cs, 1); // sub rax,1
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17013]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [depth],rax
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17041]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[lim]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 20); emit1(c, cs, 193); // mov rdx,[rcx+rax*8]
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17012]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [end],rdx
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17015]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[mark]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 20); emit1(c, cs, 193); // mov rdx,[rcx+rax*8]
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [current],rdx
                // R4.6: drop free-list holes above the region mark.
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 214); // mov rsi,rdx (mark)
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17010]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[base]
                emit1(c, cs, 72); emit1(c, cs, 41); emit1(c, cs, 198); // sub rsi,rax
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 61);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17022]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rdi,[table]
                emit1(c, cs, 255); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17025]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // call [purge]
                // R4.7: invalidate handles of allocations above the mark.
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 61);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17040]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rdi,[ht]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 53);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rsi,[current]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17010]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[base]
                emit1(c, cs, 72); emit1(c, cs, 41); emit1(c, cs, 198); // sub rsi,rax
                emit1(c, cs, 255); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17031]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // call [hpurge]
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
    let ctxi: Slice[Int] = slice_at(ps, 266336, 2112);
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
    let c: Slice[U8] = slice_at(mem, 655360, 1572864);
    let ds: Slice[U8] = slice_at(mem, 2228224, 65536);
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
            if fret_ty[ctxi[NF]] >= 11 && fret_ty[ctxi[NF]] <= 15 {
                            if ctxi[RDEPTH] > 0 { write("stage1: E-LS-UNSUPPORTED: return of a ref inside a region is not implemented in B-LS yet\n"); return 4; }
                skip(srcs, st, n);
                let rr = name_id(srcs, st, ps);
                if st[5] == 0 { write("return: bad ref expression\n"); return 4; }
                let rvi = var_find(ps, rr, ctxi[NF], st[0]);
                if rvi < 0 || (ps[50004 + rvi * 4] & 255) != fret_ty[ctxi[NF]] { write("return: ref type mismatch\n"); return 4; }
                // B5-8: only a reborrow of a `ref` parameter may escape the callee;
                // returning the address of a local slot is a dangling reference.
                let rlv0 = ps[136000 + rvi];
                if rlv0 == 0 || (rlv0 & 1) == 1 {
                    write("stage1: E-LS-REGION-ESCAPE: ");
                    diag_pos(srcs, st[0] - 1, 0);
                    write("cannot return a reference to a local variable\n");
                    write("  fix-it: return a copy of the value, or receive/forward it as a ref parameter (reborrow)\n");
                    return 4;
                }
                if expect_char(srcs, st, 59, n) == 0 { write("return: expected ;\n"); return 4; }
                st[2] = 0;
                push_post(ps, st, 75, rvi);
                set_ty(ps, st, fret_ty[ctxi[NF]]);
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit_ret(c, cs);
                ctxi[HAVE_RET] = 1;
                continue;
            }
            if ctxi[RDEPTH] > 0 {
                // B3-5c: `-> Int` functions unwind their region frames on return.
                if fret_ty[ctxi[NF]] != 1 { write("stage1: E-LS-UNSUPPORTED: return inside a region block is only implemented for -> Int functions\n"); return 4; }
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
            if ps[135743] != ps[135744] {
                // B5-11: save the return value for `result`, assert `ensures`,
                // then restore it (exit 74 on violation).
                emit1(c, cs, 80); // push rax (return value)
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[135746]; cs[2] = cs[2] + 1; emit4(c, cs, 0);
                let esave0 = st[0];
                ps[135745] = 1;
                st[0] = ps[135743]; st[1] = ps[135744]; st[2] = 0; st[3] = 0; st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                ps[135745] = 0;
                st[0] = esave0;
                st[1] = n;
                if st[3] != 0 { write("ensures: bad expression\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 133); emit1(c, cs, 192); // test eax,eax
                emit1(c, cs, 15); emit1(c, cs, 133);
                let eqj = cs[0]; emit4(c, cs, 0);
                emit1(c, cs, 184); emit4(c, cs, 60);
                emit1(c, cs, 191); emit4(c, cs, 74);
                emit1(c, cs, 15); emit1(c, cs, 5);
                patch_jump(c, eqj, cs[0]);
                emit1(c, cs, 88); // pop rax (restore the return value)
            }
            if ctxi[RDEPTH] > 0 {
                // R4.7: evaluate the return value first, then unwind the frames.
                emit1(c, cs, 80); // push rax (return value)
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
                    // R4.7: restore this frame's previous arena end (hard quota).
                    emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 13);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17041]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rcx,[lim]
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 20); emit1(c, cs, 193); // mov rdx,[rcx+rax*8]
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 21);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17012]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [end],rdx
                    // R4.7: invalidate handles above the mark.
                    emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 61);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17040]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // lea rdi,[ht]
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 53);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17011]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rsi,[current]
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17010]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rax,[base]
                    emit1(c, cs, 72); emit1(c, cs, 41); emit1(c, cs, 198); // sub rsi,rax
                    emit1(c, cs, 255); emit1(c, cs, 21);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = ps[17031]; cs[2] = cs[2] + 1; emit4(c, cs, 0); // call [hpurge]
                    ru = ru + 1;
                }
                emit1(c, cs, 88); // pop rax
            }
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
            // B5-10: `let val x: T = ...` binds a frozen (read-only) local.
            let vimm = 0;
            if st[0] + 3 <= n && srcs[st[0]] == 118 && srcs[st[0] + 1] == 97 && srcs[st[0] + 2] == 108 && kw_end(srcs, st[0] + 3, n) == 1 {
                let vp = st[0] + 3;
                while vp < n && (srcs[vp] == 32 || srcs[vp] == 9 || srcs[vp] == 10 || srcs[vp] == 13) { vp = vp + 1; }
                if vp < n && is_ident_byte(srcs[vp]) == 1 {
                    vimm = 1;
                    st[0] = st[0] + 3;
                    skip(srcs, st, n);
                }
            }
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
                if rkind >= 120 || (rkind >= 30 && rkind < 100) {
                    // R2.6-A: a generic struct value return (120+ii).
                    // R2.6-F: a plain B7 struct value return (30+si) uses the
                    // same ABI.  The callee leaves the struct's address in rax
                    // (sv base); copy its fields into a fresh receiver sv so
                    // `g.x` resolves and the value is not clobbered later.
                    let gsz = 0;
                    let gsidx = 0;
                    if rkind >= 120 {
                        gsz = inst_nvariants(ps, rty - 120) * 8;
                        gsidx = 70 + (rty - 120);
                    } else {
                        gsz = st_size(ps, rty - 30);
                        gsidx = rty - 30;
                    }
                    let groff = ctxi[DLEN];
                    ctxi[DLEN] = ctxi[DLEN] + gsz;
                    sv_add(ps, vnm, ctxi[NF], groff | (ctxi[CUR_SEND] << 31), gsidx);
                    emit_expr(c, cs, ps);   // call; rax = return address
                    // copy gsz/8 fields from [rax + w8] to [groff + w8]
                    let w8 = 0;
                    while w8 < gsz / 8 {
                        emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 72); emit1(c, cs, w8 * 8);   // mov rcx,[rax+disp8]
                        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 13);
                        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = groff + w8 * 8; cs[2] = cs[2] + 1; emit4(c, cs, 0);
                        w8 = w8 + 1;
                    }
                } else if rkind == 8 {
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
                    let vi = var_add(ps, vnm, ctxi[NF], voff, var_span(st[0], ctxi[CUR_SEND], vimm));
                    if rty >= 100 && rty < 108 { var_set_ty(ps, vi, rty); }
                    else { var_set_ty(ps, vi, 1); }
                    ps[cs[3] + cs[2] * 2 + 1] = voff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                }
                }
            } else {
            if expect_char(srcs, st, 58, n) == 0 { write("slice: expected :\n"); return 4; }
            skip(srcs, st, n);
            if st[0] + 3 <= n && srcs[st[0]] == 67 && srcs[st[0] + 1] == 97 && srcs[st[0] + 2] == 112 && kw_end(srcs, st[0] + 3, n) == 1 {
                // B5-10: `let c: Cap[Alloc] = 0;` - a static capability token
                // (8-byte placeholder; only `0` is accepted as initializer).
                if expect_char(srcs, st, 67, n) == 0 { write("cap: expected Cap\n"); return 4; }
                if expect_char(srcs, st, 97, n) == 0 { write("cap: expected Cap\n"); return 4; }
                if expect_char(srcs, st, 112, n) == 0 { write("cap: expected Cap\n"); return 4; }
                skip(srcs, st, n);
                if expect_char(srcs, st, 91, n) == 0 { write("cap: expected [\n"); return 4; }
                skip(srcs, st, n);
                let cstart = st[0];
                let cnm = name_id(srcs, st, ps);
                if st[5] == 0 { write("cap: bad capability name\n"); return 4; }
                let cbit = eff_bit(srcs, cstart, st[0] - cstart);
                if cbit <= 0 { write("cap: unknown capability\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("cap: expected ]\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("cap: expected =\n"); return 4; }
                skip(srcs, st, n);
                if st[0] >= n || srcs[st[0]] != 48 { write("cap: token initializer must be 0\n"); return 4; }
                st[0] = st[0] + 1;
                if expect_char(srcs, st, 59, n) == 0 { write("cap: expected ;\n"); return 4; }
                let coff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 8;
                emit1(c, cs, 72); emit1(c, cs, 49); emit1(c, cs, 192); // xor rax,rax
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = coff;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                let cvi = var_add(ps, vnm, ctxi[NF], coff, var_span(st[0], ctxi[CUR_SEND], 0));
                var_set_ty(ps, cvi, 1);
            } else if st[0] + 3 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 {
                // B5-6: `let r: ref[T] = x;` / `= f(...)` (T = Int/Str/Slice/Buffer).
                let rt = parse_ref_ty(srcs, st, n);
                if rt == 0 { write("let: bad ref type\n"); return 4; }
                if expect_char(srcs, st, 61, n) == 0 { write("let: expected =\n"); return 4; }
                skip(srcs, st, n);
                let save = st[0];
                let rn = name_id(srcs, st, ps);
                let iscall = 0;
                if st[0] < n && srcs[st[0]] == 40 { iscall = 1; }
                let voff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 8;
                let rai = arr_find(ps, rn, ctxi[NF]);
                let relem = 0;
                if rai >= 0 {
                    relem = (ps[4098 + rai * 3] >> 31) & 15;
                }
                if st[0] < n && srcs[st[0]] == 91 && rai >= 0 {
                    if relem >= 11 {
                        // B5-9: `let q: ref[T] = a[i]` on Array[ref[T]] loads the
                        // stored pointer; its lifetime is bounded by the array.
                        if relem != rt { write("let: ref element type mismatch\n"); return 4; }
                        st[0] = st[0] + 1;
                        st[2] = 0;
                        parse_index(srcs, st, ps);
                        if st[3] != 0 { write("let: bad ref index\n"); return 4; }
                        if expect_char(srcs, st, 93, n) == 0 { write("let: expected ]\n"); return 4; }
                        if expect_char(srcs, st, 59, n) == 0 { write("let: expected ;\n"); return 4; }
                        push_post(ps, st, 10, rai);
                        set_ty(ps, st, rt);
                        cs[1] = st[2];
                        emit_expr(c, cs, ps);
                        emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = voff; cs[2] = cs[2] + 1; emit4(c, cs, 0);
                        st[2] = 0;
                        let rvie = var_add(ps, vnm, ctxi[NF], voff, var_span(st[0], ctxi[CUR_SEND], 0));
                        var_set_ty(ps, rvie, rt);
                        if rvie < 4000 { ps[136000 + rvie] = (ps[4099 + rai * 3] << 1) | 1; }
                        continue;
                    }
                }
                if st[0] < n && srcs[st[0]] == 91 && rt == 11 && rai >= 0 {
                    if relem != 8 { write("let: ref array element must be Int\n"); return 4; }
                    st[0] = st[0] + 1;
                    st[2] = 0;
                    parse_index(srcs, st, ps);
                    if st[3] != 0 { write("let: bad ref index\n"); return 4; }
                    if expect_char(srcs, st, 93, n) == 0 { write("let: expected ]\n"); return 4; }
                    if expect_char(srcs, st, 59, n) == 0 { write("let: expected ;\n"); return 4; }
                    push_post(ps, st, 86, rai);
                    set_ty(ps, st, rt);
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = voff; cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    st[2] = 0;
                    let rvi3 = var_add(ps, vnm, ctxi[NF], voff, var_span(st[0], ctxi[CUR_SEND], 0));
                    var_set_ty(ps, rvi3, rt);
                    // B5-8: element address of a local array; the current block end
                    // is a sound lower bound for the array's lifetime.
                    if rvi3 < 4000 { ps[136000 + rvi3] = (ctxi[CUR_SEND] << 1) | 1; }
                    continue;
                }
                let rlv = 1;
                if iscall == 1 || (st[0] < n && srcs[st[0]] != 59) || st[0] >= n {
                    st[0] = save;
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("let: bad ref expr\n"); return 4; }
                    let rty = ps[110000 + st[2] - 1];
                    if rty != rt { write("let: ref type mismatch\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    rlv = ps[135802];
                } else {
                    st[0] = save;
                    let rn2 = name_id(srcs, st, ps);
                    let rvi = var_find(ps, rn2, ctxi[NF], st[0]);
                    if rvi < 0 {
                        if rt == 12 {
                            let si = str_find(ps, rn2, ctxi[NF]);
                            if si < 0 { write("let: unknown ref source\n"); return 4; }
                            push_post(ps, st, 81, si);
                            set_ty(ps, st, rt);
                        } else if rt == 13 || rt == 14 {
                            let si = sl_find(ps, rn2, ctxi[NF]);
                            if si < 0 { write("let: unknown ref source\n"); return 4; }
                            let se = (ps[66402 + si * 2] >> 31) & 15;
                            if rt == 13 && se != 1 { write("let: ref type mismatch\n"); return 4; }
                            if rt == 14 && se != 8 { write("let: ref type mismatch\n"); return 4; }
                            push_post(ps, st, 82, si);
                            set_ty(ps, st, rt);
                        } else { write("let: unknown ref source\n"); return 4; }
                        // B5-8: Str/Slice local slot; the current block end is a
                        // sound lower bound for its declaration scope end.
                        rlv = (ctxi[CUR_SEND] << 1) | 1;
                    } else {
                        let rvt = ps[50004 + rvi * 4] & 255;
                        if rvt == rt {
                            push_post(ps, st, 75, rvi);
                            set_ty(ps, st, rt);
                            // Reborrow: inherit the tracked lifetime of the source.
                            rlv = ps[136000 + rvi];
                        } else {
                            let base = 1;
                            if rt == 12 { base = 3; }
                            else if rt == 13 { base = 4; }
                            else if rt == 14 { base = 5; }
                            else if rt == 15 { base = 9; }
                            if rvt != base { write("let: ref type mismatch\n"); return 4; }
                            if rt == 12 { push_post(ps, st, 81, rvi); }
                            else if rt == 13 || rt == 14 { push_post(ps, st, 82, rvi); }
                            else { push_post(ps, st, 74, rvi); }
                            set_ty(ps, st, rt);
                            rlv = (((ps[50004 + rvi * 4] >> 30) & 1048575) << 1) | 1;
                        }
                    }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                }
                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = voff; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov [voff],rax
                st[2] = 0;
                let rvi2 = var_add(ps, vnm, ctxi[NF], voff, var_span(st[0], ctxi[CUR_SEND], 0));
                var_set_ty(ps, rvi2, rt);
                if rvi2 < 4000 { ps[136000 + rvi2] = rlv; }
                if expect_char(srcs, st, 59, n) == 0 { write("let: expected ;\n"); return 4; }
            } else if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
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
            } else if st[0] + 6 <= n && srcs[st[0]] == 79 && srcs[st[0] + 1] == 112 && srcs[st[0] + 2] == 116 && srcs[st[0] + 3] == 105 && srcs[st[0] + 4] == 111 && srcs[st[0] + 5] == 110 && kw_end(srcs, st[0] + 6, n) == 1 {

                if expect_char(srcs, st, 79, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 112, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 111, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("let: expected Option\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("let: expected [\n"); return 4; }
                let t1 = parse_ty(srcs, st, ps);
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
            } else if st[0] + 6 <= n && srcs[st[0]] == 82 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 115 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 108 && srcs[st[0] + 5] == 116 && kw_end(srcs, st[0] + 6, n) == 1 {
                if expect_char(srcs, st, 82, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 115, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 117, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 108, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("let: expected Result\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("let: expected [\n"); return 4; }
                let t1 = parse_ty(srcs, st, ps);
                if st[3] != 0 || t1 == 0 { write("let: bad Result type\n"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("let: expected ,\n"); return 4; }
                let t2 = parse_ty(srcs, st, ps);
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
            } else if st[0] + 3 <= n && srcs[st[0]] == 83 && srcs[st[0] + 1] == 116 && srcs[st[0] + 2] == 114 && kw_end(srcs, st[0] + 3, n) == 1 {
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
                } else if st[0] + 3 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 {
                    // B5-9: Array[ref[T], N] stores 8-byte pointers.
                    elem = parse_ref_ty(srcs, st, n);
                    if elem == 0 { write("slice: bad ref element type\n"); return 4; }
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
                if elem >= 11 { ctxi[DLEN] = ctxi[DLEN] + 8 * cnt; }
                else { ctxi[DLEN] = ctxi[DLEN] + elem * cnt; }
                add_arr(ps, vnm, aoff | (elem << 31) | (ctxi[NF] << 35) | (cnt << 42), ctxi[CUR_SEND]);
            } else if st[0] + 5 <= n && srcs[st[0]] == 83 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 105 && srcs[st[0] + 3] == 99 && srcs[st[0] + 4] == 101 && kw_end(srcs, st[0] + 5, n) == 1 {
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
                if expect_char(srcs, st, 115, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 108, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 99, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 101, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 95, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 97, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("slice_at: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 40, n) == 0 { write("slice_at: expected (\n"); return 4; }
                skip(srcs, st, n);
                let snm = name_id(srcs, st, ps);
                if st[5] == 0 { write("slice_at: bad source name\n"); return 4; }
                let sbase = 0;
                let ssi = sl_find(ps, snm, ctxi[NF]);
                if ssi >= 0 {
                    let smeta = ps[66402 + ssi * 2];
                    let selem = (smeta >> 31) & 15;
                    if selem != elem { write("slice_at: element size mismatch\n"); return 4; }
                    sbase = smeta & 2147483647;
                } else {
                    let svi = str_find(ps, snm, ctxi[NF]);
                    if svi < 0 { write("slice_at: source is not a Slice or Str\n"); return 4; }
                    if elem != 1 { write("slice_at: Str source needs Slice[U8]\n"); return 4; }
                    sbase = ps[15003 + svi * 4];
                }
                if expect_char(srcs, st, 44, n) == 0 { write("slice_at: expected ,\n"); return 4; }
                let soff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 16;
                add_sl(ps, vnm, soff | (elem << 31) | (ctxi[NF] << 35));
                st[2] = 0;
                st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("slice_at: bad offset\n"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("slice_at: expected ,\n"); return 4; }
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
                if st[3] != 0 { write("slice_at: bad length\n"); return 4; }
                if expect_char(srcs, st, 41, n) == 0 { write("slice_at: expected )\n"); return 4; }
                if expect_char(srcs, st, 59, n) == 0 { write("slice_at: expected ;\n"); return 4; }
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
                let ameta = ps[4098 + ai * 3];
                if ((ameta >> 31) & 15) >= 11 {
                    write("stage1: E-LS-UNSUPPORTED: Slice of ref elements is not implemented in B-LS yet\n");
                    return 4;
                }
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
                st[1] = n;
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
                // R2.2: generic structs reuse the tmpl table with nparams bit 7
                // set; test that bit BEFORE the plain `st` row (scan_funcs
                // pre-registers every struct name there, generic or not).
                let sti = tmpl_find(ps, tnm);
                let is_sgen = 0;
                if sti >= 0 {
                    if (ps[123001 + sti * 12 + 1] & 128) != 0 { is_sgen = 1; }
                }
                if is_sgen == 1 {
                // R2.2: generic struct instance `let p: S[Int, Str];`.
                skip(srcs, st, n);
                if st[0] >= n || srcs[st[0]] != 91 { write("struct: expected [\n"); return 4; }
                st[0] = st[0] + 1;
                let it1 = parse_ty(srcs, st, ps);
                if st[3] != 0 || it1 == 0 { write("struct: bad generic type\n"); return 4; }
                let it2 = 0;
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 44 {
                    st[0] = st[0] + 1;
                    it2 = parse_ty(srcs, st, ps);
                    if st[3] != 0 || it2 == 0 { write("struct: bad generic type\n"); return 4; }
                }
                if expect_char(srcs, st, 93, n) == 0 { write("struct: expected ]\n"); return 4; }
                let gi = tmpl_find(ps, tnm);
                let ii = mk_inst(ps, gi, it1, it2);
                if ii < 0 { write("struct: bad instance\n"); return 4; }
                let gsz = inst_nvariants(ps, ii) * 8;
                let soff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + gsz;
                sv_add(ps, vnm, ctxi[NF], soff | (ctxi[CUR_SEND] << 31), 70 + ii);
                if expect_char(srcs, st, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
            } else if si >= 0 {
                let sz = st_size(ps, si);
                let soff = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + sz;
                sv_add(ps, vnm, ctxi[NF], soff | (ctxi[CUR_SEND] << 31), si);
                if expect_char(srcs, st, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
            } else {
                write("struct: unknown type\n");
                return 4;
            }
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
                        } else if ty >= 30 {
                            // B5-12: struct payload binding (one slot per field).
                            let ssz2 = st_size(ps, ty - 30);
                            boff = ctxi[DLEN]; ctxi[DLEN] = ctxi[DLEN] + ssz2;
                            sv_add(ps, bname, ctxi[NF], boff | (ctxi[CUR_SEND] << 31), ty - 30);
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
                            // B5-9: a ref payload keeps its pointer type; the
                            // lifetime is unknown, which stays on the safe side.
                            if bty >= 11 && bty <= 15 { var_set_ty(ps, bvi2, bty); }
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
                        } else if bty >= 30 {
                            // B5-12: copy the struct payload slots into the binding.
                            let ssz3 = st_size(ps, bty - 30);
                            emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 194); // mov rdx,rax (payload block)
                            let sk2 = 0;
                            while sk2 * 8 < ssz3 {
                                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 66); emit1(c, cs, 8 + sk2 * 8); // mov rax,[rdx+8+k*8]
                                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = boff + sk2 * 8; cs[2] = cs[2] + 1; emit4(c, cs, 0);
                                sk2 = sk2 + 1;
                            }
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
                ps[131960] = ps[131960] | 2;
                let bvi = var_find(ps, vnm, ctxi[NF], st[0]);
                st[0] = st[0] + 1;
                st[2] = 0;
                push_handle(ps, st, bvi);
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
            // B5-9: for Array[ref[T]] element writes the value is a ref pointer.
            let aiw = arr_find(ps, vnm, ctxi[NF]);
            let wsel = 0;
            if aiw >= 0 {
                let welem = (ps[4098 + aiw * 3] >> 31) & 15;
                if welem >= 11 { wsel = welem; }
            }
            st[10] = wsel;
            st[2] = 0;
            st[12] = ctxi[DLEN];
            parse_expr(srcs, st, ps);
            ctxi[DLEN] = st[12];
            st[10] = 0;
            if st[3] != 0 { write("slice: bad value\n"); return 4; }
            if expect_char(srcs, st, 59, n) == 0 { write("slice: expected ;\n"); return 4; }
            cs[1] = st[2];
            emit_expr(c, cs, ps);
            emit1(c, cs, 89); // pop rcx = index
            let rvi = var_find(ps, vnm, ctxi[NF], st[0]);
            let rvt = 0;
            if rvi >= 0 { rvt = ps[50004 + rvi * 4] & 255; }
            if rvt == 13 || rvt == 14 {
                let bvty = ps[110000 + st[2] - 1];
                if bvty != 1 && bvty != 2 { write("ref slice: value must be Int/U8\n"); return 4; }
                let roff = ps[50003 + rvi * 4];
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = roff; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rdx,[slot]
                emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 18); // mov rdx,[rdx]
                if rvt == 14 {
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 4); emit1(c, cs, 202); // mov [rdx+rcx*8],rax
                } else {
                    emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 209); // add rcx,rdx
                    emit1(c, cs, 136); emit1(c, cs, 1); // mov [rcx],al
                }
                continue;
            }
            let ai = arr_find(ps, vnm, ctxi[NF]);
            if ai >= 0 {
                let meta = ps[4098 + ai * 3];
                let off = meta & 2147483647;
                let elem = (meta >> 31) & 15;
                if elem >= 11 {
                    // B5-9: Array[ref[T]] element write; the stored pointer must
                    // outlive the array (same rule as ref struct fields).
                    let evty = ps[110000 + st[2] - 1];
                    if evty != elem { write("array: ref element type mismatch\n"); return 4; }
                    let eal = ps[135802];
                    if eal == 0 { eal = 1; }
                    let elo = eal & 1;
                    if elo == 1 && (eal >> 1) < ps[4099 + ai * 3] {
                        write("stage1: E-LS-REGION-ESCAPE: ");
                        diag_pos(srcs, st[0] - 1, 0);
                        write("reference to a local escapes into a longer-lived array\n");
                        write("  fix-it: declare the array in a shorter-lived (inner) scope, or store a copy of the value\n");
                        return 4;
                    }
                }
                emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 21);
                ps[cs[3] + cs[2] * 2] = cs[0];
                ps[cs[3] + cs[2] * 2 + 1] = off;
                cs[2] = cs[2] + 1;
                emit4(c, cs, 0);
                if elem == 8 || elem >= 11 {
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 4); emit1(c, cs, 202);
                } else {
                    emit1(c, cs, 72); emit1(c, cs, 1); emit1(c, cs, 209);
                    emit1(c, cs, 136); emit1(c, cs, 1);
                }
            } else {
                let si = sl_find(ps, vnm, ctxi[NF]);
                if si < 0 { write("slice: unknown index target\n"); return 4; }
                let meta = ps[66402 + si * 2];
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
                if bvi >= 0 && ((ps[50004 + bvi * 4] & 255) == 9 || (ps[50004 + bvi * 4] & 255) == 15) {
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
                if sidx >= 70 {
                    // R2.2: generic instance field write `p.f = e;` - every
                    // field is a boxed 8-byte slot taken from the shared
                    // instance table (ti by name, concrete fty).
                    let gii = sidx - 70;
                    let gfi = inst_var_find(ps, gii, fld);
                    if gfi < 0 { write("struct: unknown field\n"); return 4; }
                    let gty = inst_var_pty(ps, gii, gfi);
                    let goff = (ps[6403 + svi * 4] & 2147483647) + gfi * 8;
                    if expect_char(srcs, st, 61, n) == 0 { write("struct: expected =\n"); return 4; }
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("struct: bad field value\n"); return 4; }
                    let wty = ps[110000 + st[2] - 1];
                    if wty != gty { write("struct: field type mismatch\n"); return 4; }
                    if expect_char(srcs, st, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0];
                    ps[cs[3] + cs[2] * 2 + 1] = goff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                    continue;
                }
                let fi = st_field_find(ps, sidx, fld);
                if fi < 0 { write("struct: unknown field\n"); return 4; }
                let fb = 5121 + sidx * 18;
                let fmeta = ps[fb + 3 + fi * 2];
                let off = (ps[6403 + svi * 4] & 2147483647) + (fmeta & 2147483647);
                let elem = (fmeta >> 31) & 15;
                if expect_char(srcs, st, 61, n) == 0 { write("struct: expected =\n"); return 4; }
                if elem >= 11 {
                    skip(srcs, st, n);
                    let save = st[0];
                    let rn = name_id(srcs, st, ps);
                    let iscall = 0;
                    if st[0] < n && srcs[st[0]] == 40 { iscall = 1; }
                    let flife = 1;
                    if iscall == 1 || (st[0] < n && srcs[st[0]] != 59) || st[0] >= n {
                        st[0] = save;
                        st[2] = 0;
                        st[12] = ctxi[DLEN];
                        parse_expr(srcs, st, ps);
                        ctxi[DLEN] = st[12];
                        if st[3] != 0 { write("struct: bad ref field value\n"); return 4; }
                        let rty = ps[110000 + st[2] - 1];
                        if rty != elem { write("struct: ref field type mismatch\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, cs, ps);
                        flife = ps[135802];
                    } else {
                        st[0] = save;
                        let rn2 = name_id(srcs, st, ps);
                        let rvi = var_find(ps, rn2, ctxi[NF], st[0]);
                        if rvi < 0 { write("struct: unknown ref field source\n"); return 4; }
                        let rvt = ps[50004 + rvi * 4] & 255;
                        if rvt == elem {
                            push_post(ps, st, 75, rvi);
                            flife = ps[136000 + rvi];
                        } else {
                            let base = 1;
                            if elem == 12 { base = 3; }
                            else if elem == 13 { base = 4; }
                            else if elem == 14 { base = 5; }
                            else if elem == 15 { base = 9; }
                            if rvt != base { write("struct: ref field type mismatch\n"); return 4; }
                            if elem == 12 { push_post(ps, st, 81, rvi); }
                            else if elem == 13 || elem == 14 { push_post(ps, st, 82, rvi); }
                            else { push_post(ps, st, 74, rvi); }
                            flife = (((ps[50004 + rvi * 4] >> 30) & 1048575) << 1) | 1;
                        }
                        set_ty(ps, st, elem);
                        cs[1] = st[2];
                        emit_expr(c, cs, ps);
                    }
                    // B5-8: a pointer to a local slot must not be stored into a
                    // struct that outlives the referenced variable.
                    let flo = flife & 1;
                    if flife == 0 { flo = 1; }
                    if flo == 1 && (flife >> 1) < (ps[6403 + svi * 4] >> 31) {
                        write("stage1: E-LS-REGION-ESCAPE: ");
                        diag_pos(srcs, st[0] - 1, 0);
                        write("reference to a local escapes into a longer-lived field\n");
                        write("  fix-it: declare the struct in a shorter-lived (inner) scope, or store a copy of the value\n");
                        return 4;
                    }
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = off; cs[2] = cs[2] + 1; emit4(c, cs, 0);
                    if expect_char(srcs, st, 59, n) == 0 { write("struct: expected ;\n"); return 4; }
                    continue;
                }
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
                let vi = var_find(ps, vnm, ctxi[NF], st[0]);
                if vi < 0 { write("assign: unknown variable\n"); return 4; }
                let vty = ps[50004 + vi * 4] & 255;
                if vty == 9 { write("stage1: E-LS-UNSUPPORTED: Buffer[Int] assignment is not implemented in B-LS yet\n"); return 4; }
                                if vty == 15 { write("stage1: E-LS-UNSUPPORTED: assignment through ref Buffer is not implemented in B-LS yet\n"); return 4; }
                if ((ps[50004 + vi * 4] >> 8) & 1) == 1 { write("assign: val binding is immutable\n"); return 4; }
                let voff = ps[50003 + vi * 4];
                if vty == 12 {
                    st[12] = ctxi[DLEN];
                    if st[0] < n && srcs[st[0]] == 34 {
                        let slen = parse_str_lit(srcs, st, ds);
                        if st[3] != 0 { write("str: bad literal\n"); return 4; }
                        let chars = utf8_count(ds, st[7], slen);
                        emit1(c, cs, 72); emit1(c, cs, 141); emit1(c, cs, 5);
                        ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = st[7]; cs[2] = cs[2] + 1; emit4(c, cs, 0);
                        emit1(c, cs, 80);
                        emit1(c, cs, 72); emit1(c, cs, 184); emit4(c, cs, slen); emit4(c, cs, 0);
                        emit1(c, cs, 80);
                        emit1(c, cs, 72); emit1(c, cs, 184); emit4(c, cs, chars); emit4(c, cs, 0);
                    } else {
                        st[2] = 0;
                        parse_expr(srcs, st, ps);
                        ctxi[DLEN] = st[12];
                        if st[3] != 0 { write("assign: bad expr\n"); return 4; }
                        let rty = ps[110000 + st[2] - 1];
                        if rty != 3 { write("ref assign: value must be Str\n"); return 4; }
                        cs[1] = st[2];
                        emit_expr(c, cs, ps);
                    }
                    // emit_expr leaves chars in rax and base/len on the stack;
                    // the literal path mirrors that shape.
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 61);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = voff; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rdi,[slot]
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 71); emit1(c, cs, 16); // mov [rdi+16],rax
                    emit1(c, cs, 88); // pop rax (len)
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 71); emit1(c, cs, 8); // mov [rdi+8],rax
                    emit1(c, cs, 88); // pop rax (base)
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 7); // mov [rdi],rax
                } else if vty == 13 || vty == 14 {
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("assign: bad expr\n"); return 4; }
                    let rty = ps[110000 + st[2] - 1];
                    if vty == 13 && rty != 4 { write("ref assign: value must be Slice[U8]\n"); return 4; }
                    if vty == 14 && rty != 5 { write("ref assign: value must be Slice[Int]\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 61);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = voff; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rdi,[slot]
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 71); emit1(c, cs, 8); // mov [rdi+8],rax (len)
                    emit1(c, cs, 88); // pop rax (base)
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 7); // mov [rdi],rax
                } else if vty == 11 {
                    st[2] = 0;
                    st[12] = ctxi[DLEN];
                    parse_expr(srcs, st, ps);
                    ctxi[DLEN] = st[12];
                    if st[3] != 0 { write("assign: bad expr\n"); return 4; }
                    let rty = ps[110000 + st[2] - 1];
                    if rty != 1 && rty != 2 { write("ref assign: value must be Int\n"); return 4; }
                    cs[1] = st[2];
                    emit_expr(c, cs, ps);
                    emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 13);
                    ps[cs[3] + cs[2] * 2] = cs[0]; ps[cs[3] + cs[2] * 2 + 1] = voff; cs[2] = cs[2] + 1; emit4(c, cs, 0); // mov rcx,[slot]
                    emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 1); // mov [rcx],rax
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
                    ps[cs[3] + cs[2] * 2 + 1] = voff;
                    cs[2] = cs[2] + 1;
                    emit4(c, cs, 0);
                }
                }
                if expect_char(srcs, st, 59, n) == 0 { write("assign: expected ;\n"); return 4; }
            }
        }
    }
    return 0;
}

fn emit_body(mem: Slice[U8], ps: Slice[Int], n: Int) -> Int {
    // post's tail is reserved for the packed Int state (see main).
    let ctxi: Slice[Int] = slice_at(ps, 266336, 2112);
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
    // membuf layout: src [0,655360), code [655360,2228224), data [2228224,2293760).
    let srcs: Slice[U8] = slice_at(mem, 0, n);
    let c: Slice[U8] = slice_at(mem, 655360, 1572864);
    let ds: Slice[U8] = slice_at(mem, 2228224, 65536);
    let i = 0;
    let done = 0;
    let in_end = 0 - 1;
    while done == 0 {
        skip(srcs, st, n);
        if st[0] >= n { done = 1; }
        else {
            if in_end >= 0 && st[0] + 1 >= in_end {
                // B7: leaving an impl block - swallow its closing brace.
                in_end = 0 - 1;
                st[0] = st[0] + 1;
                continue;
            }
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
                // B7: reuse the name row pre-registered by scan_funcs so impl
                // headers and field rows all resolve against one entry.
                let si = st_add(ps, snm);
                let ssi = st_find(ps, snm);
                if ssi >= 0 { si = ssi; }
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 91 {
                    // R2.2: generic struct S[A, B] { f0: A, f1: Int, ... }.
                    // Fields live in the shared generic-template table (index
                    // 123000); generic-parameter fields carry 100+gi, concrete
                    // fields 1/2/3.  Layout matches tmpl_* exactly, so the same
                    // adders are reused (field slot = the enum-variant slot).
                    ps[135899] = 0 - 1;
                    let gc = scan_generic_list(srcs, st, ps);
                    if st[3] != 0 { return 4; }
                    if gc <= 0 { write("struct: bad generic params\n"); return 4; }
                    // nparams bit 7 also marks this as a struct template (see
                    // parse_user_desc); the count itself is `gc & 127`.
                    let ti = tmpl_add(ps, snm, gc | 128);
                    if expect_char(srcs, st, 123, n) == 0 { write("struct: expected {\n"); return 4; }
                    while 1 {
                        skip(srcs, st, n);
                        if st[0] < n && srcs[st[0]] == 125 { break; }
                        let fname = name_id(srcs, st, ps);
                        if st[5] == 0 { write("struct: bad field\n"); return 4; }
                        if expect_char(srcs, st, 58, n) == 0 { write("struct: expected :\n"); return 4; }
                        skip(srcs, st, n);
                        let gty = gen_peek(srcs, st, ps);
                        if gty >= 100 && gty < 108 {
                            tmpl_var_add(ps, ti, fname, gty);
                        } else {
                            let fty = 0;
                            if st[0] < n && srcs[st[0]] == 73 {
                                if expect_char(srcs, st, 73, n) == 0 { write("struct: expected Int\n"); return 4; }
                                if expect_char(srcs, st, 110, n) == 0 { write("struct: expected Int\n"); return 4; }
                                if expect_char(srcs, st, 116, n) == 0 { write("struct: expected Int\n"); return 4; }
                                fty = 1;
                            } else if st[0] < n && srcs[st[0]] == 85 {
                                if expect_char(srcs, st, 85, n) == 0 { write("struct: expected U8\n"); return 4; }
                                if expect_char(srcs, st, 56, n) == 0 { write("struct: expected U8\n"); return 4; }
                                fty = 2;
} else if st[0] + 4 < n && srcs[st[0]] == 83 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 105 && srcs[st[0] + 3] == 99 && srcs[st[0] + 4] == 101 {
                                if expect_char(srcs, st, 83, n) == 0 { write("struct: expected Str\n"); return 4; }
                                if expect_char(srcs, st, 116, n) == 0 { write("struct: expected Str\n"); return 4; }
                                if expect_char(srcs, st, 114, n) == 0 { write("struct: expected Str\n"); return 4; }
                                fty = 3;
                            } else {
                                write("struct: bad generic field type\n");
                                return 4;
                            }
                            tmpl_var_add(ps, ti, fname, fty);
                        }
                        skip(srcs, st, n);
                        if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                    }
                    if expect_char(srcs, st, 125, n) == 0 { write("struct: expected }\n"); return 4; }
                    ps[135900] = 0;
                    continue;
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
                    if st[0] + 3 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 {
                        elem = parse_ref_ty(srcs, st, n);
                        if elem == 0 { write("struct: bad ref field type\n"); return 4; }
                    } else if st[0] < n && srcs[st[0]] == 85 {
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
                    if elem >= 11 { foff = foff + 8; }
                    else { foff = foff + elem; }
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
                    ps[135899] = 0 - 1;
                    nparams = scan_generic_list(srcs, st, ps);
                    if st[3] != 0 { return 4; }
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
                        pty = parse_ty(srcs, st, ps);
                        if pty == 0 { write("enum: bad payload type\n"); return 4; }
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
                ps[135900] = 0;
            } else if srcs[st[0]] == 116 && st[0] + 1 < n && srcs[st[0] + 1] == 114 {
                // B7 trait item: declaration only; emits no code. Scan_funcs
                // already registered the trait and checked its block.
                st[0] = st[0] + 5;
                skip(srcs, st, n);
                name_id(srcs, st, ps);
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 91 { while st[0] < n && srcs[st[0]] != 93 { st[0] = st[0] + 1; } if st[0] < n { st[0] = st[0] + 1; } }
                skip(srcs, st, n);
                if st[0] >= n || srcs[st[0]] != 123 { write("stage1: E-LS-UNSUPPORTED: trait block is malformed\n"); return 4; }
                let tbend2 = scan_block_end(srcs, st[0], n);
                if tbend2 < 0 { write("stage1: E-LS-UNSUPPORTED: trait block is malformed\n"); return 4; }
                st[0] = tbend2;
            } else if srcs[st[0]] == 105 && st[0] + 1 < n && srcs[st[0] + 1] == 109 {
                // B7 impl item: consume the `impl Trait for Ty {` header; the
                // fns inside parse as ordinary top-level fns (flat namespace).
                st[0] = st[0] + 4;
                skip(srcs, st, n);
                name_id(srcs, st, ps);
                skip(srcs, st, n);
                if st[0] < n && srcs[st[0]] == 91 { while st[0] < n && srcs[st[0]] != 93 { st[0] = st[0] + 1; } if st[0] < n { st[0] = st[0] + 1; } }
                skip(srcs, st, n);
                if st[0] + 3 > n || srcs[st[0]] != 102 || srcs[st[0] + 1] != 111 || srcs[st[0] + 2] != 114 || (st[0] + 3 < n && is_ident_byte(srcs[st[0] + 3]) == 1) { write("impl: expected for\n"); return 4; }
                st[0] = st[0] + 3;
                skip(srcs, st, n);
                name_id(srcs, st, ps);
                skip(srcs, st, n);
                if st[0] >= n || srcs[st[0]] != 123 { write("stage1: E-LS-UNSUPPORTED: impl block is malformed\n"); return 4; }
                let ibend3 = scan_block_end(srcs, st[0], n);
                if ibend3 < 0 { write("stage1: E-LS-UNSUPPORTED: impl block is malformed\n"); return 4; }
                in_end = ibend3;
                st[0] = st[0] + 1;
            } else {
            if expect_char(srcs, st, 102, n) == 0 { write("slice: expected fn\n"); return 4; }
            if expect_char(srcs, st, 110, n) == 0 { write("slice: expected fn\n"); return 4; }
            skip(srcs, st, n);
            let fnm = name_id(srcs, st, ps);
            // B5-10: per-function effect tables start clean (signature parsing
            // writes the declared eff / cap masks from here on).
            ps[135700] = 0;
            if st[5] == 4 && srcs[st[0] - 4] == 109 && srcs[st[0] - 3] == 97 && srcs[st[0] - 2] == 105 && srcs[st[0] - 1] == 110 { ps[135700] = 1; }
            ps[131700 + ctxi[NF]] = 0;
            ps[131830 + ctxi[NF]] = 0;
            ps[131960] = 0;
            ps[135741] = 0;
            ps[135742] = 0;
            ps[135743] = 0;
            ps[135744] = 0;
            ps[135745] = 0;
            ps[135746] = 0;
            if st[5] == 0 { write("slice: bad name\n"); return 4; }
            let is_gen = 0;
            skip(srcs, st, n);
            if st[0] < n && srcs[st[0]] == 91 {
                is_gen = 1;
                ps[135899] = ctxi[NF];
                let gp = scan_generic_list(srcs, st, ps);
                if st[3] != 0 { return 4; }
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
                    // B5-1: `ref x: Int` is a mutable temporary borrow.
                    let rp = st[0] + 3;
                    while rp < n && (srcs[rp] == 32 || srcs[rp] == 9 || srcs[rp] == 10 || srcs[rp] == 13) { rp = rp + 1; }
                    if rp < n && is_ident_byte(srcs[rp]) == 1 {
                        vmode = 2;
                        st[0] = st[0] + 3;
                        skip(srcs, st, n);
                    } else {
                        write("stage1: E-LS-UNSUPPORTED: ref parameters are not implemented in B-LS yet\n");
                        return 4;
                    }
                }
                let pid = name_id(srcs, st, ps);
                if st[5] == 0 { write("names: bad param\n"); return 4; }
                fparams[pc] = pid;
                if expect_char(srcs, st, 58, n) == 0 { write("names: expected :\n"); return 4; }
                skip(srcs, st, n);
                let pe = 0;
                let gpc = gen_peek(srcs, st, ps);
                if gpc >= 0 {
                    pe = gpc;
                } else if st[0] + 3 <= n && srcs[st[0]] == 67 && srcs[st[0] + 1] == 97 && srcs[st[0] + 2] == 112 && kw_end(srcs, st[0] + 3, n) == 1 {
                    // B5-10: `c: Cap[Alloc]` is a static capability token; the
                    // runtime representation is a placeholder Int (8 bytes).
                    if expect_char(srcs, st, 67, n) == 0 { write("cap: expected Cap\n"); return 4; }
                    if expect_char(srcs, st, 97, n) == 0 { write("cap: expected Cap\n"); return 4; }
                    if expect_char(srcs, st, 112, n) == 0 { write("cap: expected Cap\n"); return 4; }
                    skip(srcs, st, n);
                    if expect_char(srcs, st, 91, n) == 0 { write("cap: expected [\n"); return 4; }
                    skip(srcs, st, n);
                    let cstart = st[0];
                    let cnm = name_id(srcs, st, ps);
                    if st[5] == 0 { write("cap: bad capability name\n"); return 4; }
                    let cbit = eff_bit(srcs, cstart, st[0] - cstart);
                    if cbit <= 0 { write("cap: unknown capability\n"); return 4; }
                    if expect_char(srcs, st, 93, n) == 0 { write("cap: expected ]\n"); return 4; }
                    ps[131830 + ctxi[NF]] = ps[131830 + ctxi[NF]] | cbit;
                    pe = 0;
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
                } else if st[0] + 4 < n && srcs[st[0]] == 83 && srcs[st[0] + 1] == 108 && srcs[st[0] + 2] == 105 && srcs[st[0] + 3] == 99 && srcs[st[0] + 4] == 101 {
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
                    if vmode != 2 {
                        write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
                        return 4;
                    }
                    if expect_char(srcs, st, 66, n) == 0 { write("names: expected Buffer\n"); return 4; }
                    if expect_char(srcs, st, 117, n) == 0 { write("names: expected Buffer\n"); return 4; }
                    if expect_char(srcs, st, 102, n) == 0 { write("names: expected Buffer\n"); return 4; }
                    if expect_char(srcs, st, 102, n) == 0 { write("names: expected Buffer\n"); return 4; }
                    if expect_char(srcs, st, 101, n) == 0 { write("names: expected Buffer\n"); return 4; }
                    if expect_char(srcs, st, 114, n) == 0 { write("names: expected Buffer\n"); return 4; }
                    if expect_char(srcs, st, 91, n) == 0 { write("names: expected [\n"); return 4; }
                    if expect_char(srcs, st, 73, n) == 0 { write("names: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 110, n) == 0 { write("names: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 116, n) == 0 { write("names: expected Int\n"); return 4; }
                    if expect_char(srcs, st, 93, n) == 0 { write("names: expected ]\n"); return 4; }
                    pe = 9;
                } else {
                    // R2.6-A: a user struct name.  A generic struct template
                    // (`struct S[A, B]`, tmpl nparams bit 7) resolves to its
                    // instance type `120+ii`; otherwise this is a B7 plain
                    // struct and the method-receiver type is `30+si`.
                    let psave = st[0];
                    let pn2 = name_id(srcs, st, ps);
                    let ptm = tmpl_find(ps, pn2);
                    let is_sgen = 0;
                    if ptm >= 0 {
                        if (ps[123001 + ptm * 12 + 1] & 128) != 0 { is_sgen = 1; }
                    }
                    if is_sgen == 1 {
                        // `S[Int, Str]` instance: parse the two type args and
                        // instantiate (reuse the typed-let R2.2 parsing shape).
                        skip(srcs, st, n);
                        if st[0] >= n || srcs[st[0]] != 91 { st[0] = psave; write("names: expected [ for generic struct\n"); return 4; }
                        st[0] = st[0] + 1;
                        let git1 = parse_ty(srcs, st, ps);
                        if st[3] != 0 || git1 == 0 { st[0] = psave; st[3] = 1; write("names: bad generic struct type\n"); return 4; }
                        let git2 = 0;
                        skip(srcs, st, n);
                        if st[0] < n && srcs[st[0]] == 44 {
                            st[0] = st[0] + 1;
                            git2 = parse_ty(srcs, st, ps);
                            if st[3] != 0 || git2 == 0 { st[0] = psave; st[3] = 1; write("names: bad generic struct type\n"); return 4; }
                        }
                        if expect_char(srcs, st, 93, n) == 0 { st[0] = psave; st[3] = 1; write("names: expected ] for generic struct\n"); return 4; }
                        let iix = mk_inst(ps, ptm, git1, git2);
                        if iix < 0 { st[0] = psave; st[3] = 1; write("names: bad generic struct instance\n"); return 4; }
                        pe = 120 + iix;
                    } else {
                        let psi2 = 0 - 1;
                        if st[5] != 0 { psi2 = st_find(ps, pn2); }
                        if psi2 < 0 {
                            st[0] = psave;
                            write("names: unsupported param type\n"); return 4;
                        }
                        pe = 30 + psi2;
                    }
                }
                if vmode == 2 {
                    if is_gen == 1 {
                        write("stage1: E-LS-UNSUPPORTED: ref parameters in generic functions are not implemented in B-LS yet\n");
                        return 4;
                    }
                    if (pe >= 30 && pe < 100) || pe >= 120 {
                        // B7: struct ref parameters copy the caller's bytes in.
                        // R2.6-A: a generic struct instance (120+ii) is treated
                        // the same way - every field is an 8-byte boxed slot, so
                        // the instance size is inst_nvariants*8 (always aligned).
                        let ssz2 = 0;
                        if pe >= 120 { ssz2 = inst_nvariants(ps, pe - 120) * 8; }
                        else { ssz2 = st_size(ps, pe - 30); }
                        if ssz2 == 0 || (ssz2 & 7) != 0 {
                            write("stage1: E-LS-UNSUPPORTED: struct ref parameters need an 8-byte-aligned layout\n");
                            return 4;
                        }
                    } else if pe != 0 && pe != 2 && pe != 1 && pe != 8 && pe != 9 {
                        write("stage1: E-LS-UNSUPPORTED: ref parameters are only implemented for Int/Str/Slice/Buffer/structs in B-LS yet\n");
                        return 4;
                    }
                }
                if ((pe >= 30 && pe < 100) || pe >= 120) && vmode != 2 {
                    // R2.6-A: a generic struct instance (120+ii) may also be
                    // passed by-value (non-ref); it uses the same byte-copy
                    // ABI in the callee prologue.
                    // R2.6-F: a plain B7 struct (30..99) may now be passed by
                    // value too; the prologue copies the caller's bytes into
                    // this frame, so the layout must be 8-byte aligned.
                    let ssz2b = 0;
                    if pe >= 120 { ssz2b = inst_nvariants(ps, pe - 120) * 8; }
                    else { ssz2b = st_size(ps, pe - 30); }
                    if ssz2b == 0 || (ssz2b & 7) != 0 {
                        write("stage1: E-LS-UNSUPPORTED: struct value parameters need an 8-byte-aligned layout\n");
                        return 4;
                    }
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
            let frefret = 0;
            if st[0] + 3 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 {
                frefret = parse_ref_ty(srcs, st, n);
                if frefret == 0 { write("slice: bad ref return type\n"); return 4; }
            } else if st[0] + 6 <= n && srcs[st[0]] == 66 && srcs[st[0] + 1] == 117 && srcs[st[0] + 2] == 102 && srcs[st[0] + 3] == 102 && srcs[st[0] + 4] == 101 && srcs[st[0] + 5] == 114 && kw_end(srcs, st[0] + 6, n) == 1 {
                write("stage1: E-LS-UNSUPPORTED: Buffer[T] type is not implemented in B-LS yet\n");
                return 4;
            }
            let rgpc = gen_peek(srcs, st, ps);
            if frefret != 0 {
            } else if rgpc >= 0 {
                fret_t = 1;
                fdesc = rgpc;
                fgen = 1;
            } else if st[0] < n && srcs[st[0]] == 79 {
                if expect_char(srcs, st, 79, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 112, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 105, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 111, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("slice: expected Option\n"); return 4; }
                if expect_char(srcs, st, 91, n) == 0 { write("slice: expected [\n"); return 4; }
                ft1 = parse_ty(srcs, st, ps);
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
                ft1 = parse_ty(srcs, st, ps);
                if st[3] != 0 || ft1 == 0 { write("slice: bad Result type\n"); return 4; }
                if expect_char(srcs, st, 44, n) == 0 { write("slice: expected ,\n"); return 4; }
                ft2 = parse_ty(srcs, st, ps);
                if st[3] != 0 || ft2 == 0 { write("slice: bad Result type\n"); return 4; }
                if expect_char(srcs, st, 93, n) == 0 { write("slice: expected ]\n"); return 4; }
                fretv = 2;
            } else if st[0] < n && srcs[st[0]] != 73 {
                // R2.6-A: a generic struct template return `S[Int, Str]`
                // resolves to its instance type 120+ii.  Probe the name before
                // falling back to the generic-enum description (parse_user_desc
                // deliberately rejects struct templates at its bit-7 test).
                let rsave = st[0];
                let rnm = name_id(srcs, st, ps);
                let rtm = tmpl_find(ps, rnm);
                let rsg = 0;
                if rtm >= 0 {
                    if (ps[123001 + rtm * 12 + 1] & 128) != 0 { rsg = 1; }
                }
                if rsg == 1 {
                    skip(srcs, st, n);
                    if st[0] >= n || srcs[st[0]] != 91 { st[0] = rsave; write("slice: expected [ for generic struct return\n"); return 4; }
                    st[0] = st[0] + 1;
                    let r1 = parse_ty(srcs, st, ps);
                    if st[3] != 0 || r1 == 0 { st[0] = rsave; st[3] = 1; write("slice: bad generic struct return type\n"); return 4; }
                    let r2 = 0;
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 44 {
                        st[0] = st[0] + 1;
                        r2 = parse_ty(srcs, st, ps);
                        if st[3] != 0 || r2 == 0 { st[0] = rsave; st[3] = 1; write("slice: bad generic struct return type\n"); return 4; }
                    }
                    if expect_char(srcs, st, 93, n) == 0 { st[0] = rsave; st[3] = 1; write("slice: expected ] for generic struct return\n"); return 4; }
                    let rii = mk_inst(ps, rtm, r1, r2);
                    if rii < 0 { st[0] = rsave; st[3] = 1; write("slice: bad generic struct return instance\n"); return 4; }
                    fdesc = 120 + rii;
                    fgen = 1;
                } else {
                    let rpsi = 0 - 1;
                    if st[5] != 0 { rpsi = st_find(ps, rnm); }
                    if rpsi >= 0 {
                        // R2.6-F: plain B7 struct by-value return (`-> Point`).
                        // The callee leaves the address of its copy in rax; the
                        // caller's `let r = f()` copies the fields out.
                        if is_gen == 1 {
                            write("stage1: E-LS-UNSUPPORTED: generic function return type must be a parameter or a scalar/Slice type\n");
                            return 4;
                        }
                        let rssz = st_size(ps, rpsi);
                        if rssz == 0 || (rssz & 7) != 0 {
                            write("stage1: E-LS-UNSUPPORTED: struct value returns need an 8-byte-aligned layout\n");
                            return 4;
                        }
                        fdesc = 30 + rpsi;
                        fgen = 1;
                    } else {
                        st[0] = rsave;
                        fdesc = parse_user_desc(srcs, st, ps);
                        if fdesc <= 0 { write("slice: bad generic return type\n"); return 4; }
                        fgen = 1;
                    }
                }
            } else {
                if expect_char(srcs, st, 73, n) == 0 { write("slice: expected Int\n"); return 4; }
                if expect_char(srcs, st, 110, n) == 0 { write("slice: expected Int\n"); return 4; }
                if expect_char(srcs, st, 116, n) == 0 { write("slice: expected Int\n"); return 4; }
            }
            fret[ctxi[NF]] = fretv;
            fret_t1[ctxi[NF]] = ft1;
            fret_t2[ctxi[NF]] = ft2;
            if frefret != 0 { fret_ty[ctxi[NF]] = frefret; }
            else if fgen == 1 { fret_ty[ctxi[NF]] = fdesc; }
            else if fretv == 1 { fret_ty[ctxi[NF]] = mk_opt_ty(ft1); }
            else if fretv == 2 { fret_ty[ctxi[NF]] = mk_res_ty(ft1, ft2); }
            else { fret_ty[ctxi[NF]] = 1; }
            if is_gen == 1 { ps[120000 + fnm] = 1073741824 | (fret_t << 29) | fret_ty[ctxi[NF]]; }
            else { ps[120000 + fnm] = fret_ty[ctxi[NF]]; }
            skip(srcs, st, n);
            // B4: optional `where A: Bound, ...` clause (bounds are recorded by scan_sigs).
            if st[0] + 5 <= n && srcs[st[0]] == 119 && srcs[st[0] + 1] == 104 && srcs[st[0] + 2] == 101 && srcs[st[0] + 3] == 114 && srcs[st[0] + 4] == 101 && kw_end(srcs, st[0] + 5, n) == 1 {
                st[0] = st[0] + 5;
                while 1 {
                    skip(srcs, st, n);
                    if st[0] >= n || srcs[st[0]] == 123 { break; }
                    if st[0] + 3 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 102 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 { break; }
                    if st[0] + 8 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 113 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 105 && srcs[st[0] + 5] == 114 && srcs[st[0] + 6] == 101 && srcs[st[0] + 7] == 115 && kw_end(srcs, st[0] + 8, n) == 1 { break; }
                    if st[0] + 7 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 110 && srcs[st[0] + 2] == 115 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 114 && srcs[st[0] + 5] == 101 && srcs[st[0] + 6] == 115 && kw_end(srcs, st[0] + 7, n) == 1 { break; }
                    let gn = name_id(srcs, st, ps);
                    if st[5] == 0 { write("generic: bad where clause\n"); return 4; }
                    if expect_char(srcs, st, 58, n) == 0 { write("generic: expected :\n"); return 4; }
                    skip(srcs, st, n);
                    let bn = name_id(srcs, st, ps);
                    if st[5] == 0 { write("generic: bad where bound\n"); return 4; }
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                    else { break; }
                }
                skip(srcs, st, n);
            }
            if st[0] + 3 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 102 && srcs[st[0] + 2] == 102 && kw_end(srcs, st[0] + 3, n) == 1 {
                // B5-10: `eff(read, write, alloc, ...)`; `eff(pure)` is the empty set.
                // Bit 30 marks "has an effect clause".
                if expect_char(srcs, st, 101, n) == 0 { write("eff: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 102, n) == 0 { write("eff: bad keyword\n"); return 4; }
                if expect_char(srcs, st, 102, n) == 0 { write("eff: bad keyword\n"); return 4; }
                skip(srcs, st, n);
                if expect_char(srcs, st, 40, n) == 0 { write("eff: expected (\n"); return 4; }
                let em = 1073741824;
                while 1 {
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                    let estart = st[0];
                    let enm = name_id(srcs, st, ps);
                    if st[5] == 0 { write("eff: bad effect name\n"); return 4; }
                    let ebit = eff_bit(srcs, estart, st[0] - estart);
                    if ebit < 0 { write("eff: unknown effect\n"); return 4; }
                    if ebit == 128 { em = 1073741824; }
                    else { em = em | ebit; }
                    skip(srcs, st, n);
                    if st[0] < n && srcs[st[0]] == 44 { st[0] = st[0] + 1; }
                    else if st[0] < n && srcs[st[0]] == 41 { st[0] = st[0] + 1; break; }
                    else { write("eff: expected )\n"); return 4; }
                }
                ps[131700 + ctxi[NF]] = em;
            }
            if st[0] + 8 <= n && srcs[st[0]] == 114 && srcs[st[0] + 1] == 101 && srcs[st[0] + 2] == 113 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 105 && srcs[st[0] + 5] == 114 && srcs[st[0] + 6] == 101 && srcs[st[0] + 7] == 115 && kw_end(srcs, st[0] + 8, n) == 1 {
                // B5-11: `requires <expr>` - asserted at function entry (exit 73).
                st[0] = st[0] + 8;
                skip(srcs, st, n);
                let rcstart = st[0];
                let rcend = rcstart;
                let rquote = 0;
                while rcend < n {
                    if rquote == 1 {
                        if srcs[rcend] == 92 { rcend = rcend + 1; }
                        else if srcs[rcend] == 34 { rquote = 0; }
                        rcend = rcend + 1;
                    } else if srcs[rcend] == 34 { rquote = 1; rcend = rcend + 1; }
                    else if srcs[rcend] == 123 { break; }
                    else if is_ident_byte(srcs[rcend]) == 0 { rcend = rcend + 1; }
                    else if rcend + 7 <= n && srcs[rcend] == 101 && srcs[rcend + 1] == 110 && srcs[rcend + 2] == 115 && srcs[rcend + 3] == 117 && srcs[rcend + 4] == 114 && srcs[rcend + 5] == 101 && srcs[rcend + 6] == 115 { break; }
                    else if rcend + 3 <= n && srcs[rcend] == 101 && srcs[rcend + 1] == 102 && srcs[rcend + 2] == 102 { break; }
                    else if rcend + 5 <= n && srcs[rcend] == 119 && srcs[rcend + 1] == 104 && srcs[rcend + 2] == 101 && srcs[rcend + 3] == 114 && srcs[rcend + 4] == 101 { break; }
                    else { rcend = rcend + 1; }
                }
                ps[135741] = rcstart;
                ps[135742] = rcend;
                st[0] = rcend;
            }
            if st[0] + 7 <= n && srcs[st[0]] == 101 && srcs[st[0] + 1] == 110 && srcs[st[0] + 2] == 115 && srcs[st[0] + 3] == 117 && srcs[st[0] + 4] == 114 && srcs[st[0] + 5] == 101 && srcs[st[0] + 6] == 115 && kw_end(srcs, st[0] + 7, n) == 1 {
                // B5-11: `ensures <expr>` - asserted before every return (exit 74);
                // `result` is the return value.
                st[0] = st[0] + 7;
                skip(srcs, st, n);
                let ecstart = st[0];
                let ecend = ecstart;
                let equote = 0;
                while ecend < n {
                    if equote == 1 {
                        if srcs[ecend] == 92 { ecend = ecend + 1; }
                        else if srcs[ecend] == 34 { equote = 0; }
                        ecend = ecend + 1;
                    } else if srcs[ecend] == 34 { equote = 1; ecend = ecend + 1; }
                    else if srcs[ecend] == 123 { break; }
                    else if is_ident_byte(srcs[ecend]) == 0 { ecend = ecend + 1; }
                    else if ecend + 3 <= n && srcs[ecend] == 101 && srcs[ecend + 1] == 102 && srcs[ecend + 2] == 102 { break; }
                    else if ecend + 8 <= n && srcs[ecend] == 114 && srcs[ecend + 1] == 101 && srcs[ecend + 2] == 113 && srcs[ecend + 3] == 117 && srcs[ecend + 4] == 105 && srcs[ecend + 5] == 114 && srcs[ecend + 6] == 101 && srcs[ecend + 7] == 115 { break; }
                    else if ecend + 5 <= n && srcs[ecend] == 119 && srcs[ecend + 1] == 104 && srcs[ecend + 2] == 101 && srcs[ecend + 3] == 114 && srcs[ecend + 4] == 101 { break; }
                    else { ecend = ecend + 1; }
                }
                ps[135743] = ecstart;
                ps[135744] = ecend;
                st[0] = ecend;
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
                if fval[i] == 2 || pe == 0 || pe >= 100 || (pe >= 30 && pe < 100) {
                    let vi0 = var_find_any(ps, pid, ctxi[NF]);
                    let off = 0;
                    if vi0 >= 0 { off = ps[50003 + vi0 * 4]; }
                    else {
                        off = ctxi[DLEN];
                        ctxi[DLEN] = ctxi[DLEN] + 8;
                    }
                    let vi = var_add(ps, pid, ctxi[NF], off, var_span(0, n, fval[i]));
                    if fval[i] == 2 || (pe >= 30 && pe < 100) || pe >= 120 {
                        if pe >= 30 {
                            // B7: struct ref parameter - copy the caller's bytes
                            // into this frame, then register the receiver as an
                            // sv struct variable so `a.x` fields resolve normally.
                            // R2.6-A: a generic struct instance (120+ii) uses the
                            // instance field count for its size and sv sidx
                            // (70+ii, matching the typed-let instantiation); it
                            // may also be passed by-value (fval==0), same ABI.
                            let ssz3 = 0;
                            let svix = 0;
                            if pe >= 120 {
                                ssz3 = inst_nvariants(ps, pe - 120) * 8;
                                svix = 70 + (pe - 120);
                            } else {
                                ssz3 = st_size(ps, pe - 30);
                                svix = pe - 30;
                            }
                            ctxi[DLEN] = off + ssz3;
                            sv_add(ps, pid, ctxi[NF], off | (n << 31), svix);
                            let w3 = 0;
                            while w3 < ssz3 / 8 {
                                if reg < 4 {
                                    if reg == 0 { emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 71); }
                                    else if reg == 1 { emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 70); }
                                    else if reg == 2 { emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 66); }
                                    else { emit1(c, cs, 72); emit1(c, cs, 139); emit1(c, cs, 65); }
                                    emit1(c, cs, w3 * 8);
                                } else {
                                    write("stage1: E-LS-UNSUPPORTED: struct parameters must sit in the first four argument slots
");
                                    return 4;
                                }
                                emit1(c, cs, 72); emit1(c, cs, 137); emit1(c, cs, 5);
                                ps[cs[3] + cs[2] * 2] = cs[0];
                                ps[cs[3] + cs[2] * 2 + 1] = off + w3 * 8;
                                cs[2] = cs[2] + 1;
                                emit4(c, cs, 0);
                                w3 = w3 + 1;
                            }
                        } else {
                            let rt = 11;
                            if pe == 2 { rt = 12; }
                            else if pe == 1 { rt = 13; }
                            else if pe == 8 { rt = 14; }
                            else if pe == 9 { rt = 15; }
                            var_set_ty(ps, vi, rt);
                            // B5-8: a `ref` parameter is a reborrow from the caller,
                            // so it may outlive this function (origin 0).
                            if vi < 4000 { ps[136000 + vi] = n << 1; }
                        }
                    }
                    else if pe >= 100 { var_set_ty(ps, vi, pe); }
                    else { var_set_ty(ps, vi, 1); }
                    // R2.6-A fix: only by-value generic structs (pe>=120) skip
                    // the single-register store (their copy prologue already
                    // ran).  Ref scalars (fval==2, pe<30) MUST still store the
                    // incoming register: the A1 condition dropped that store
                    // and segfaulted every `ref Int` callee.
                    if pe < 30 || (pe >= 100 && pe < 120) {
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
                    }
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

            // B5-11: reserve the `result` slot and assert `requires` at entry.
            if ps[135743] != ps[135744] {
                ps[135746] = ctxi[DLEN];
                ctxi[DLEN] = ctxi[DLEN] + 8;
            }
            if ps[135741] != ps[135742] {
                let rsave0 = st[0];
                st[0] = ps[135741]; st[1] = ps[135742]; st[2] = 0; st[3] = 0; st[12] = ctxi[DLEN];
                parse_expr(srcs, st, ps);
                ctxi[DLEN] = st[12];
                if st[3] != 0 { write("requires: bad expression\n"); return 4; }
                cs[1] = st[2];
                emit_expr(c, cs, ps);
                emit1(c, cs, 72); emit1(c, cs, 133); emit1(c, cs, 192); // test eax,eax
                emit1(c, cs, 15); emit1(c, cs, 133);
                let rqj = cs[0]; emit4(c, cs, 0);
                emit1(c, cs, 184); emit4(c, cs, 60);
                emit1(c, cs, 191); emit4(c, cs, 73);
                emit1(c, cs, 15); emit1(c, cs, 5);
                patch_jump(c, rqj, cs[0]);
                st[0] = rsave0;
                st[1] = n;
            }

            ctxi[HAVE_RET] = 0;
            ps[131960] = 0;
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
            // B5-10: declared effects must cover the body; alloc/unsafe need a Cap token.
            let dcl = ps[131700 + ctxi[NF]];
            if dcl != 0 && ps[135700] == 0 {
                // Boundary effects (alloc/panic/spawn/unsafe = 4|16|32|64 = 116)
                // must be declared; read/write/io are internal and inferred.
                let miss = ps[131960] & 116 & (116 - (dcl & 116));
                if miss != 0 {
                    write("stage1: E-LS-EFFECT: ");
                    diag_pos(srcs, body_after - 1, 0);
                    write("function body has an effect not declared in its eff(...) clause\n");
                    write("  fix-it: declare ");
                    if (miss & 4) != 0 { write("alloc "); }
                    if (miss & 16) != 0 { write("panic "); }
                    if (miss & 32) != 0 { write("spawn "); }
                    if (miss & 64) != 0 { write("unsafe "); }
                    write("in the eff(...) clause\n");
                    return 4;
                }
                let needcap = dcl & 68;
                let misshave = needcap & (68 - (ps[131830 + ctxi[NF]] & 68));
                if misshave != 0 {
                    write("stage1: E-LS-CAP: ");
                    diag_pos(srcs, body_after - 1, 0);
                    write("eff(...) alloc/io/unsafe needs a matching Cap[...] parameter\n");
                    write("  fix-it: add parameter(s) ");
                    if (misshave & 4) != 0 { write("c: Cap[Alloc] "); }
                    if (misshave & 64) != 0 { write("u: Cap[Unsafe] "); }
                    write("and pass them from callers\n");
                    return 4;
                }
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

