fn emit_expr_a(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let pval = post[cst[9] * 2 + 1];
    let done = 0;
    if kind == 0 {
        emit1(code, cst, 72); emit1(code, cst, 184);
        let k = 0;
        while k < 8 {
            emit1(code, cst, (pval >> (k * 8)) & 255);
            k = k + 1;
        }
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 1 && done == 0 {
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4];
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 89 && done == 0 {
        // B7: address of a struct value (sv) - lea rax,[rip+disp]; push rax.
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = post[6403 + pval * 4] & 2147483647;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if (kind == 10 || kind == 11) && done == 0 {
        let meta = 0;
        if kind == 10 { meta = post[4098 + pval * 3]; }
        else { meta = post[66402 + pval * 2]; }
        let off = meta & 2147483647;
        let elem = (meta >> 31) & 15;
        emit1(code, cst, 89);
        if kind == 10 { emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 21); }
        else { emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 21); }
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = off;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        if elem == 8 || elem >= 11 {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 202);
        } else {
            emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 209);
            emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 1);
        }
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 13 && done == 0 {
        let meta = post[66402 + pval * 2];
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
        post[cst[3] + cst[2] * 2 + 1] = pval;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 18 && done == 0 {
        let meta = post[4098 + pval * 3];
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
        let off = post[15003 + pval * 4];
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
        let off = post[15003 + pval * 4];
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = off + 16;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        done = 1;
    }
    if kind == 23 && done == 0 {
        let off = post[15003 + pval * 4];
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
    let pval = post[cst[9] * 2 + 1];
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
    let pval = post[cst[9] * 2 + 1];
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
    let pval = post[cst[9] * 2 + 1];
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
    let pval = post[cst[9] * 2 + 1];
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

// R4.7: resolve a Buffer handle (in rax) to its current block offset
// (out rax, -1 when the handle is stale/invalid). Clobbers rsi/rdi.
fn emit_hget(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax
    emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
    post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17040]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[ht]
    emit1(code, cst, 255); emit1(code, cst, 21);
    post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17028]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [hget]
    emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
    return 0;
}

