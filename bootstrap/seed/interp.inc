/*
 * interp.inc — B-LS interpreter for `seed --run`.
 *
 * Included by seed.c after the host read_file/write_file helpers.
 * Purpose: run B-LS programs on the developer host (including Windows)
 * so stage1 can be tested before it is compiled to ELF.
 *
 * Limitations: no recursion-safe locals (functions use global slots),
 * no bounds checks on arrays/slices, no error recovery.
 */

static i64 var_vals[MAX_VARS];
static int run_argc;
static char **run_argv;
static char dyn_path[256];
static int ret_flag;
static int brk_flag;
static int cont_flag;
static i64 ret_val;

static u64 load64(u32 off) {
    if (off + 8u > DATA_MAX) die("interp: memory read OOB");
    u64 v = 0;
    for (int i = 0; i < 8; i++) v |= ((u64)data[off + (u32)i]) << (8 * i);
    return v;
}

static void store64(u32 off, u64 v) {
    if (off + 8u > DATA_MAX) die("interp: memory write OOB");
    for (int i = 0; i < 8; i++) data[off + (u32)i] = (u8)(v >> (8 * i));
}

static u8 load8(u32 off) {
    if (off >= DATA_MAX) die("interp: memory read OOB");
    return data[off];
}

static void store8(u32 off, u8 v) {
    if (off >= DATA_MAX) die("interp: memory write OOB");
    data[off] = v;
}

static void host_write(const char *s, u32 n) {
#ifdef _WIN32
    fwrite(s, 1, n, stdout);
    fflush(stdout);
#else
    syscall3(1, 1, (long)s, (long)n);
#endif
}

static i64 eval_expr(int idx);
static void exec_list(int head);

static i64 call_fn(int fi, i64 *args, int nargs) {
    if (fi < 0 || fi >= nfuncs) die("interp: bad function");
    int saved_fn = current_fn;
    current_fn = fi;
    int ai = 0;
    for (int i = 0; i < funcs[fi].nparams; i++) {
        if (funcs[fi].param_elem[i] == 0) {
            int slot = var_slot(funcs[fi].params[i], 1);
            var_vals[slot] = (ai < nargs) ? args[ai] : 0;
            ai++;
        } else if (funcs[fi].param_elem[i] == 2) {
            int sv = strvar_slot(funcs[fi].params[i], 1);
            store64(strvars[sv].off, (ai < nargs) ? (u64)args[ai] : 0); ai++;
            store64(strvars[sv].off + 8, (ai < nargs) ? (u64)args[ai] : 0); ai++;
            store64(strvars[sv].off + 16, (ai < nargs) ? (u64)args[ai] : 0); ai++;
        } else {
            int si = slice_slot(funcs[fi].params[i], 1, funcs[fi].param_elem[i]);
            u64 base = (ai < nargs) ? (u64)args[ai] : 0; ai++;
            u64 len = (ai < nargs) ? (u64)args[ai] : 0; ai++;
            store64(slices[si].off, base);
            store64(slices[si].off + 8, len);
        }
    }
    int saved_flag = ret_flag;
    int saved_brk = brk_flag;
    int saved_cont = cont_flag;
    i64 saved_val = ret_val;
    ret_flag = 0;
    brk_flag = 0;
    cont_flag = 0;
    ret_val = 0;
    exec_list(funcs[fi].b0);
    i64 result = ret_val;
    ret_flag = saved_flag;
    brk_flag = saved_brk;
    cont_flag = saved_cont;
    ret_val = saved_val;
    current_fn = saved_fn;
    return result;
}

