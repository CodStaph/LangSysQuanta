from pathlib import Path
p=Path('bootstrap/seed/seed.c')
s=p.read_text(encoding='utf-8')
def rep(old,new):
    global s
    assert old in s, old[:80]
    s=s.replace(old,new,1)

rep('''    E_EQ, E_NE, E_LT, E_LE, E_GT, E_GE, E_NEG, E_CALL
};''','''    E_EQ, E_NE, E_LT, E_LE, E_GT, E_GE, E_NEG, E_CALL, E_INDEX
};''')

rep('''enum { S_LET, S_ASSIGN, S_WRITE, S_RETURN, S_WHILE, S_IF };''',
'''enum { S_LET, S_ASSIGN, S_WRITE, S_RETURN, S_WHILE, S_IF, S_ARR, S_INDEX_ASSIGN };''')

rep('''    char name[64];
    char str[512];
    u32 len;
};''','''    char name[64];
    char str[512];
    u32 len;
    int elem;
    int index;
};''')

rep('''static char var_names[MAX_VARS][160];
static int var_count;''','''#define MAX_ARRS 64
struct Arr {
    char name[160];
    u32 off;
    u32 count;
    int elem;
};
static struct Arr arrs[MAX_ARRS];
static int narrs;

static char var_names[MAX_VARS][160];
static int var_count;''')

rep('''static struct { u32 pos; int fn_idx; } call_patch[MAX_PATCH];
static int ncall_patch;''','''static struct { u32 pos; int fn_idx; } call_patch[MAX_PATCH];
static int ncall_patch;
static struct { u32 pos; int arr; } arr_patch[MAX_PATCH];
static int narr_patch;''')

# insert arr_slot after memcmp_str definition
anchor='''static int memcmp_str(const char *a, const char *b) {
    while (*a && *b) {
        if (*a != *b) return 0;
        a++; b++;
    }
    return *a == *b;
}'''
assert anchor in s
arr_fn=anchor+'''

static int arr_slot(const char *name, int create, int elem, u32 count) {
    char key[160];
    int n = 0;
    u32 f = (u32)current_fn;
    char tmp[12];
    int t = 0;
    if (f == 0) tmp[t++] = '0';
    while (f) { tmp[t++] = (char)('0' + (f % 10)); f /= 10; }
    while (t) key[n++] = tmp[--t];
    key[n++] = ':';
    const char *q = name;
    while (*q && n < 158) key[n++] = *q++;
    key[n] = 0;

    for (int i = 0; i < narrs; i++)
        if (memcmp_str(arrs[i].name, key)) return i;
    if (!create) die("unknown array");
    if (narrs >= MAX_ARRS) die("too many arrays");
    if (dlen + (u32)elem * count > DATA_MAX) die("array too large");
    struct Arr *a = &arrs[narrs];
    memcopy(a->name, key, (u32)slen(key) + 1);
    a->off = dlen;
    a->count = count;
    a->elem = elem;
    for (u32 i = 0; i < (u32)elem * count; i++) data[dlen++] = 0;
    return narrs++;
}'''
s=s.replace(anchor,arr_fn,1)

# parse_primary: index branch
rep('''        expect_char(')');
        return e;
    }
    int e = new_expr(E_VAR);''','''        expect_char(')');
        return e;
    }
    if (*P == '[') {
        P++;
        int e = new_expr(E_INDEX);
        memcopy(exprs[e].name, name, (u32)slen(name) + 1);
        exprs[e].a = parse_expr();
        expect_char(']');
        return e;
    }
    int e = new_expr(E_VAR);''')

# let branch optional array
rep('''        if (at_word("let")) {
            P += 3;
            parse_ident(s->name, sizeof(s->name));
            expect_char('=');
            s->e = parse_expr();
            expect_char(';');
            s->kind = S_LET;
        } else if (at_word("if")) {''','''        if (at_word("let")) {
            P += 3;
            parse_ident(s->name, sizeof(s->name));
            skip();
            if (*P == ':') {
                P++;
                expect_word("Array");
                expect_char('[');
                if (at_word("U8")) { P += 2; s->elem = 1; }
                else { expect_word("Int"); s->elem = 8; }
                expect_char(',');
                s->len = parse_number();
                expect_char(']');
                expect_char('=');
                expect_word("Array");
                expect_char('.');
                expect_word("zeroed");
                expect_char('(');
                expect_char(')');
                expect_char(';');
                s->kind = S_ARR;
            } else {
                expect_char('=');
                s->e = parse_expr();
                expect_char(';');
                s->kind = S_LET;
            }
        } else if (at_word("if")) {''')