fn emit_expr_c(code: Slice[U8], cst: Slice[Int], post: Slice[Int]) -> Int {
    let kind = post[cst[9] * 2];
    let pval = post[cst[9] * 2 + 1];
    if kind == 24 {
        // Option.Some(v) / Result.Ok(v) / Result.Err(v): pack tag | (v << 8).
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 224); emit1(code, cst, 8);
        emit1(code, cst, 72); emit1(code, cst, 13);
        emit4(code, cst, pval & 255);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 27 {
        let meta = post[100000 + cst[9]];
        let tag = meta & 255;
        let ty = (meta >> 8) & 255;
        if ty != 0 {
            let w = ty_width(ty);
            if ty >= 30 { w = st_size(post, ty - 30) / 8; }
            let k = w - 1;
            while k >= 0 {
                emit1(code, cst, 88);
                emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
                post[cst[3] + cst[2] * 2] = cst[0];
                post[cst[3] + cst[2] * 2 + 1] = pval + 8 + k * 8;
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
        post[cst[3] + cst[2] * 2 + 1] = pval;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = pval;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 90 {
        // R2.6-B: generic-struct constructor field store (ctor glue node):
        // pop the field value, store it 8 bytes at [rip+pval].
        emit1(code, cst, 88);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = pval;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        return 0;
    }
    if kind == 91 {
        // R2.6-B: generic-struct constructor result: lea rax,[rip+pval];
        // push rax.  The value is the instance block address (120+ii type),
        // matching the bare-struct (kind 89) ABI for args, returns and
        // the R2.6-A let receiver copy.
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = pval;
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
        // arena_alloc(n): 8-byte aligned allocation; reuses free-list holes first.
        emit1(code, cst, 88); // pop rax (n)
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 7); // add rax,7
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 224); emit1(code, cst, 248); // and rax,-8
        // R4.6: reuse a hole first.
        emit1(code, cst, 80); // push rax (size)
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[table]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17023]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [take]
        emit1(code, cst, 94); // pop rsi (size)
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let areuse = cst[0]; emit4(code, cst, 0); // jl bump
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194); // mov rdx,rax (off)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17019]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[allocs]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17019]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [allocs]=rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 208); // mov rax,rdx
        emit1(code, cst, 80); // push offset
        emit1(code, cst, 233);
        let areusetop = cst[0]; emit4(code, cst, 0);
        patch_jump(code, areuse, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 240); // mov rax,rsi (size)
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
        patch_jump(code, areusetop, cst[0]);
        return 0;
    }
    if kind == 56 {
        // R4.7: Buffer.new allocates the block, then registers it in the handle
        // table; the returned handle is the table slot (stable under compaction).
        emit1(code, cst, 88); // pop rax (cap)
        emit1(code, cst, 80); // push cap for header init
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 224); emit1(code, cst, 3); // shl rax,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 32); // add rax,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 199); // mov rdi,rax
        emit1(code, cst, 232);
        let bcall = cst[0]; emit4(code, cst, 0);
        let bcn = post[266336 + 1399]; post[266336 + 1400 + bcn] = bcall; post[266336 + 1399] = bcn + 1;
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let bnfail = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194); // mov rdx,rax
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 198); emit1(code, cst, 32); // add rsi,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 49); // mov [rcx],rsi
        emit1(code, cst, 72); emit1(code, cst, 190);
        let z = 0; while z < 8 { emit1(code, cst, 0); z = z + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 113); emit1(code, cst, 8); // mov [rcx+8],rsi
        emit1(code, cst, 94); // pop rsi (cap)
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 113); emit1(code, cst, 16); // mov [rcx+16],rsi
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
        // Register in the handle table: rsi=off, rdx=size.
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 214); // mov rsi,rdx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 81); emit1(code, cst, 16); // mov rdx,[rcx+16]
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 226); emit1(code, cst, 3); // shl rdx,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 194); emit1(code, cst, 32); // add rdx,32
        emit1(code, cst, 86); // push rsi (off)
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17040]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[ht]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17027]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [hreg]
        emit1(code, cst, 94); // pop rsi (off)
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let breg = cst[0]; emit4(code, cst, 0); // jl reg-fail
        emit1(code, cst, 233);
        let bdone = cst[0]; emit4(code, cst, 0); // jmp common result
        patch_jump(code, bnfail, cst[0]);
        emit1(code, cst, 94); // pop cap
        emit1(code, cst, 72); emit1(code, cst, 184);
        z = 0; while z < 8 { emit1(code, cst, 255); z = z + 1; }
        emit1(code, cst, 233);
        let bdone2 = cst[0]; emit4(code, cst, 0);
        // Handle table full: return the fresh block to the free list (it may
        // have come from a hole, so it is not necessarily the arena top).
        patch_jump(code, breg, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[free]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17024]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [buf_free]
        emit1(code, cst, 72); emit1(code, cst, 184);
        z = 0; while z < 8 { emit1(code, cst, 255); z = z + 1; }
        patch_jump(code, bdone, cst[0]);
        patch_jump(code, bdone2, cst[0]);
        emit1(code, cst, 80); // push result handle / -1
        return 0;
    }
    if kind == 57 || kind == 58 {
        // buffer_len(handle) / buffer_cap(handle) through the handle table.
        emit1(code, cst, 88); // pop rax (handle)
        emit_hget(code, cst, post);
        emit1(code, cst, 15); emit1(code, cst, 140);
        let hlfail = cst[0]; emit4(code, cst, 0); // jl fail
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); // add rax,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 64);
        if kind == 57 { emit1(code, cst, 8); } else { emit1(code, cst, 16); }
        emit1(code, cst, 80);
        emit1(code, cst, 233);
        let hldone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, hlfail, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let hz = 0; while hz < 8 { emit1(code, cst, 255); hz = hz + 1; }
        emit1(code, cst, 80);
        patch_jump(code, hldone, cst[0]);
        return 0;
    }
    if kind == 59 {
        // buffer_push(handle, value): returns new len or -1 when full.
        emit1(code, cst, 90); // pop rdx (value)
        emit1(code, cst, 88); // pop rax (handle)
        emit_hget(code, cst, post);
        emit1(code, cst, 15); emit1(code, cst, 140);
        let bpfail = cst[0]; emit4(code, cst, 0); // jl fail
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); // add rax,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 112); emit1(code, cst, 8); // mov rsi,[rax+8]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 120); emit1(code, cst, 16); // mov rdi,[rax+16]
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 254); // cmp rsi,rdi
        emit1(code, cst, 15); emit1(code, cst, 131);
        let bpfail2 = cst[0]; emit4(code, cst, 0);
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
        patch_jump(code, bpfail2, cst[0]);
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
        emit_hget(code, cst, post);
        emit1(code, cst, 15); emit1(code, cst, 140);
        let bgfail = cst[0]; emit4(code, cst, 0); // jl fail
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); // add rax,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 120); emit1(code, cst, 8); // mov rdi,[rax+8]
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 250); // cmp rdx,rdi
        emit1(code, cst, 15); emit1(code, cst, 131);
        let bgfail2 = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 56); // mov rdi,[rax]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13); // mov rcx,[base]
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 207); // add rdi,rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 215); // mov rax,[rdi+rdx*8]
        emit1(code, cst, 80);
        emit1(code, cst, 233);
        let bgdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, bgfail, cst[0]);
        patch_jump(code, bgfail2, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let g = 0; while g < 8 { emit1(code, cst, 255); g = g + 1; }
        emit1(code, cst, 80);
        patch_jump(code, bgdone, cst[0]);
        return 0;
    }
    if kind == 61 {
        // B3-3/R4.7: Buffer.try_new -> Result block at `val`; the Ok payload is
        // the handle-table slot (not the block offset).
        emit1(code, cst, 88); // pop rax (cap)
        emit1(code, cst, 80); // push cap (needed for the header init)
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 224); emit1(code, cst, 3); // shl rax,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 32); // add rax,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 199); // mov rdi,rax
        emit1(code, cst, 232);
        let tcall = cst[0]; emit4(code, cst, 0);
        let tcn = post[266336 + 1399]; post[266336 + 1400 + tcn] = tcall; post[266336 + 1399] = tcn + 1;
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let tfail = cst[0]; emit4(code, cst, 0);
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
        // Register the fresh block (rdx=off, rcx=header).
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 214); // mov rsi,rdx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 81); emit1(code, cst, 16); // mov rdx,[rcx+16]
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 226); emit1(code, cst, 3); // shl rdx,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 194); emit1(code, cst, 32); // add rdx,32
        emit1(code, cst, 86); // push rsi (off)
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17040]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[ht]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17027]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [hreg]
        emit1(code, cst, 94); // pop rsi (off)
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let treg = cst[0]; emit4(code, cst, 0); // jl reg-fail
        // Ok: tag 0, payload = handle (rdx).
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194); // mov rdx,rax
        emit1(code, cst, 72); emit1(code, cst, 184);
        zz = 0; while zz < 8 { emit1(code, cst, 0); zz = zz + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 0
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=handle
        emit1(code, cst, 233);
        let tdone = cst[0]; emit4(code, cst, 0);
        // Allocation failed: drop cap, then write Err(-1).
        patch_jump(code, tfail, cst[0]);
        emit1(code, cst, 94); // pop cap
        emit1(code, cst, 233);
        let terr = cst[0]; emit4(code, cst, 0);
        // Handle table full: return the fresh block to the free list (it may
        // have come from a hole), then write Err(-1).
        patch_jump(code, treg, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[free]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17024]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [buf_free]
        patch_jump(code, terr, cst[0]);
        // Err block: tag 1, payload -1.
        emit1(code, cst, 72); emit1(code, cst, 184);
        emit1(code, cst, 1);
        zz = 0; while zz < 7 { emit1(code, cst, 0); zz = zz + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 1
        emit1(code, cst, 72); emit1(code, cst, 184);
        zz = 0; while zz < 8 { emit1(code, cst, 255); zz = zz + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=-1
        patch_jump(code, tdone, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rax,[blk]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 62 {
        // buffer_release(handle): owner check, then top rewind or free list;
        // the handle slot is invalidated only when the release succeeds.
        emit1(code, cst, 88); // pop rax (handle)
        emit1(code, cst, 80); // push handle (kept until success)
        emit_hget(code, cst, post);
        emit1(code, cst, 15); emit1(code, cst, 140);
        let rfail0 = cst[0]; emit4(code, cst, 0); // jl fail
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
        let rfreepath = cst[0]; emit4(code, cst, 0);
        // Top: rewind current to the block.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov [current],rcx
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[reclaims]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [reclaims]=rax
        emit1(code, cst, 233);
        let rsuccess = cst[0]; emit4(code, cst, 0);
        // Non-top: free list (arbitrary order).
        patch_jump(code, rfreepath, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 193); // add rcx,rax (header)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 81); emit1(code, cst, 16); // mov rdx,[rcx+16] (cap)
        emit1(code, cst, 72); emit1(code, cst, 193); emit1(code, cst, 226); emit1(code, cst, 3); // shl rdx,3
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 194); emit1(code, cst, 32); // add rdx,32
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax (off)
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[table]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17024]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [free]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let rfails = cst[0]; emit4(code, cst, 0); // jl fail
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[reclaims]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [reclaims]=rax
        patch_jump(code, rsuccess, cst[0]);
        // Success: invalidate the handle slot.
        emit1(code, cst, 94); // pop rsi (handle)
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17040]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[ht]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17029]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [hfree]
        emit1(code, cst, 72); emit1(code, cst, 184);
        let rz = 0; while rz < 8 { emit1(code, cst, 0); rz = rz + 1; }
        emit1(code, cst, 233);
        let rdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, rfail0, cst[0]);
        patch_jump(code, rowner, cst[0]);
        patch_jump(code, rfails, cst[0]);
        emit1(code, cst, 94); // pop handle (failure keeps the slot alive)
        emit1(code, cst, 72); emit1(code, cst, 184);
        let rf = 0; while rf < 8 { emit1(code, cst, 255); rf = rf + 1; }
        patch_jump(code, rdone, cst[0]);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 63 {
        // buffer_set(handle, index, value): 0 on success, -1 when index >= len.
        emit1(code, cst, 90); // pop rdx (value)
        emit1(code, cst, 89); // pop rcx (index)
        emit1(code, cst, 88); // pop rax (handle)
        emit1(code, cst, 81); // push rcx (index; hget clobbers rcx)
        emit_hget(code, cst, post);
        emit1(code, cst, 15); emit1(code, cst, 140);
        let bsfail = cst[0]; emit4(code, cst, 0); // jl fail
        emit1(code, cst, 89); // pop rcx (index)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rsi,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 240); // add rax,rsi (header)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 120); emit1(code, cst, 8); // mov rdi,[rax+8] (len)
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 249); // cmp rcx,rdi
        emit1(code, cst, 15); emit1(code, cst, 131);
        let bsfail2 = cst[0]; emit4(code, cst, 0); // jae fail
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 56); // mov rdi,[rax] (data_off)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rsi,[base]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 247); // add rdi,rsi
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 20); emit1(code, cst, 207); // mov [rdi+rcx*8],rdx
        emit1(code, cst, 72); emit1(code, cst, 184);
        let sz = 0; while sz < 8 { emit1(code, cst, 0); sz = sz + 1; }
        emit1(code, cst, 233);
        let bsdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, bsfail2, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let sf = 0; while sf < 8 { emit1(code, cst, 255); sf = sf + 1; }
        emit1(code, cst, 233);
        let sfdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, bsfail, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 196); emit1(code, cst, 8); // add rsp,8
        emit1(code, cst, 72); emit1(code, cst, 184);
        sf = 0; while sf < 8 { emit1(code, cst, 255); sf = sf + 1; }
        patch_jump(code, bsdone, cst[0]);
        patch_jump(code, sfdone, cst[0]);
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
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rcx,[val]
        emit1(code, cst, 76); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea r8,[current]
        emit1(code, cst, 76); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17012]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea r9,[end]
        emit1(code, cst, 232);
        let scall = cst[0]; emit4(code, cst, cst[15] - (scall + 4));
        emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov eax,[val] (tag)
        emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 3); // cmp eax,3
        emit1(code, cst, 15); emit1(code, cst, 133);
        let serr = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 191);
        let so = 0; while so < 8 { emit1(code, cst, 0); so = so + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 32; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 0
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 8; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[strbox+8]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 40; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=ptr
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 16; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[strbox+16]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 48; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+16]=bytes
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 24; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[strbox+24]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 56; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+24]=chars
        emit1(code, cst, 233);
        let sdone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, serr, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 191);
        emit1(code, cst, 1);
        let se = 0; while se < 7 { emit1(code, cst, 0); se = se + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 32; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk]=tag 1
        emit1(code, cst, 72); emit1(code, cst, 191);
        let sf = 0; while sf < 8 { emit1(code, cst, 255); sf = sf + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 40; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [blk+8]=-1
        patch_jump(code, sdone, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval + 32; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rax,[blk]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 65 {
        // R4.2: arena_stat(sel) reads high_water/allocs/rejects/reclaims.
        let aslot = post[17018 + pval];
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
        // R4.6: purge free-list holes above the new top.
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[table]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17025]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [purge]
        // R4.7: invalidate Buffer handles above the new top.
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17040]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[ht]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rsi,[current]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[base]
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 198); // sub rsi,rax
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17031]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [hpurge]
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
    if kind == 87 {
        // B5-11: `result` inside an ensures clause (load the saved return value).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 69 {
        // R4.5: Result/Option variable load (block pointer; feeds `?`).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = pval; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 70 {
        // R4.6: arena_free(off, size): insert into the free list; 0 or -1.
        emit1(code, cst, 90); // pop rdx (size)
        emit1(code, cst, 88); // pop rax (off)
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 198); // mov rsi,rax
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[table]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17024]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [free]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 140);
        let afail = cst[0]; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[reclaims]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 192); emit1(code, cst, 1); // add rax,1
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [reclaims]=rax
        emit1(code, cst, 72); emit1(code, cst, 184);
        let az = 0; while az < 8 { emit1(code, cst, 0); az = az + 1; }
        emit1(code, cst, 233);
        let adone = cst[0]; emit4(code, cst, 0);
        patch_jump(code, afail, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 184);
        let af = 0; while af < 8 { emit1(code, cst, 255); af = af + 1; }
        patch_jump(code, adone, cst[0]);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 71 {
        // R4.6: arena_coalesce(): merge adjacent free holes (no live moves).
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[table]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17026]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [compact]
        emit1(code, cst, 72); emit1(code, cst, 184);
        let cz = 0; while cz < 8 { emit1(code, cst, 0); cz = cz + 1; }
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 72 {
        // R4.7: region_limit() = effective end - innermost region mark (root: end-base).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17013]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[depth]
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 248); emit1(code, cst, 0); // cmp rax,0
        emit1(code, cst, 15); emit1(code, cst, 132);
        let rlg = cst[0]; emit4(code, cst, 0); // je root
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 232); emit1(code, cst, 1); // sub rax,1
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17015]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rcx,[mark]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 193); // mov rax,[rcx+rax*8]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17012]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[end]
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 193); // sub rcx,rax
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 200); // mov rax,rcx
        emit1(code, cst, 233);
        let rld = cst[0]; emit4(code, cst, 0);
        patch_jump(code, rlg, cst[0]);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17012]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[end]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rcx,[base]
        emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200); // sub rax,rcx
        patch_jump(code, rld, cst[0]);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 73 {
        // R4.7: arena_compact() -> moved block count; reclaims += moved.
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 61);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdi,[free]
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 53);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17040]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rsi,[ht]
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rdx,[base]
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 13);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rcx,[current]
        emit1(code, cst, 255); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17030]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // call [hcompact]
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 194); // mov rdx,rax
        emit1(code, cst, 72); emit1(code, cst, 131); emit1(code, cst, 250); emit1(code, cst, 0); // cmp rdx,0
        emit1(code, cst, 15); emit1(code, cst, 142);
        let acz = cst[0]; emit4(code, cst, 0); // jle done
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[reclaims]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 208); // add rax,rdx
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17021]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // [reclaims]=rax
        patch_jump(code, acz, cst[0]);
        emit1(code, cst, 82); // push moved count
        return 0;
    }
    if kind == 75 {
        // B5: load a ref variable's pointer (forward to another ref parameter).
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[slot]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 77 {
        // B5: ref Str value: load the pointer, then push base/byte_len/char_len.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[slot]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 16); // mov rdx,[rax]
        emit1(code, cst, 82);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 80); emit1(code, cst, 8); // mov rdx,[rax+8]
        emit1(code, cst, 82);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 80); emit1(code, cst, 16); // mov rdx,[rax+16]
        emit1(code, cst, 82);
        return 0;
    }
    if kind == 78 {
        // B5: ref Slice value: load the pointer, then push base/len.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[slot]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 16); // mov rdx,[rax]
        emit1(code, cst, 82);
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 80); emit1(code, cst, 8); // mov rdx,[rax+8]
        emit1(code, cst, 82);
        return 0;
    }
    if kind == 79 || kind == 80 {
        // B5: ref Str/Slice .len.
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rax,[slot]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 64);
        if kind == 79 { emit1(code, cst, 16); } else { emit1(code, cst, 8); }
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 81 {
        // B5: address of a Str slot (ref argument).
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[15003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 82 {
        // B5: address of a Slice slot (ref argument).
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[66402 + pval * 2] & 2147483647; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 86 {
        // B5-7: address of an Int Array element.
        emit1(code, cst, 89); // pop rcx (index)
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[4098 + pval * 3] & 2147483647; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rax,[array]
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 4); emit1(code, cst, 200); // lea rax,[rax+rcx*8]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 85 {
        // B5-4: index a Ref Str (byte view).
        emit1(code, cst, 89); // pop rcx (index)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rdx,[slot]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 18); // mov rdx,[rdx]
        emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 209); // add rcx,rdx
        emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 1); // movzx eax,byte [rcx]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 83 || kind == 84 {
        // B5-3: index a Ref Slice (base/len are read through the pointer).
        emit1(code, cst, 89); // pop rcx (index)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 21);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // mov rdx,[slot]
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 18); // mov rdx,[rdx]
        if kind == 84 {
            emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 4); emit1(code, cst, 202); // mov rax,[rdx+rcx*8]
        } else {
            emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 209); // add rcx,rdx
            emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 1); // movzx eax,byte [rcx]
        }
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 74 {
        // B5-1: address of an Int variable slot (ref argument).
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[50003 + pval * 4]; cst[2] = cst[2] + 1; emit4(code, cst, 0); // lea rax,[slot]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 76 {
        // B5-1: dereference a ref Int variable slot.
        emit1(code, cst, 88); // pop rax (pointer)
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 0); // mov rax,[rax]
        emit1(code, cst, 80);
        return 0;
    }
    if kind == 32 {
        emit1(code, cst, 72); emit1(code, cst, 139); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17010]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17011]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        // R4.6: reset clears the free list (count = 0).
        emit1(code, cst, 72); emit1(code, cst, 199); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17022]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit4(code, cst, 0);
        // R4.7: reset also drops every Buffer handle slot.
        emit1(code, cst, 72); emit1(code, cst, 199); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0]; post[cst[3] + cst[2] * 2 + 1] = post[17040]; cst[2] = cst[2] + 1; emit4(code, cst, 0);
        emit4(code, cst, 0);
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
            post[cst[3] + cst[2] * 2 + 1] = pval;
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
            post[cst[3] + cst[2] * 2 + 1] = pval;
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
            post[cst[3] + cst[2] * 2 + 1] = pval + 8 + k * 8;
            cst[2] = cst[2] + 1;
            emit4(code, cst, 0);
            k = k - 1;
        }
        emit1(code, cst, 72); emit1(code, cst, 184);
        let b = 0;
        while b < 8 { emit1(code, cst, (aty >> (b * 8)) & 255); b = b + 1; }
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = pval;
        cst[2] = cst[2] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 72); emit1(code, cst, 141); emit1(code, cst, 5);
        post[cst[3] + cst[2] * 2] = cst[0];
        post[cst[3] + cst[2] * 2 + 1] = pval;
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
        post[cst[6] + cst[5] * 2 + 1] = pval;
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
        post[cst[6] + cst[5] * 2 + 1] = pval;
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
    if kind == 93 {
        // B7: method call through an impl row: pop the two struct addresses
        // into the arg registers, call the method, then apply the operator
        // derivation (== eq, != ~eq, < lt(a,b), <= ~lt(b,a), > lt(b,a), >= ~lt(a,b)).
        let mop = post[100000 + cst[9]];
        emit1(code, cst, 94); // pop rsi (right operand, second arg)
        emit1(code, cst, 95); // pop rdi (left operand, first arg)
        if mop == 9 || mop == 10 {
            emit1(code, cst, 72); emit1(code, cst, 135); emit1(code, cst, 254);
        }
        emit1(code, cst, 232);
        post[cst[6] + cst[5] * 2] = cst[0];
        post[cst[6] + cst[5] * 2 + 1] = pval;
        cst[5] = cst[5] + 1;
        emit4(code, cst, 0);
        if mop == 7 || mop == 9 || mop == 11 {
            // != / <= / >= negate the 0/1 result.
            emit1(code, cst, 131); emit1(code, cst, 240); emit1(code, cst, 1);
        }
        emit1(code, cst, 80);
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
        post[cst[6] + cst[5] * 2 + 1] = pval;
        cst[5] = cst[5] + 1;
        emit4(code, cst, 0);
        emit1(code, cst, 80);
        return 0;
    }
    if pval == 20 {
        emit1(code, cst, 88);
        emit1(code, cst, 72); emit1(code, cst, 247); emit1(code, cst, 216);
        emit1(code, cst, 80);
        return 0;
    }
    emit1(code, cst, 89);
    emit1(code, cst, 88);
    if pval == 1 { emit1(code, cst, 72); emit1(code, cst, 1); emit1(code, cst, 200); }
    else if pval == 2 { emit1(code, cst, 72); emit1(code, cst, 41); emit1(code, cst, 200); }
    else if pval == 3 { emit1(code, cst, 72); emit1(code, cst, 15); emit1(code, cst, 175); emit1(code, cst, 193); }
    else if pval == 4 {
        emit1(code, cst, 72); emit1(code, cst, 153);
        emit1(code, cst, 72); emit1(code, cst, 247); emit1(code, cst, 249);
    } else if pval == 5 {
        emit1(code, cst, 72); emit1(code, cst, 153);
        emit1(code, cst, 72); emit1(code, cst, 247); emit1(code, cst, 249);
        emit1(code, cst, 72); emit1(code, cst, 137); emit1(code, cst, 208);
    } else if pval >= 6 && pval <= 11 {
        emit1(code, cst, 72); emit1(code, cst, 57); emit1(code, cst, 200);
        if pval == 6 { emit1(code, cst, 15); emit1(code, cst, 148); }
        else if pval == 7 { emit1(code, cst, 15); emit1(code, cst, 149); }
        else if pval == 8 { emit1(code, cst, 15); emit1(code, cst, 156); }
        else if pval == 9 { emit1(code, cst, 15); emit1(code, cst, 158); }
        else if pval == 10 { emit1(code, cst, 15); emit1(code, cst, 159); }
        else { emit1(code, cst, 15); emit1(code, cst, 157); }
        emit1(code, cst, 192);
        emit1(code, cst, 72); emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 192);
    } else if pval == 12 || pval == 13 {
        // rax = lhs, rcx = rhs: normalize both, then combine truth values.
        emit1(code, cst, 72); emit1(code, cst, 133); emit1(code, cst, 192);
        emit1(code, cst, 15); emit1(code, cst, 149); emit1(code, cst, 192);
        emit1(code, cst, 72); emit1(code, cst, 133); emit1(code, cst, 201);
        emit1(code, cst, 15); emit1(code, cst, 149); emit1(code, cst, 193);
        if pval == 13 { emit1(code, cst, 32); emit1(code, cst, 200); }
        else { emit1(code, cst, 8); emit1(code, cst, 200); }
        emit1(code, cst, 72); emit1(code, cst, 15); emit1(code, cst, 182); emit1(code, cst, 192);
    } else if pval == 14 { emit1(code, cst, 72); emit1(code, cst, 9); emit1(code, cst, 200); }
    else if pval == 15 { emit1(code, cst, 72); emit1(code, cst, 49); emit1(code, cst, 200); }
    else if pval == 16 { emit1(code, cst, 72); emit1(code, cst, 33); emit1(code, cst, 200); }
    else if pval == 17 { emit1(code, cst, 72); emit1(code, cst, 211); emit1(code, cst, 224); }
    else if pval == 18 { emit1(code, cst, 72); emit1(code, cst, 211); emit1(code, cst, 248); }
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