static i64 eval_expr(int idx) {
    struct Expr *e = &exprs[idx];
    switch (e->kind) {
    case E_NUM:
        return (i64)e->val;
    case E_STR:
        die("interp: string literal used outside io builtin");
        return 0;
    case E_VAR: {
        int slot = var_slot(e->name, 0);
        if (slot < 0) {
            int ev = evar_slot(e->name, 0, 0);
            if (ev >= 0) return (i64)load64(evars[ev].off);
            die("interp: unknown variable");
        }
        return var_vals[slot];
    }
    case E_NEG:
        return -eval_expr(e->a);
    case E_AND:
        return (eval_expr(e->a) != 0) && (eval_expr(e->b) != 0);
    case E_OR:
        return (eval_expr(e->a) != 0) || (eval_expr(e->b) != 0);
    case E_FIELD: {
        int vi = svar_slot(e->name, 0, 0);
        if (vi < 0) {
            int si = slice_slot(e->name, 0, 0);
            if (si >= 0 && same_str(e->field, "len")) return (i64)load64(slices[si].off + 8);
            int sv = strvar_slot(e->name, 0);
            if (sv >= 0 && same_str(e->field, "len")) return (i64)load64(strvars[sv].off + 16);
            die("interp: unknown field");
        }
        int fi = find_field(svars[vi].sidx, e->field);
        if (fi < 0) die("interp: unknown field");
        u32 off = svars[vi].off + structs[svars[vi].sidx].fields[fi].off;
        if (structs[svars[vi].sidx].fields[fi].elem == 8) return (i64)load64(off);
        return (i64)load8(off);
    }
    case E_INDEX: {
        i64 iv = eval_expr(e->a);
        int si = slice_slot(e->name, 0, 0);
        if (si >= 0) {
            u32 base = (u32)load64(slices[si].off);
            u32 off = base + (u32)iv * (u32)slices[si].elem;
            if (slices[si].elem == 8) return (i64)load64(off);
            return (i64)load8(off);
        }
        int ai = arr_slot(e->name, 0, 0, 0);
        u32 off = arrs[ai].off + (u32)iv * (u32)arrs[ai].elem;
        if (arrs[ai].elem == 8) return (i64)load64(off);
        return (i64)load8(off);
    }
    case E_CALL: {
        if (same_str(e->name, "argc")) {
            if (e->nargs != 0) die("interp: argc takes no args");
            return run_argc;
        }
        if (same_str(e->name, "arg_len")) {
            if (e->nargs != 1) die("interp: arg_len takes 1 arg");
            int i = (int)eval_expr(e->args[0]);
            if (i < 0 || i >= run_argc) return 0;
            int n = 0;
            while (run_argv[i][n]) n++;
            return n;
        }
        if (same_str(e->name, "arg_byte")) {
            if (e->nargs != 2) die("interp: arg_byte takes 2 args");
            int i = (int)eval_expr(e->args[0]);
            int p = (int)eval_expr(e->args[1]);
            if (i < 0 || i >= run_argc) return 0;
            int n = 0;
            while (run_argv[i][n]) n++;
            if (p < 0 || p >= n) return 0;
            return (unsigned char)run_argv[i][p];
        }
        if (same_str(e->name, "read_file") || same_str(e->name, "write_file")) {
            int is_read = same_str(e->name, "read_file");
            if (e->nargs != 3) die("interp: io builtin needs 3 args");
            if (exprs[e->args[1]].kind != E_VAR) die("interp: io buffer must be array name");
            const char *path = 0;
            if (exprs[e->args[0]].kind == E_STR) {
                path = exprs[e->args[0]].lit;
            } else if (exprs[e->args[0]].kind == E_VAR) {
                int si = slice_slot(exprs[e->args[0]].name, 0, 0);
                u32 base = 0, n = 0;
                if (si >= 0) {
                    base = (u32)load64(slices[si].off);
                    n = (u32)load64(slices[si].off + 8);
                } else {
                    int sv = strvar_slot(exprs[e->args[0]].name, 0);
                    if (sv < 0) die("interp: io path must be a Slice or Str");
                    base = (u32)load64(strvars[sv].off);
                    n = (u32)load64(strvars[sv].off + 8);
                }
                if (n > 255) n = 255;
                for (u32 i = 0; i < n; i++) dyn_path[i] = (char)load8(base + i);
                dyn_path[n] = 0;
                path = dyn_path;
            } else {
                die("interp: io path must be literal, Slice or Str");
            }
            int ai = arr_slot(exprs[e->args[1]].name, 0, 0, 0);
            u32 cap = (u32)eval_expr(e->args[2]);
            if (is_read) return (i64)read_file(path, (char *)(data + arrs[ai].off), cap);
            return (i64)write_file(path, data + arrs[ai].off, cap);
        }
        int fi = find_func(e->name);
        if (fi < 0) die("interp: unknown function");
        if (e->nargs != funcs[fi].nparams) die("interp: argument count mismatch");
        i64 args[12];
        int n = 0;
        for (int i = 0; i < e->nargs; i++) {
            if (funcs[fi].param_elem[i] == 0) {
                args[n++] = eval_expr(e->args[i]);
            } else if (funcs[fi].param_elem[i] == 2) {
                struct Expr *ae = &exprs[e->args[i]];
                if (ae->kind == E_STR) {
                    int li = add_lit(ae->lit, ae->litlen);
                    args[n++] = (i64)str_off[li];
                    args[n++] = (i64)ae->litlen;
                    args[n++] = (i64)utf8_count((const u8 *)ae->lit, ae->litlen);
                } else if (ae->kind == E_VAR) {
                    int sv = strvar_slot(ae->name, 0);
                    if (sv < 0) die("interp: Str argument must be a string variable");
                    args[n++] = (i64)load64(strvars[sv].off);
                    args[n++] = (i64)load64(strvars[sv].off + 8);
                    args[n++] = (i64)load64(strvars[sv].off + 16);
                } else {
                    die("interp: bad Str argument");
                }
            } else {
                struct Expr *ae = &exprs[e->args[i]];
                if (ae->kind != E_VAR) die("interp: Slice argument must be a variable");
                int si = slice_slot(ae->name, 0, 0);
                if (si < 0) die("interp: argument is not a slice");
                args[n++] = (i64)load64(slices[si].off);
                args[n++] = (i64)load64(slices[si].off + 8);
            }
        }
        return call_fn(fi, args, n);
    }
    default: {
        i64 a = eval_expr(e->a);
        i64 b = eval_expr(e->b);
        switch (e->kind) {
        case E_ADD: return a + b;
        case E_SUB: return a - b;
        case E_MUL: return a * b;
        case E_DIV: if (b == 0) die("interp: divide by zero"); return a / b;
        case E_MOD: if (b == 0) die("interp: divide by zero"); return a % b;
        case E_EQ: return a == b;
        case E_NE: return a != b;
        case E_LT: return a < b;
        case E_LE: return a <= b;
        case E_GT: return a > b;
        case E_GE: return a >= b;
        case E_BITAND: return a & b;
        case E_BITOR: return a | b;
        case E_BITXOR: return a ^ b;
        case E_SHL: return (i64)((u64)a << ((u64)b & 63));
        case E_SHR: return a >> ((u64)b & 63);
        default: die("interp: bad expression"); return 0;
        }
    }
    }
}