# assignment branch index assignment
rep('''        } else {
            parse_ident(s->name, sizeof(s->name));
            expect_char('=');
            s->e = parse_expr();
            expect_char(';');
            s->kind = S_ASSIGN;
        }''','''        } else {
            parse_ident(s->name, sizeof(s->name));
            skip();
            if (*P == '[') {
                P++;
                s->index = new_expr(E_INDEX);
                memcopy(exprs[s->index].name, s->name, (u32)slen(s->name) + 1);
                exprs[s->index].a = parse_expr();
                expect_char(']');
                expect_char('=');
                s->e = parse_expr();
                expect_char(';');
                s->kind = S_INDEX_ASSIGN;
            } else {
                expect_char('=');
                s->e = parse_expr();
                expect_char(';');
                s->kind = S_ASSIGN;
            }
        }''')

# E_INDEX codegen before E_CALL
rep('''    case E_CALL: {''','''    case E_INDEX: {
        int ai = arr_slot(e->name, 0, 0, 0);
        emit_expr(e->a);
        emit1(0x48); emit1(0x8d); emit1(0x0d);
        if (narr_patch >= MAX_PATCH) die("too many array patches");
        arr_patch[narr_patch].pos = clen;
        arr_patch[narr_patch].arr = ai;
        narr_patch++;
        emit4(0);
        if (arrs[ai].elem == 8) {
            emit1(0x48); emit1(0x8d); emit1(0x0c); emit1(0xc1);
            emit1(0x48); emit1(0x8b); emit1(0x01);
        } else {
            emit1(0x48); emit1(0x01); emit1(0xc1);
            emit1(0x0f); emit1(0xb6); emit1(0x01);
        }
        break;
    }
    case E_CALL: {''')

# S_ARR / S_INDEX_ASSIGN before S_IF
rep('''    case S_IF: {''','''    case S_ARR:
        arr_slot(s->name, 1, s->elem, s->len);
        break;
    case S_INDEX_ASSIGN: {
        int ai = arr_slot(s->name, 0, 0, 0);
        emit_expr(s->e);
        emit1(0x50);
        emit_expr(s->index);
        emit1(0x5a);
        emit1(0x48); emit1(0x8d); emit1(0x0d);
        if (narr_patch >= MAX_PATCH) die("too many array patches");
        arr_patch[narr_patch].pos = clen;
        arr_patch[narr_patch].arr = ai;
        narr_patch++;
        emit4(0);
        if (arrs[ai].elem == 8) {
            emit1(0x48); emit1(0x8d); emit1(0x0c); emit1(0xc1);
            emit1(0x48); emit1(0x89); emit1(0x11);
        } else {
            emit1(0x48); emit1(0x01); emit1(0xc1);
            emit1(0x88); emit1(0x11);
        }
        break;
    }
    case S_IF: {''')

# build_elf arr patches
rep('''    for (int i = 0; i < ncall_patch; i++) {
        u32 pos = call_patch[i].pos;
        u32 target = func_label[call_patch[i].fn_idx];
        i64 disp = (i64)target - (i64)(pos + 4u);
        put32(code + pos, (u32)(i32)disp);
    }''','''    for (int i = 0; i < ncall_patch; i++) {
        u32 pos = call_patch[i].pos;
        u32 target = func_label[call_patch[i].fn_idx];
        i64 disp = (i64)target - (i64)(pos + 4u);
        put32(code + pos, (u32)(i32)disp);
    }
    for (int i = 0; i < narr_patch; i++) {
        u32 pos = arr_patch[i].pos;
        u64 instr_end = code_vaddr + (u64)pos + 4ull;
        u64 addr = data_vaddr + (u64)arrs[arr_patch[i].arr].off;
        i64 disp = (i64)addr - (i64)instr_end;
        put32(code + pos, (u32)(i32)disp);
    }''')

p.write_text(s,encoding='utf-8')
print('patched arrays')
