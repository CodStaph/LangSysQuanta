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
    let t1 = parse_ty(src, st, post);
    if st[3] != 0 || t1 == 0 { return 0 - 1; }
    let t2 = 0;
    skip(src, st, st[1]);
    if st[0] < st[1] && src[st[0]] == 44 {
        st[0] = st[0] + 1;
        t2 = parse_ty(src, st, post);
        if st[3] != 0 || t2 == 0 { return 0 - 1; }
    }
    if expect_char(src, st, 93, st[1]) == 0 { return 0 - 1; }
    let ti = tmpl_find(post, nm);
    if ti < 0 { return 0 - 1; }
    // R2.2: struct generic templates share the table; nparams bit 7 marks
    // them so `S[Int, Str]` is NOT consumed as a generic-enum description.
    if post[123001 + ti * 12 + 1] & 128 { st[0] = save; return 0; }
    let ii = mk_inst(post, ti, t1, t2);
    if ii < 0 { return 0 - 1; }
    return 8 | (ii << 8);
}