static void exec_stmt(int i) {
    struct Stmt *s = &stmts[i];
    switch (s->kind) {
    case S_LET:
    case S_ASSIGN: {
        int slot = var_slot(s->name, s->kind == S_LET);
        if (slot < 0) die("interp: unknown variable");
        var_vals[slot] = eval_expr(s->e);
        break;
    }
    case S_EXPR:
        (void)eval_expr(s->e);
        break;
    case S_WRITE: {
        struct Expr *we = &exprs[s->e];
        if (we->kind == E_STR) {
            host_write(we->lit, we->litlen);
        } else if (we->kind == E_VAR) {
            int sv = strvar_slot(we->name, 0);
            if (sv < 0) die("interp: write expects Str");
            u32 base = (u32)load64(strvars[sv].off);
            u32 n = (u32)load64(strvars[sv].off + 8);
            host_write((const char *)(data + base), n);
        } else {
            die("interp: write expects Str");
        }
        break;
    }
    case S_STR_SET: {
        int sv = strvar_slot(s->name, 1);
        struct Expr *re = &exprs[s->e];
        if (re->kind == E_STR) {
            int li = add_lit(re->lit, re->litlen);
            store64(strvars[sv].off, (u64)str_off[li]);
            store64(strvars[sv].off + 8, (u64)re->litlen);
            store64(strvars[sv].off + 16, (u64)utf8_count((const u8 *)re->lit, re->litlen));
        } else if (re->kind == E_VAR) {
            int src = strvar_slot(re->name, 0);
            if (src < 0) die("interp: Str assignment expects Str");
            store64(strvars[sv].off, load64(strvars[src].off));
            store64(strvars[sv].off + 8, load64(strvars[src].off + 8));
            store64(strvars[sv].off + 16, load64(strvars[src].off + 16));
        } else {
            die("interp: Str assignment expects literal or Str");
        }
        break;
    }
    case S_RETURN:
        ret_val = eval_expr(s->e);
        ret_flag = 1;
        break;
    case S_ENUM_LET: {
        int ei = find_enum(s->type);
        if (ei < 0) die("interp: unknown enum type");
        int vi = evar_slot(s->name, 1, ei);
        store64(evars[vi].off, (u64)s->variant);
        if (s->has_payload) store64(evars[vi].off + 8, (u64)eval_expr(s->e));
        break;
    }
    case S_MATCH: {
        int vi = evar_slot(s->name, 0, 0);
        int vslot = -1;
        i64 v;
        if (vi >= 0) {
            v = (i64)load64(evars[vi].off);
        } else {
            vslot = var_slot(s->name, 0);
            if (vslot < 0) die("interp: match subject must be a variable");
            v = var_vals[vslot];
        }
        for (int k = 0; k < s->armn; k++) {
            struct MatchArm *a = &arms[s->arm0 + k];
            if (v == (i64)a->tag) {
                if (a->has_bind) {
                    if (vi < 0) die("interp: payload binding requires enum payload");
                    int slot = var_slot(a->bind, 1);
                    var_vals[slot] = (i64)load64(evars[vi].off + 8);
                }
                exec_list(a->b0);
                return;
            }
        }
        break;
    }
    case S_WHILE:
        while (eval_expr(s->e) != 0) {
            exec_list(s->b0);
            if (ret_flag) return;
            if (brk_flag) { brk_flag = 0; break; }
            if (cont_flag) { cont_flag = 0; continue; }
        }
        break;
    case S_BREAK:
        brk_flag = 1;
        break;
    case S_CONTINUE:
        cont_flag = 1;
        break;
    case S_IF:
        if (eval_expr(s->e) != 0) exec_list(s->b0);
        else if (s->e0 >= 0) exec_list(s->e0);
        break;
    case S_ARR:
        (void)arr_slot(s->name, 1, s->elem, s->len);
        break;
    case S_SVAR_DECL: {
        int si = find_struct(s->type);
        if (si < 0) die("interp: unknown struct type");
        (void)svar_slot(s->name, 1, si);
        break;
    }
    case S_SLICE_INIT: {
        int si = slice_slot(s->name, 1, s->elem);
        int ai = arr_slot(s->type, 0, 0, 0);
        i64 off = eval_expr(s->index);
        store64(slices[si].off, (u64)arrs[ai].off + (u64)off);
        store64(slices[si].off + 8, (u64)eval_expr(s->e));
        break;
    }
    case S_INDEX_ASSIGN: {
        i64 val = eval_expr(s->e);
        i64 iv = eval_expr(s->index);
        int si = slice_slot(s->name, 0, 0);
        if (si >= 0) {
            u32 base = (u32)load64(slices[si].off);
            u32 off = base + (u32)iv * (u32)slices[si].elem;
            if (slices[si].elem == 8) store64(off, (u64)val);
            else store8(off, (u8)val);
            break;
        }
        int ai = arr_slot(s->name, 0, 0, 0);
        u32 off = arrs[ai].off + (u32)iv * (u32)arrs[ai].elem;
        if (arrs[ai].elem == 8) store64(off, (u64)val);
        else store8(off, (u8)val);
        break;
    }
    case S_FIELD_ASSIGN: {
        int vi = svar_slot(s->name, 0, 0);
        if (vi < 0) die("interp: unknown struct variable");
        int fi = find_field(svars[vi].sidx, s->field);
        if (fi < 0) die("interp: unknown field");
        u32 off = svars[vi].off + structs[svars[vi].sidx].fields[fi].off;
        i64 val = eval_expr(s->e);
        if (structs[svars[vi].sidx].fields[fi].elem == 8) store64(off, (u64)val);
        else store8(off, (u8)val);
        break;
    }
    default:
        die("interp: unknown statement");
    }
}

static void exec_list(int head) {
    for (int i = head; i >= 0; i = stmts[i].next) {
        exec_stmt(i);
        if (ret_flag || brk_flag || cont_flag) return;
    }
}

static int run_program(int argc, char **argv) {
    run_argc = argc;
    run_argv = argv;
    int main_fi = find_func("main");
    if (main_fi < 0) die("interp: missing main");
    dlen = 0;
    var_count = 0;
    narrs = 0;
    nsvars = 0;
    nslices = 0;
    nstrvars = 0;
    str_count = 0;
    ret_flag = 0;
    brk_flag = 0;
    cont_flag = 0;
    ret_val = 0;
    i64 rc = call_fn(main_fi, 0, 0);
    return (int)(rc & 0xff);
}
