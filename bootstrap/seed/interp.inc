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
static int ret_flag;
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
    for (int i = 0; i < funcs[fi].nparams; i++) {
        int slot = var_slot(funcs[fi].params[i], 1);
        if (i < nargs) var_vals[slot] = args[i];
        else var_vals[slot] = 0;
    }
    int saved_flag = ret_flag;
    i64 saved_val = ret_val;
    ret_flag = 0;
    ret_val = 0;
    exec_list(funcs[fi].b0);
    i64 result = ret_val;
    ret_flag = saved_flag;
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
        if (slot < 0) die("interp: unknown variable");
        return var_vals[slot];
    }
    case E_NEG:
        return -eval_expr(e->a);
    case E_FIELD: {
        int vi = svar_slot(e->name, 0, 0);
        if (vi < 0) {
            int si = slice_slot(e->name, 0, 0);
            if (si >= 0 && same_str(e->field, "len")) return (i64)load64(slices[si].off + 8);
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
        if (same_str(e->name, "read_file") || same_str(e->name, "write_file")) {
            int is_read = same_str(e->name, "read_file");
            if (e->nargs != 3) die("interp: io builtin needs 3 args");
            if (exprs[e->args[0]].kind != E_STR) die("interp: io path must be literal");
            if (exprs[e->args[1]].kind != E_VAR) die("interp: io buffer must be array name");
            int ai = arr_slot(exprs[e->args[1]].name, 0, 0, 0);
            u32 cap = (u32)eval_expr(e->args[2]);
            if (is_read) return (i64)read_file(exprs[e->args[0]].lit, (char *)(data + arrs[ai].off), cap);
            return (i64)write_file(exprs[e->args[0]].lit, data + arrs[ai].off, cap);
        }
        int fi = find_func(e->name);
        if (fi < 0) die("interp: unknown function");
        i64 args[6];
        if (e->nargs > 6) die("interp: too many args");
        for (int i = 0; i < e->nargs; i++) args[i] = eval_expr(e->args[i]);
        return call_fn(fi, args, e->nargs);
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
    case S_WRITE:
        host_write(s->str, s->len);
        break;
    case S_RETURN:
        ret_val = eval_expr(s->e);
        ret_flag = 1;
        break;
    case S_WHILE:
        while (eval_expr(s->e) != 0) {
            exec_list(s->b0);
            if (ret_flag) return;
        }
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
        if (ret_flag) return;
    }
}

static int run_program(void) {
    int main_fi = find_func("main");
    if (main_fi < 0) die("interp: missing main");
    dlen = 0;
    var_count = 0;
    narrs = 0;
    nsvars = 0;
    nslices = 0;
    ret_flag = 0;
    ret_val = 0;
    i64 rc = call_fn(main_fi, NULL, 0);
    return (int)(rc & 0xff);
}
