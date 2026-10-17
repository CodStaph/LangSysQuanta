/*
 * seed.c — bootstrap stage0 for LangSysQuanta.
 *
 * M1a scope:
 *   fn main() -> Int {
 *       let x = 2 + 3 * 4;
 *       let i = 0;
 *       while i < x { i = i + 1; }
 *       if i == 14 { write("ok\n"); } else { write("bad\n"); }
 *       return i;
 *   }
 *
 * Supported: let/assign, int arithmetic + comparisons, if/else, while,
 * write(string), return(expr). Not yet: user functions, structs/enums,
 * arrays/slices (M1b), file I/O (stage1).
 *
 * No libc on Linux, no assembler, no linker, no LLVM.
 * Windows is a developer convenience host (CRT file I/O).
 */

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef int i32;
typedef long long i64;

#ifdef _WIN32
#include <stdio.h>
#include <stdlib.h>
typedef unsigned long long usize;
#else
static long syscall1(long n, long a) {
    long r;
    __asm__ volatile("syscall" : "=a"(r) : "a"(n), "D"(a) : "rcx", "r11", "memory");
    return r;
}
static long syscall3(long n, long a, long b, long c) {
    long r;
    __asm__ volatile("syscall"
                     : "=a"(r)
                     : "a"(n), "D"(a), "S"(b), "d"(c)
                     : "rcx", "r11", "memory");
    return r;
}
static long syscall4(long n, long a, long b, long c, long d) {
    long r;
    register long r10 __asm__("r10") = d;
    __asm__ volatile("syscall"
                     : "=a"(r)
                     : "a"(n), "D"(a), "S"(b), "d"(c), "r"(r10)
                     : "rcx", "r11", "memory");
    return r;
}
#endif

#define IN_MAX (1u << 20)
#define CODE_MAX 131072u
#define DATA_MAX 65536u
#define OUT_MAX (IN_MAX + CODE_MAX + DATA_MAX + 4096u)

#define MAX_EXPR 4096
#define MAX_STMT 2048
#define MAX_VARS 256
#define MAX_STRS 128
#define MAX_PATCH 4096

static char inbuf[IN_MAX];
static u8 code[CODE_MAX];
static u32 clen;
static u8 data[DATA_MAX];
static u32 dlen;
static u8 out[OUT_MAX];

/* ---------- AST ---------- */

enum {
    E_NUM, E_VAR, E_ADD, E_SUB, E_MUL, E_DIV, E_MOD,
    E_EQ, E_NE, E_LT, E_LE, E_GT, E_GE, E_NEG, E_CALL, E_INDEX, E_FIELD, E_SLICE_LEN, E_STR,
    E_OR, E_AND, E_BITOR, E_BITXOR, E_BITAND, E_SHL, E_SHR
};

struct Expr {
    int kind;
    u32 val;
    int a, b;
    char name[64];
    char field[64];
    char lit[512];
    u32 litlen;
    int args[6];
    int nargs;
};

enum { S_LET, S_ASSIGN, S_WRITE, S_RETURN, S_WHILE, S_IF, S_ARR, S_INDEX_ASSIGN, S_SVAR_DECL, S_FIELD_ASSIGN, S_SLICE_INIT, S_EXPR,
    S_BREAK, S_CONTINUE, S_MATCH, S_ENUM_LET };

struct Stmt {
    int kind;
    int e;            /* expr index */
    int b0, b1;       /* then body */
    int e0, e1;       /* else body */
    int next;         /* sibling in the same block */
    char name[64];
    char type[64];
    char field[64];
    char str[512];
    u32 len;
    int elem;
    int index;
    int arm0;
    int armn;
    int variant;
    int has_payload;
};

static struct Expr exprs[MAX_EXPR];
static int nexpr;
static struct Stmt stmts[MAX_STMT];
static int nstmt;

#define MAX_ARMS 256
struct MatchArm {
    int tag;
    int b0;
    int b1;
    int has_bind;
    char bind[64];
};
static struct MatchArm arms[MAX_ARMS];
static int narm;

/* ---------- variables / strings ---------- */

#define MAX_FUNCS 64
struct Func {
    char name[64];
    char params[6][64];
    int param_elem[6];   /* 0 = Int, 1/8 = Slice element size */
    int nparams;
    int b0, b1;
};
static struct Func funcs[MAX_FUNCS];
static int nfuncs;
static int current_fn;
static u32 func_label[MAX_FUNCS];

#define MAX_ARRS 64
struct Arr {
    char name[160];
    u32 off;
    u32 count;
    int elem;
};
static struct Arr arrs[MAX_ARRS];
static int narrs;

#define MAX_ENUMS 16
#define MAX_VARIANTS 16
struct EnumDef {
    char name[64];
    char variants[MAX_VARIANTS][64];
    int payload[MAX_VARIANTS];
    int n;
};
static struct EnumDef enums[MAX_ENUMS];
static int nenums;

#define MAX_STRUCTS 32
#define MAX_FIELDS 16
struct FieldDef {
    char name[64];
    int elem;
    u32 off;
};
struct StructDef {
    char name[64];
    struct FieldDef fields[MAX_FIELDS];
    int nfields;
    u32 size;
};
static struct StructDef structs[MAX_STRUCTS];
static int nstructs;

#define MAX_SVARS 64
struct SVar {
    char name[160];
    u32 off;
    int sidx;
};
static struct SVar svars[MAX_SVARS];
static int nsvars;

#define MAX_EVARS 64
struct EVar {
    char name[160];
    u32 off;
    int eidx;
};
static struct EVar evars[MAX_EVARS];
static int nevars;

#define MAX_SLICES 64
struct SliceVar {
    char name[160];
    u32 off;
    int elem;
};
static struct SliceVar slices[MAX_SLICES];
static int nslices;

static char var_names[MAX_VARS][160];
static int var_count;

static u32 str_off[MAX_STRS];
static u32 str_len[MAX_STRS];
static int str_count;

static struct { u32 pos; int var; int store; } var_patch[MAX_PATCH];
static int nvar_patch;
static struct { u32 pos; int str; } str_patch[MAX_PATCH];
static int nstr_patch;
static struct { u32 pos; u32 target; } jump_patch[MAX_PATCH];
static int njump_patch;
static u32 loop_start[16];
static int loop_depth;
static struct { int jp; int depth; } break_patch[MAX_PATCH];
static int nbreak;
static struct { u32 pos; int fn_idx; } call_patch[MAX_PATCH];
static int ncall_patch;
static struct { u32 pos; int arr; } arr_patch[MAX_PATCH];
static int narr_patch;
static struct { u32 pos; u32 off; } struct_patch[MAX_PATCH];
static int nstruct_patch;

static const char *P;
static int line_no = 1;
static int main_b0, main_b1;

/* ---------- basic ---------- */

static u32 slen(const char *s) {
    u32 n = 0;
    while (s[n]) n++;
    return n;
}

static void *memcopy(void *dst, const void *src, u32 n) {
    u8 *d = (u8 *)dst;
    const u8 *s = (const u8 *)src;
    for (u32 i = 0; i < n; i++) d[i] = s[i];
    return dst;
}

static void *memzero(void *dst, u32 n) {
    u8 *d = (u8 *)dst;
    for (u32 i = 0; i < n; i++) d[i] = 0;
    return dst;
}

static void eputs(const char *s) {
#ifdef _WIN32
    printf("%s", s);
#else
    syscall3(1, 2, (long)s, (long)slen(s));
#endif
}

static void die(const char *msg) {
    eputs("seed: ");
    eputs(msg);
    eputs(" at line ");
#ifdef _WIN32
    printf("%d\n", line_no);
    exit(1);
#else
    {
        char buf[16];
        int n = 0;
        u32 v = (u32)line_no;
        char tmp[16];
        int t = 0;
        while (v) {
            tmp[t++] = (char)('0' + (v % 10));
            v /= 10;
        }
        while (t) buf[n++] = tmp[--t];
        buf[n++] = '\n';
        syscall3(1, 2, (long)buf, (long)n);
    }
    for (;;) syscall1(60, 1);
#endif
}

static void skip(void) {
    for (;;) {
        while (*P == ' ' || *P == '\t' || *P == '\r' || *P == '\n') {
            if (*P == '\n') line_no++;
            P++;
        }
        if (P[0] == '/' && P[1] == '/') {
            while (*P && *P != '\n') P++;
            continue;
        }
        if (P[0] == '/' && P[1] == '*') {
            P += 2;
            while (*P && !(P[0] == '*' && P[1] == '/')) {
                if (*P == '\n') line_no++;
                P++;
            }
            if (*P) P += 2;
            continue;
        }
        break;
    }
}

static int at_char(char c) {
    skip();
    return *P == c;
}

static int at_word(const char *w) {
    skip();
    const char *q = P;
    while (*w) {
        if (*q != *w) return 0;
        q++;
        w++;
    }
    return !((*q >= 'a' && *q <= 'z') || (*q >= 'A' && *q <= 'Z') ||
             (*q >= '0' && *q <= '9') || *q == '_');
}

static void expect_word(const char *w) {
    if (!at_word(w)) die("expected word");
    P += slen(w);
}

static void expect_char(char c) {
    if (!at_char(c)) die("expected character");
    P++;
}

static void parse_ident(char *out, u32 cap) {
    skip();
    u32 n = 0;
    if (!((*P >= 'a' && *P <= 'z') || (*P >= 'A' && *P <= 'Z') || *P == '_'))
        die("expected identifier");
    while ((*P >= 'a' && *P <= 'z') || (*P >= 'A' && *P <= 'Z') ||
           (*P >= '0' && *P <= '9') || *P == '_') {
        if (n + 1 >= cap) die("identifier too long");
        out[n++] = *P++;
    }
    out[n] = 0;
}

static u32 parse_number(void) {
    skip();
    if (*P < '0' || *P > '9') die("expected number");
    u32 v = 0;
    while (*P >= '0' && *P <= '9') {
        v = v * 10u + (u32)(*P - '0');
        P++;
    }
    return v;
}

static void parse_string(char *out, u32 cap, u32 *len) {
    expect_char('"');
    u32 n = 0;
    while (*P && *P != '"') {
        char c = *P++;
        if (c == '\\') {
            char e = *P++;
            if (e == 'n') c = '\n';
            else if (e == 't') c = '\t';
            else if (e == '\\') c = '\\';
            else if (e == '"') c = '"';
            else c = e;
        }
        if (n + 1 >= cap) die("string too long");
        out[n++] = c;
    }
    if (*P != '"') die("unterminated string");
    P++;
    out[n] = 0;
    *len = n;
}

/* ---------- expressions ---------- */

static int new_expr(int kind) {
    if (nexpr >= MAX_EXPR) die("too many expressions");
    struct Expr *e = &exprs[nexpr];
    memzero(e, sizeof(*e));
    e->kind = kind;
    e->a = e->b = -1;
    return nexpr++;
}

static int parse_expr(void);

static int same_str(const char *a, const char *b) {
    while (*a && *b) { if (*a != *b) return 0; a++; b++; }
    return *a == *b;
}
static int find_enum(const char *name) {
    for (int i = 0; i < nenums; i++) if (same_str(enums[i].name, name)) return i;
    return -1;
}
static int find_variant(int e, const char *name) {
    for (int i = 0; i < enums[e].n; i++) if (same_str(enums[e].variants[i], name)) return i;
    return -1;
}

static int find_struct(const char *name) {
    for (int i = 0; i < nstructs; i++) if (same_str(structs[i].name, name)) return i;
    return -1;
}
static int find_field(int sidx, const char *name) {
    for (int i = 0; i < structs[sidx].nfields; i++)
        if (same_str(structs[sidx].fields[i].name, name)) return i;
    return -1;
}

static int svar_slot(const char *name, int create, int sidx) {
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
    for (int i = 0; i < nsvars; i++) if (same_str(svars[i].name, key)) return i;
    if (!create) return -1;
    if (nsvars >= MAX_SVARS) die("too many struct variables");
    if (dlen + structs[sidx].size > DATA_MAX) die("struct too large");
    struct SVar *v = &svars[nsvars];
    memcopy(v->name, key, (u32)slen(key) + 1);
    v->off = dlen;
    v->sidx = sidx;
    for (u32 i = 0; i < structs[sidx].size; i++) data[dlen++] = 0;
    return nsvars++;
}

static int slice_slot(const char *name, int create, int elem) {
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
    for (int i = 0; i < nslices; i++) if (same_str(slices[i].name, key)) return i;
    if (!create) return -1;
    if (nslices >= MAX_SLICES) die("too many slices");
    if (dlen + 16 > DATA_MAX) die("slice data too large");
    struct SliceVar *v = &slices[nslices];
    memcopy(v->name, key, (u32)slen(key) + 1);
    v->off = dlen;
    v->elem = elem;
    for (int i = 0; i < 16; i++) data[dlen++] = 0;
    return nslices++;
}

static int evar_slot(const char *name, int create, int eidx) {
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
    for (int i = 0; i < nevars; i++) if (same_str(evars[i].name, key)) return i;
    if (!create) return -1;
    if (nevars >= MAX_EVARS) die("too many enum variables");
    if (dlen + 16 > DATA_MAX) die("enum data too large");
    struct EVar *v = &evars[nevars];
    memcopy(v->name, key, (u32)slen(key) + 1);
    v->off = dlen;
    v->eidx = eidx;
    for (int i = 0; i < 16; i++) data[dlen++] = 0;
    return nevars++;
}

static int parse_primary(void) {
    skip();
    if (at_char('(')) {
        P++;
        int e = parse_expr();
        expect_char(')');
        return e;
    }
    if (*P == '"') {
        int e = new_expr(E_STR);
        parse_string(exprs[e].lit, sizeof(exprs[e].lit), &exprs[e].litlen);
        return e;
    }
    if (*P >= '0' && *P <= '9') {
        int e = new_expr(E_NUM);
        exprs[e].val = parse_number();
        return e;
    }
    char name[64];
    parse_ident(name, sizeof(name));
    skip();
    if (*P == '(') {
        P++;
        int e = new_expr(E_CALL);
        memcopy(exprs[e].name, name, (u32)slen(name) + 1);
        while (!at_char(')')) {
            if (exprs[e].nargs >= 6) die("too many arguments");
            exprs[e].args[exprs[e].nargs++] = parse_expr();
            if (!at_char(',')) break;
            P++;
        }
        expect_char(')');
        return e;
    }
    if (*P == '.') {
        P++;
        char field[64];
        parse_ident(field, sizeof(field));
        int ei = find_enum(name);
        if (ei >= 0) {
            int tag = find_variant(ei, field);
            if (tag < 0) die("unknown enum variant");
            int e = new_expr(E_NUM);
            exprs[e].val = (u32)tag;
            return e;
        }
        int e = new_expr(E_FIELD);
        memcopy(exprs[e].name, name, (u32)slen(name) + 1);
        memcopy(exprs[e].field, field, (u32)slen(field) + 1);
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
    int e = new_expr(E_VAR);
    memcopy(exprs[e].name, name, (u32)slen(name) + 1);
    return e;
}

static int parse_unary(void) {
    skip();
    if (at_char('-')) {
        P++;
        int a = parse_unary();
        int e = new_expr(E_NEG);
        exprs[e].a = a;
        return e;
    }
    return parse_primary();
}

static int parse_mul(void) {
    int e = parse_unary();
    for (;;) {
        skip();
        int kind = -1;
        if (*P == '*') kind = E_MUL;
        else if (*P == '/') kind = E_DIV;
        else if (*P == '%') kind = E_MOD;
        if (kind < 0) break;
        P++;
        int r = parse_unary();
        int n = new_expr(kind);
        exprs[n].a = e;
        exprs[n].b = r;
        e = n;
    }
    return e;
}

static int parse_add(void) {
    int e = parse_mul();
    for (;;) {
        skip();
        int kind = -1;
        if (*P == '+') kind = E_ADD;
        else if (*P == '-') kind = E_SUB;
        if (kind < 0) break;
        P++;
        int r = parse_mul();
        int n = new_expr(kind);
        exprs[n].a = e;
        exprs[n].b = r;
        e = n;
    }
    return e;
}

static int parse_shift(void) {
    int e = parse_add();
    for (;;) {
        skip();
        int kind = -1;
        if (P[0] == '<' && P[1] == '<') { kind = E_SHL; P += 2; }
        else if (P[0] == '>' && P[1] == '>') { kind = E_SHR; P += 2; }
        if (kind < 0) break;
        int r = parse_add();
        int n = new_expr(kind);
        exprs[n].a = e;
        exprs[n].b = r;
        e = n;
    }
    return e;
}

static int parse_cmp(void) {
    int e = parse_shift();
    for (;;) {
        skip();
        int kind = -1;
        if (P[0] == '=' && P[1] == '=') { kind = E_EQ; P += 2; }
        else if (P[0] == '!' && P[1] == '=') { kind = E_NE; P += 2; }
        else if (P[0] == '<' && P[1] == '=') { kind = E_LE; P += 2; }
        else if (P[0] == '>' && P[1] == '=') { kind = E_GE; P += 2; }
        else if (P[0] == '<') { kind = E_LT; P += 1; }
        else if (P[0] == '>') { kind = E_GT; P += 1; }
        if (kind < 0) break;
        int r = parse_shift();
        int n = new_expr(kind);
        exprs[n].a = e;
        exprs[n].b = r;
        e = n;
    }
    return e;
}

static int parse_bitand(void) {
    int e = parse_cmp();
    for (;;) {
        skip();
        if (P[0] != '&' || P[1] == '&') break;
        P++;
        int r = parse_cmp();
        int n = new_expr(E_BITAND); exprs[n].a = e; exprs[n].b = r; e = n;
    }
    return e;
}

static int parse_bitxor(void) {
    int e = parse_bitand();
    for (;;) {
        skip();
        if (P[0] != '^') break;
        P++;
        int r = parse_bitand();
        int n = new_expr(E_BITXOR); exprs[n].a = e; exprs[n].b = r; e = n;
    }
    return e;
}

static int parse_bitor(void) {
    int e = parse_bitxor();
    for (;;) {
        skip();
        if (P[0] != '|' || P[1] == '|') break;
        P++;
        int r = parse_bitxor();
        int n = new_expr(E_BITOR); exprs[n].a = e; exprs[n].b = r; e = n;
    }
    return e;
}

static int parse_and(void) {
    int e = parse_bitor();
    for (;;) {
        skip();
        if (!(P[0] == '&' && P[1] == '&')) break;
        P += 2;
        int r = parse_bitor();
        int n = new_expr(E_AND); exprs[n].a = e; exprs[n].b = r; e = n;
    }
    return e;
}

static int parse_or(void) {
    int e = parse_and();
    for (;;) {
        skip();
        if (!(P[0] == '|' && P[1] == '|')) break;
        P += 2;
        int r = parse_and();
        int n = new_expr(E_OR); exprs[n].a = e; exprs[n].b = r; e = n;
    }
    return e;
}

static int parse_expr(void) { return parse_or(); }

/* ---------- statements ---------- */

static void parse_block(int *start, int *end) {
    expect_char('{');
    int head = -1, tail = -1;
    while (!at_char('}')) {
        if (nstmt >= MAX_STMT) die("too many statements");
        int idx = nstmt++;
        struct Stmt *s = &stmts[idx];
        memzero(s, sizeof(*s));
        s->e = -1;
        s->b0 = s->b1 = s->e0 = s->e1 = -1;
        s->next = -1;
        if (head < 0) head = idx; else stmts[tail].next = idx;
        tail = idx;

        if (at_word("let")) {
            P += 3;
            parse_ident(s->name, sizeof(s->name));
            skip();
            if (*P == ':') {
                P++;
                if (at_word("Array")) {
                    P += 5;
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
                } else if (at_word("Slice")) {
                    P += 5;
                    expect_char('[');
                    if (at_word("U8")) { P += 2; s->elem = 1; }
                    else { expect_word("Int"); s->elem = 8; }
                    expect_char(']');
                    expect_char('=');
                    expect_word("slice");
                    expect_char('(');
                    parse_ident(s->type, sizeof(s->type));
                    expect_char(',');
                    s->index = parse_expr();
                    expect_char(',');
                    s->e = parse_expr();
                    expect_char(')');
                    expect_char(';');
                    s->kind = S_SLICE_INIT;
                } else {
                    parse_ident(s->type, sizeof(s->type));
                    expect_char(';');
                    s->kind = S_SVAR_DECL;
                }
            } else {
                expect_char('=');
                const char *save = P;
                char et[64], vn[64];
                skip();
                parse_ident(et, sizeof(et));
                skip();
                if (*P == '.') {
                    P++;
                    parse_ident(vn, sizeof(vn));
                    int ei = find_enum(et);
                    int tag = (ei >= 0) ? find_variant(ei, vn) : -1;
                    if (ei >= 0 && tag >= 0) {
                        memcopy(s->type, et, (u32)slen(et) + 1);
                        s->variant = tag;
                        s->has_payload = 0;
                        s->e = -1;
                        skip();
                        if (*P == '(') {
                            P++;
                            s->e = parse_expr();
                            expect_char(')');
                            s->has_payload = 1;
                        }
                        expect_char(';');
                        s->kind = S_ENUM_LET;
                    } else {
                        P = save;
                        s->e = parse_expr();
                        expect_char(';');
                        s->kind = S_LET;
                    }
                } else {
                    P = save;
                    s->e = parse_expr();
                    expect_char(';');
                    s->kind = S_LET;
                }
            }
        } else if (at_word("if")) {
            P += 2;
            s->e = parse_expr();
            parse_block(&s->b0, &s->b1);
            if (at_word("else")) {
                P += 4;
                parse_block(&s->e0, &s->e1);
            }
            s->kind = S_IF;
        } else if (at_word("while")) {
            P += 5;
            s->e = parse_expr();
            parse_block(&s->b0, &s->b1);
            s->kind = S_WHILE;
        } else if (at_word("match")) {
            P += 5;
            parse_ident(s->name, sizeof(s->name));
            expect_char('{');
            s->arm0 = narm;
            while (!at_char('}')) {
                char et[64], vn[64];
                parse_ident(et, sizeof(et));
                expect_char('.');
                parse_ident(vn, sizeof(vn));
                int ei = find_enum(et);
                if (ei < 0) die("match: unknown enum");
                int tag = find_variant(ei, vn);
                if (tag < 0) die("match: unknown variant");
                skip();
                int has_bind = 0;
                char bind[64];
                bind[0] = 0;
                if (*P == '(') {
                    P++;
                    parse_ident(bind, sizeof(bind));
                    expect_char(')');
                    has_bind = 1;
                    skip();
                }
                if (!(P[0] == '=' && P[1] == '>')) die("match: expected =>");
                P += 2;
                if (narm >= MAX_ARMS) die("too many match arms");
                int b0, b1;
                parse_block(&b0, &b1);
                arms[narm].tag = tag;
                arms[narm].b0 = b0;
                arms[narm].b1 = b1;
                arms[narm].has_bind = has_bind;
                memcopy(arms[narm].bind, bind, (u32)slen(bind) + 1);
                narm++;
                if (at_char(',')) P++;
            }
            expect_char('}');
            s->armn = narm - s->arm0;
            s->kind = S_MATCH;
        } else if (at_word("write")) {
            P += 5;
            expect_char('(');
            parse_string(s->str, sizeof(s->str), &s->len);
            expect_char(')');
            expect_char(';');
            s->kind = S_WRITE;
        } else if (at_word("return")) {
            P += 6;
            s->e = parse_expr();
            expect_char(';');
            s->kind = S_RETURN;
        } else if (at_word("break")) {
            P += 5;
            expect_char(';');
            s->kind = S_BREAK;
        } else if (at_word("continue")) {
            P += 8;
            expect_char(';');
            s->kind = S_CONTINUE;
        } else if (at_word("read_file") || at_word("write_file")) {
            s->e = parse_expr();
            expect_char(';');
            s->kind = S_EXPR;
        } else {
            parse_ident(s->name, sizeof(s->name));
            skip();
            if (*P == '[') {
                P++;
                s->index = parse_expr();
                expect_char(']');
                expect_char('=');
                s->e = parse_expr();
                expect_char(';');
                s->kind = S_INDEX_ASSIGN;
            } else if (*P == '.') {
                P++;
                parse_ident(s->field, sizeof(s->field));
                expect_char('=');
                s->e = parse_expr();
                expect_char(';');
                s->kind = S_FIELD_ASSIGN;
            } else {
                expect_char('=');
                s->e = parse_expr();
                expect_char(';');
                s->kind = S_ASSIGN;
            }
        }
    }
    expect_char('}');
    *start = head;
    *end = tail;
}

static void parse_enum_decl(void) {
    expect_word("enum");
    if (nenums >= MAX_ENUMS) die("too many enums");
    struct EnumDef *d = &enums[nenums];
    memzero(d, sizeof(*d));
    parse_ident(d->name, sizeof(d->name));
    expect_char('{');
    while (!at_char('}')) {
        if (d->n >= MAX_VARIANTS) die("too many variants");
        parse_ident(d->variants[d->n], sizeof(d->variants[0]));
        d->payload[d->n] = 0;
        skip();
        if (*P == '(') {
            P++;
            expect_word("Int");
            expect_char(')');
            d->payload[d->n] = 1;
        }
        d->n++;
        if (!at_char(',')) break;
        P++;
    }
    expect_char('}');
    nenums++;
}

static void parse_struct_decl(void) {
    expect_word("struct");
    if (nstructs >= MAX_STRUCTS) die("too many structs");
    struct StructDef *d = &structs[nstructs];
    memzero(d, sizeof(*d));
    parse_ident(d->name, sizeof(d->name));
    expect_char('{');
    while (!at_char('}')) {
        if (d->nfields >= MAX_FIELDS) die("too many fields");
        struct FieldDef *f = &d->fields[d->nfields];
        parse_ident(f->name, sizeof(f->name));
        expect_char(':');
        if (at_word("U8")) { P += 2; f->elem = 1; }
        else { expect_word("Int"); f->elem = 8; }
        f->off = d->size;
        d->size += (u32)f->elem;
        d->nfields++;
        if (!at_char(',')) break;
        P++;
    }
    expect_char('}');
    nstructs++;
}

static void parse_program(void) {
    for (;;) {
        skip();
        if (!*P) break;
        if (at_word("enum")) { parse_enum_decl(); continue; }
        if (at_word("struct")) { parse_struct_decl(); continue; }
        expect_word("fn");
        if (nfuncs >= MAX_FUNCS) die("too many functions");
        struct Func *f = &funcs[nfuncs];
        memzero(f, sizeof(*f));
        parse_ident(f->name, sizeof(f->name));
        expect_char('(');
        while (!at_char(')')) {
            if (f->nparams >= 6) die("too many parameters");
            parse_ident(f->params[f->nparams], sizeof(f->params[0]));
            expect_char(':');
            if (at_word("Int")) { P += 3; f->param_elem[f->nparams] = 0; }
            else if (at_word("Slice")) {
                P += 5;
                expect_char('[');
                if (at_word("U8")) { P += 2; f->param_elem[f->nparams] = 1; }
                else { expect_word("Int"); f->param_elem[f->nparams] = 8; }
                expect_char(']');
            } else {
                die("unsupported parameter type");
            }
            f->nparams++;
            if (!at_char(',')) break;
            P++;
        }
        expect_char(')');
        expect_char('-');
        expect_char('>');
        expect_word("Int");
        current_fn = nfuncs;
        parse_block(&f->b0, &f->b1);
        nfuncs++;
    }
    if (nfuncs == 0) die("no functions");
}

/* ---------- codegen ---------- */

static int add_lit(const char *s, u32 len) {
    if (str_count >= MAX_STRS) die("too many strings");
    int i = str_count++;
    str_off[i] = dlen;
    str_len[i] = len;
    memcopy(data + dlen, s, len);
    dlen += len;
    return i;
}

static void emit1(u8 b) {
    if (clen >= CODE_MAX) die("code too large");
    code[clen++] = b;
}

static void emit4(u32 v) {
    emit1((u8)(v & 0xff));
    emit1((u8)((v >> 8) & 0xff));
    emit1((u8)((v >> 16) & 0xff));
    emit1((u8)((v >> 24) & 0xff));
}

static void emit8(u64 v) {
    for (int i = 0; i < 8; i++) emit1((u8)((v >> (8 * i)) & 0xff));
}

static int memcmp_str(const char *a, const char *b);

static int var_slot(const char *name, int create) {
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

    for (int i = 0; i < var_count; i++)
        if (memcmp_str(var_names[i], key)) return i;
    if (!create) die("unknown variable");
    if (var_count >= MAX_VARS) die("too many variables");
    memcopy(var_names[var_count], key, (u32)slen(key) + 1);
    return var_count++;
}

/* tiny strcmp without libc: returns 1 on equal */
static int memcmp_str(const char *a, const char *b) {
    while (*a && *b) {
        if (*a != *b) return 0;
        a++; b++;
    }
    return *a == *b;
}

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
}

static void emit_var_load(int var) {
    emit1(0x48); emit1(0x8b); emit1(0x05);
    if (nvar_patch >= MAX_PATCH) die("too many patches");
    var_patch[nvar_patch].pos = clen;
    var_patch[nvar_patch].var = var;
    var_patch[nvar_patch].store = 0;
    nvar_patch++;
    emit4(0);
}

static void emit_var_store(int var) {
    emit1(0x48); emit1(0x89); emit1(0x05);
    if (nvar_patch >= MAX_PATCH) die("too many patches");
    var_patch[nvar_patch].pos = clen;
    var_patch[nvar_patch].var = var;
    var_patch[nvar_patch].store = 1;
    nvar_patch++;
    emit4(0);
}

static void emit_jump_cond(u32 target);
static void emit_jump_cond_nz(u32 target);
static void emit_jump(u32 target);

static int find_func(const char *name) {
    for (int i = 0; i < nfuncs; i++)
        if (memcmp_str(funcs[i].name, name)) return i;
    return -1;
}

static void emit_expr(int idx) {
    struct Expr *e = &exprs[idx];
    switch (e->kind) {
    case E_NUM:
        emit1(0x48); emit1(0xb8); emit8(e->val);
        break;
    case E_VAR: {
        int slot = var_slot(e->name, 0);
        if (slot < 0) {
            int ev = evar_slot(e->name, 0, 0);
            if (ev < 0) die("unknown variable");
            emit1(0x48); emit1(0x8b); emit1(0x05);
            if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
            struct_patch[nstruct_patch].pos = clen;
            struct_patch[nstruct_patch].off = evars[ev].off;
            nstruct_patch++;
            emit4(0);
            break;
        }
        emit_var_load(slot);
        break;
    }
    case E_NEG:
        emit_expr(e->a);
        emit1(0x48); emit1(0xf7); emit1(0xd8); /* neg rax */
        break;
    case E_SLICE_LEN: {
        int si = slice_slot(e->name, 0, 0);
        if (si < 0) die("unknown slice");
        emit1(0x48); emit1(0x8b); emit1(0x05);
        if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
        struct_patch[nstruct_patch].pos = clen;
        struct_patch[nstruct_patch].off = slices[si].off + 8;
        nstruct_patch++;
        emit4(0);
        break;
    }
    case E_AND: {
        emit_expr(e->a);
        emit1(0x48); emit1(0x85); emit1(0xc0);
        int p_false = njump_patch;
        emit_jump_cond(0);
        emit_expr(e->b);
        emit1(0x48); emit1(0x85); emit1(0xc0);
        emit1(0x0f); emit1(0x95); emit1(0xc0);
        emit1(0x48); emit1(0x0f); emit1(0xb6); emit1(0xc0);
        int p_end = njump_patch;
        emit_jump(0);
        u32 f = clen;
        jump_patch[p_false].target = f;
        emit1(0x48); emit1(0x31); emit1(0xc0);
        u32 en = clen;
        jump_patch[p_end].target = en;
        break;
    }
    case E_OR: {
        emit_expr(e->a);
        emit1(0x48); emit1(0x85); emit1(0xc0);
        int p_true = njump_patch;
        emit_jump_cond_nz(0);
        emit_expr(e->b);
        emit1(0x48); emit1(0x85); emit1(0xc0);
        emit1(0x0f); emit1(0x95); emit1(0xc0);
        emit1(0x48); emit1(0x0f); emit1(0xb6); emit1(0xc0);
        int p_end = njump_patch;
        emit_jump(0);
        u32 t = clen;
        jump_patch[p_true].target = t;
        emit1(0x48); emit1(0xb8); emit8(1);
        u32 en = clen;
        jump_patch[p_end].target = en;
        break;
    }
    case E_FIELD: {
        int vi = svar_slot(e->name, 0, 0);
        if (vi < 0) {
            int si = slice_slot(e->name, 0, 0);
            if (si >= 0 && same_str(e->field, "len")) {
                emit1(0x48); emit1(0x8b); emit1(0x05);
                if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
                struct_patch[nstruct_patch].pos = clen;
                struct_patch[nstruct_patch].off = slices[si].off + 8;
                nstruct_patch++;
                emit4(0);
                break;
            }
            die("unknown field");
        }
        int fi = find_field(svars[vi].sidx, e->field);
        if (fi < 0) die("unknown field");
        u32 off = svars[vi].off + structs[svars[vi].sidx].fields[fi].off;
        if (structs[svars[vi].sidx].fields[fi].elem == 8) {
            emit1(0x48); emit1(0x8b); emit1(0x05);
        } else {
            emit1(0x0f); emit1(0xb6); emit1(0x05);
        }
        if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
        struct_patch[nstruct_patch].pos = clen;
        struct_patch[nstruct_patch].off = off;
        nstruct_patch++;
        emit4(0);
        break;
    }
    case E_INDEX: {
        int si = slice_slot(e->name, 0, 0);
        if (si >= 0) {
            emit_expr(e->a);
            emit1(0x48); emit1(0x8b); emit1(0x0d);
            if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
            struct_patch[nstruct_patch].pos = clen;
            struct_patch[nstruct_patch].off = slices[si].off;
            nstruct_patch++;
            emit4(0);
            if (slices[si].elem == 8) {
                emit1(0x48); emit1(0x8d); emit1(0x0c); emit1(0xc1);
                emit1(0x48); emit1(0x8b); emit1(0x01);
            } else {
                emit1(0x48); emit1(0x01); emit1(0xc1);
                emit1(0x0f); emit1(0xb6); emit1(0x01);
            }
            break;
        }
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
    case E_CALL: {
        if (same_str(e->name, "read_file") || same_str(e->name, "write_file")) {
            int is_read = same_str(e->name, "read_file");
            if (e->nargs != 3) die("io builtin needs 3 args");
            if (exprs[e->args[0]].kind != E_STR) die("io path must be a string literal");
            if (exprs[e->args[1]].kind != E_VAR) die("io buffer must be an array name");
            int li = add_lit(exprs[e->args[0]].lit, exprs[e->args[0]].litlen);
            int ai = arr_slot(exprs[e->args[1]].name, 0, 0, 0);
            emit_expr(e->args[2]);
            emit1(0x50); /* cap/len */
            emit1(0xb8); emit4(257); /* openat */
            emit1(0xbf); emit4((u32)-100);
            emit1(0x48); emit1(0x8d); emit1(0x35);
            if (nstr_patch >= MAX_PATCH) die("too many string patches");
            str_patch[nstr_patch].pos = clen;
            str_patch[nstr_patch].str = li;
            nstr_patch++;
            emit4(0);
            emit1(0xba); emit4(is_read ? 0u : 0x241u);
            emit1(0x41); emit1(0xba); emit4(0644u);
            emit1(0x0f); emit1(0x05);
            emit1(0x48); emit1(0x89); emit1(0xc7); /* rdi = fd */
            emit1(0x5a); /* rdx = cap/len */
            emit1(0x48); emit1(0x8d); emit1(0x35);
            if (narr_patch >= MAX_PATCH) die("too many array patches");
            arr_patch[narr_patch].pos = clen;
            arr_patch[narr_patch].arr = ai;
            narr_patch++;
            emit4(0);
            emit1(0xb8); emit4(is_read ? 0u : 1u);
            emit1(0x0f); emit1(0x05);
            emit1(0x50); /* n */
            emit1(0xb8); emit4(3); /* close */
            emit1(0x0f); emit1(0x05);
            emit1(0x58); /* rax = n */
            break;
        }
        int fi = find_func(e->name);
        if (fi < 0) die("unknown function");
        if (e->nargs != funcs[fi].nparams) die("argument count mismatch");
        int total = 0;
        for (int i = 0; i < e->nargs; i++) {
            if (funcs[fi].param_elem[i] == 0) {
                emit_expr(e->args[i]);
                emit1(0x50);
                total++;
            } else {
                struct Expr *ae = &exprs[e->args[i]];
                if (ae->kind != E_VAR) die("Slice argument must be a variable");
                int si = slice_slot(ae->name, 0, 0);
                if (si < 0) die("Slice argument is not a slice");
                emit1(0x48); emit1(0x8b); emit1(0x05);
                if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
                struct_patch[nstruct_patch].pos = clen;
                struct_patch[nstruct_patch].off = slices[si].off;
                nstruct_patch++;
                emit4(0);
                emit1(0x50);
                emit1(0x48); emit1(0x8b); emit1(0x05);
                if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
                struct_patch[nstruct_patch].pos = clen;
                struct_patch[nstruct_patch].off = slices[si].off + 8;
                nstruct_patch++;
                emit4(0);
                emit1(0x50);
                total += 2;
            }
        }
        if (total > 6) die("too many argument slots");
        for (int i = total - 1; i >= 0; i--) {
            if (i == 0) emit1(0x5f);
            else if (i == 1) emit1(0x5e);
            else if (i == 2) emit1(0x5a);
            else if (i == 3) emit1(0x59);
            else if (i == 4) { emit1(0x41); emit1(0x58); }
            else { emit1(0x41); emit1(0x59); }
        }
        emit1(0xe8);
        if (ncall_patch >= MAX_PATCH) die("too many calls");
        call_patch[ncall_patch].pos = clen;
        call_patch[ncall_patch].fn_idx = fi;
        ncall_patch++;
        emit4(0);
        break;
    }
    default: {
        emit_expr(e->a);
        emit1(0x50); /* push rax */
        emit_expr(e->b);
        emit1(0x59); /* pop rcx (left) */
        emit1(0x48); emit1(0x91); /* xchg rax, rcx: rax=left, rcx=right */
        switch (e->kind) {
        case E_ADD: emit1(0x48); emit1(0x01); emit1(0xc8); break;
        case E_SUB: emit1(0x48); emit1(0x29); emit1(0xc8); break;
        case E_MUL: emit1(0x48); emit1(0x0f); emit1(0xaf); emit1(0xc1); break;
        case E_DIV:
            emit1(0x48); emit1(0x99);             /* cqo */
            emit1(0x48); emit1(0xf7); emit1(0xf9); /* idiv rcx */
            break;
        case E_MOD:
            emit1(0x48); emit1(0x99);
            emit1(0x48); emit1(0xf7); emit1(0xf9);
            emit1(0x48); emit1(0x89); emit1(0xd0); /* mov rax, rdx */
            break;
        case E_BITAND: emit1(0x48); emit1(0x21); emit1(0xc8); break;
        case E_BITOR:  emit1(0x48); emit1(0x09); emit1(0xc8); break;
        case E_BITXOR: emit1(0x48); emit1(0x31); emit1(0xc8); break;
        case E_SHL:    emit1(0x48); emit1(0xd3); emit1(0xe0); break;
        case E_SHR:    emit1(0x48); emit1(0xd3); emit1(0xf8); break;
        case E_EQ: emit1(0x48); emit1(0x39); emit1(0xc8); emit1(0x0f); emit1(0x94); emit1(0xc0); break;
        case E_NE: emit1(0x48); emit1(0x39); emit1(0xc8); emit1(0x0f); emit1(0x95); emit1(0xc0); break;
        case E_LT: emit1(0x48); emit1(0x39); emit1(0xc8); emit1(0x0f); emit1(0x9c); emit1(0xc0); break;
        case E_LE: emit1(0x48); emit1(0x39); emit1(0xc8); emit1(0x0f); emit1(0x9e); emit1(0xc0); break;
        case E_GT: emit1(0x48); emit1(0x39); emit1(0xc8); emit1(0x0f); emit1(0x9f); emit1(0xc0); break;
        case E_GE: emit1(0x48); emit1(0x39); emit1(0xc8); emit1(0x0f); emit1(0x9d); emit1(0xc0); break;
        default: die("bad expr kind");
        }
        if (e->kind >= E_EQ) {
            emit1(0x48); emit1(0x0f); emit1(0xb6); emit1(0xc0); /* movzx rax, al */
        }
    }
    }
}

static void emit_jump_cond(u32 target) {
    emit1(0x0f); emit1(0x84); /* je rel32 */
    if (njump_patch >= MAX_PATCH) die("too many jumps");
    jump_patch[njump_patch].pos = clen;
    jump_patch[njump_patch].target = target;
    njump_patch++;
    emit4(0);
}

static void emit_jump_cond_nz(u32 target) {
    emit1(0x0f); emit1(0x85);
    if (njump_patch >= MAX_PATCH) die("too many jumps");
    jump_patch[njump_patch].pos = clen;
    jump_patch[njump_patch].target = target;
    njump_patch++;
    emit4(0);
}

static void emit_jump(u32 target) {
    emit1(0xe9);
    if (njump_patch >= MAX_PATCH) die("too many jumps");
    jump_patch[njump_patch].pos = clen;
    jump_patch[njump_patch].target = target;
    njump_patch++;
    emit4(0);
}

static void emit_list(int head);

static void emit_stmt(int i) {
    struct Stmt *s = &stmts[i];
    switch (s->kind) {
    case S_LET:
    case S_ASSIGN: {
        emit_expr(s->e);
        emit_var_store(var_slot(s->name, s->kind == S_LET));
        break;
    }
    case S_WRITE: {
        int si = str_count;
        if (si >= MAX_STRS) die("too many strings");
        str_off[si] = dlen;
        str_len[si] = s->len;
        memcopy(data + dlen, s->str, s->len);
        dlen += s->len;
        str_count++;
        emit1(0xb8); emit4(1);
        emit1(0xbf); emit4(1);
        emit1(0x48); emit1(0x8d); emit1(0x35);
        if (nstr_patch >= MAX_PATCH) die("too many patches");
        str_patch[nstr_patch].pos = clen;
        str_patch[nstr_patch].str = si;
        nstr_patch++;
        emit4(0);
        emit1(0xba); emit4(s->len);
        emit1(0x0f); emit1(0x05);
        break;
    }
    case S_RETURN:
        emit_expr(s->e);
        emit1(0xc3); /* ret */
        break;
    case S_ENUM_LET: {
        int ei = find_enum(s->type);
        if (ei < 0) die("unknown enum type");
        int vi = evar_slot(s->name, 1, ei);
        emit1(0x48); emit1(0xb8); emit8((u64)s->variant);
        emit1(0x48); emit1(0x89); emit1(0x05);
        if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
        struct_patch[nstruct_patch].pos = clen;
        struct_patch[nstruct_patch].off = evars[vi].off;
        nstruct_patch++;
        emit4(0);
        if (s->has_payload) {
            emit_expr(s->e);
            emit1(0x48); emit1(0x89); emit1(0x05);
            if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
            struct_patch[nstruct_patch].pos = clen;
            struct_patch[nstruct_patch].off = evars[vi].off + 8;
            nstruct_patch++;
            emit4(0);
        }
        break;
    }
    case S_MATCH: {
        int vi = evar_slot(s->name, 0, 0);
        if (vi < 0) die("match subject must be enum");
        int end_patch[64];
        int nend = 0;
        for (int k = 0; k < s->armn; k++) {
            struct MatchArm *a = &arms[s->arm0 + k];
            emit1(0x48); emit1(0x8b); emit1(0x05);
            if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
            struct_patch[nstruct_patch].pos = clen;
            struct_patch[nstruct_patch].off = evars[vi].off;
            nstruct_patch++;
            emit4(0);
            emit1(0x48); emit1(0x3d); emit4((u32)a->tag);
            int pnext = njump_patch;
            emit_jump_cond_nz(0);
            if (a->has_bind) {
                int slot = var_slot(a->bind, 1);
                emit1(0x48); emit1(0x8b); emit1(0x05);
                if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
                struct_patch[nstruct_patch].pos = clen;
                struct_patch[nstruct_patch].off = evars[vi].off + 8;
                nstruct_patch++;
                emit4(0);
                emit1(0x48); emit1(0x89); emit1(0x05);
                if (nvar_patch >= MAX_PATCH) die("too many patches");
                var_patch[nvar_patch].pos = clen;
                var_patch[nvar_patch].var = slot;
                var_patch[nvar_patch].store = 1;
                nvar_patch++;
                emit4(0);
            }
            emit_list(a->b0);
            if (nend < 64) {
                end_patch[nend] = njump_patch;
                emit_jump(0);
                nend++;
            }
            u32 next = clen;
            jump_patch[pnext].target = next;
        }
        u32 end = clen;
        for (int k = 0; k < nend; k++) jump_patch[end_patch[k]].target = end;
        break;
    }
    case S_WHILE: {
        u32 start = clen;
        if (loop_depth >= 16) die("loop nest too deep");
        loop_start[loop_depth] = start;
        int depth = loop_depth;
        loop_depth++;
        int bbase = nbreak;
        emit_expr(s->e);
        emit1(0x48); emit1(0x85); emit1(0xc0);
        int p = njump_patch;
        emit_jump_cond(0);
        emit_list(s->b0);
        emit_jump(start);
        u32 end = clen;
        loop_depth--;
        jump_patch[p].target = end;
        for (int k = bbase; k < nbreak; k++)
            if (break_patch[k].depth == depth)
                jump_patch[break_patch[k].jp].target = end;
        break;
    }
    case S_BREAK: {
        if (loop_depth <= 0) die("break outside loop");
        if (nbreak >= MAX_PATCH) die("too many breaks");
        int jp = njump_patch;
        emit_jump(0);
        break_patch[nbreak].jp = jp;
        break_patch[nbreak].depth = loop_depth - 1;
        nbreak++;
        break;
    }
    case S_CONTINUE: {
        if (loop_depth <= 0) die("continue outside loop");
        emit_jump(loop_start[loop_depth - 1]);
        break;
    }
    case S_EXPR:
        emit_expr(s->e);
        break;
    case S_SLICE_INIT: {
        int si = slice_slot(s->name, 1, s->elem);
        int ai = arr_slot(s->type, 0, 0, 0);
        emit_expr(s->index);
        emit1(0x50);
        emit1(0x48); emit1(0x8d); emit1(0x0d);
        if (narr_patch >= MAX_PATCH) die("too many array patches");
        arr_patch[narr_patch].pos = clen;
        arr_patch[narr_patch].arr = ai;
        narr_patch++;
        emit4(0);
        emit1(0x58);
        emit1(0x48); emit1(0x01); emit1(0xc8); /* add rax, rcx */
        emit1(0x48); emit1(0x89); emit1(0x05);
        if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
        struct_patch[nstruct_patch].pos = clen;
        struct_patch[nstruct_patch].off = slices[si].off;
        nstruct_patch++;
        emit4(0);
        emit_expr(s->e);
        emit1(0x48); emit1(0x89); emit1(0x05);
        if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
        struct_patch[nstruct_patch].pos = clen;
        struct_patch[nstruct_patch].off = slices[si].off + 8;
        nstruct_patch++;
        emit4(0);
        break;
    }
    case S_SVAR_DECL: {
        int si = find_struct(s->type);
        if (si < 0) die("unknown struct type");
        svar_slot(s->name, 1, si);
        break;
    }
    case S_FIELD_ASSIGN: {
        int vi = svar_slot(s->name, 0, 0);
        if (vi < 0) die("unknown struct variable");
        int fi = find_field(svars[vi].sidx, s->field);
        if (fi < 0) die("unknown field");
        u32 off = svars[vi].off + structs[svars[vi].sidx].fields[fi].off;
        int elem = structs[svars[vi].sidx].fields[fi].elem;
        emit_expr(s->e);
        if (elem == 8) { emit1(0x48); emit1(0x89); emit1(0x05); }
        else { emit1(0x88); emit1(0x05); }
        if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
        struct_patch[nstruct_patch].pos = clen;
        struct_patch[nstruct_patch].off = off;
        nstruct_patch++;
        emit4(0);
        break;
    }
    case S_ARR:
        arr_slot(s->name, 1, s->elem, s->len);
        break;
    case S_INDEX_ASSIGN: {
        int si = slice_slot(s->name, 0, 0);
        if (si >= 0) {
            emit_expr(s->e);
            emit1(0x50);
            emit_expr(s->index);
            emit1(0x5a);
            emit1(0x48); emit1(0x8b); emit1(0x0d);
            if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
            struct_patch[nstruct_patch].pos = clen;
            struct_patch[nstruct_patch].off = slices[si].off;
            nstruct_patch++;
            emit4(0);
            if (slices[si].elem == 8) {
                emit1(0x48); emit1(0x8d); emit1(0x0c); emit1(0xc1);
                emit1(0x48); emit1(0x89); emit1(0x11);
            } else {
                emit1(0x48); emit1(0x01); emit1(0xc1);
                emit1(0x88); emit1(0x11);
            }
            break;
        }
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
    case S_IF: {
        emit_expr(s->e);
        emit1(0x48); emit1(0x85); emit1(0xc0);
        int p_else = njump_patch;
        emit_jump_cond(0);
        emit_list(s->b0);
        if (s->e0 >= 0) {
            int p_end = njump_patch;
            emit_jump(0);
            u32 else_label = clen;
            jump_patch[p_else].target = else_label;
            emit_list(s->e0);
            u32 end = clen;
            jump_patch[p_end].target = end;
        } else {
            u32 end = clen;
            jump_patch[p_else].target = end;
        }
        break;
    }
    default:
        die("bad stmt kind");
    }
}

static void emit_list(int head) {
    for (int i = head; i >= 0; i = stmts[i].next) emit_stmt(i);
}

static void put16(u8 *p, u32 v) { p[0] = (u8)v; p[1] = (u8)(v >> 8); }
static void put32(u8 *p, u32 v) { for (int i = 0; i < 4; i++) p[i] = (u8)(v >> (8 * i)); }
static void put64(u8 *p, u64 v) { for (int i = 0; i < 8; i++) p[i] = (u8)(v >> (8 * i)); }

static u32 build_elf(void) {
    u32 strlen_total = dlen;
    u32 var_bytes = (u32)var_count * 8u;
    for (u32 i = 0; i < var_bytes; i++) data[dlen++] = 0;

    u64 base = 0x400000ull;
    u64 code_vaddr = base + 120ull;
    u64 data_vaddr = code_vaddr + (u64)clen;

    for (int i = 0; i < nvar_patch; i++) {
        u32 pos = var_patch[i].pos;
        u64 instr_end = code_vaddr + (u64)pos + 4ull;
        u64 addr = data_vaddr + (u64)strlen_total + (u64)var_patch[i].var * 8ull;
        i64 disp = (i64)addr - (i64)instr_end;
        put32(code + pos, (u32)(i32)disp);
    }
    for (int i = 0; i < nstr_patch; i++) {
        u32 pos = str_patch[i].pos;
        u64 instr_end = code_vaddr + (u64)pos + 4ull;
        u64 addr = data_vaddr + (u64)str_off[str_patch[i].str];
        i64 disp = (i64)addr - (i64)instr_end;
        put32(code + pos, (u32)(i32)disp);
    }
    for (int i = 0; i < njump_patch; i++) {
        u32 pos = jump_patch[i].pos;
        i64 disp = (i64)jump_patch[i].target - (i64)(pos + 4u);
        put32(code + pos, (u32)(i32)disp);
    }
    for (int i = 0; i < ncall_patch; i++) {
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
    }
    for (int i = 0; i < nstruct_patch; i++) {
        u32 pos = struct_patch[i].pos;
        u64 instr_end = code_vaddr + (u64)pos + 4ull;
        u64 addr = data_vaddr + (u64)struct_patch[i].off;
        i64 disp = (i64)addr - (i64)instr_end;
        put32(code + pos, (u32)(i32)disp);
    }

    u32 total = 120u + clen + dlen;
    memzero(out, 120);
    out[0] = 0x7f; out[1] = 'E'; out[2] = 'L'; out[3] = 'F';
    out[4] = 2; out[5] = 1; out[6] = 1;
    put16(out + 16, 2);
    put16(out + 18, 62);
    put32(out + 20, 1);
    put64(out + 24, code_vaddr);
    put64(out + 32, 64);
    put64(out + 40, 0);
    put32(out + 48, 0);
    put16(out + 52, 64);
    put16(out + 54, 56);
    put16(out + 56, 1);
    put16(out + 58, 0);
    put16(out + 60, 0);
    put16(out + 62, 0);

    put32(out + 64, 1);
    put32(out + 68, 7); /* R | W | X: vars live in this segment */
    put64(out + 72, 0);
    put64(out + 80, base);
    put64(out + 88, base);
    put64(out + 96, total);
    put64(out + 104, total);
    put64(out + 112, 0x1000);

    memcopy(out + 120, code, clen);
    memcopy(out + 120 + clen, data, dlen);
    return total;
}

static int read_file(const char *path, char *buf, u32 cap) {
#ifdef _WIN32
    FILE *f = fopen(path, "rb");
    if (!f) return -1;
    size_t n = fread(buf, 1, cap - 1, f);
    fclose(f);
    if (n >= cap) return -1;
    buf[n] = 0;
    return (int)n;
#else
    long fd = syscall4(257, -100, (long)path, 0, 0);
    if (fd < 0) return -1;
    long n = syscall3(0, fd, (long)buf, (long)(cap - 1));
    syscall1(3, fd);
    if (n < 0) return -1;
    buf[n] = 0;
    return (int)n;
#endif
}

static int write_file(const char *path, const u8 *buf, u32 len) {
#ifdef _WIN32
    FILE *f = fopen(path, "wb");
    if (!f) return -1;
    size_t n = fwrite(buf, 1, len, f);
    fclose(f);
    return n == len ? 0 : -1;
#else
    long fd = syscall4(257, -100, (long)path, 0x241, 0644);
    if (fd < 0) return -1;
    long n = syscall3(1, fd, (long)buf, (long)len);
    syscall1(3, fd);
    return n == (long)len ? 0 : -1;
#endif
}

#include "interp.inc"

int seed_main(int argc, char **argv) {
    const char *in = 0;
    const char *out_path = "a.out";
    int run_mode = 0;
    for (int i = 1; i < argc; i++) {
        if (same_str(argv[i], "--run")) run_mode = 1;
        else if (argv[i][0] == '-' && argv[i][1] == 'o') {
            if (argv[i][2]) out_path = argv[i] + 2;
            else if (i + 1 < argc) out_path = argv[++i];
        } else {
            in = argv[i];
        }
    }
    if (!in) die("usage: seed [--run] <input.ls> [-o output]");
    if (read_file(in, inbuf, IN_MAX) < 0) die("cannot read input");

    P = inbuf;
    parse_program();
    if (run_mode) return run_program();

    int main_fi = find_func("main");
    if (main_fi < 0) die("missing main");

    emit1(0xe8);
    if (ncall_patch >= MAX_PATCH) die("too many calls");
    call_patch[ncall_patch].pos = clen;
    call_patch[ncall_patch].fn_idx = main_fi;
    ncall_patch++;
    emit4(0);
    emit1(0x48); emit1(0x89); emit1(0xc7);
    emit1(0xb8); emit4(60);
    emit1(0x0f); emit1(0x05);

    for (int fi = 0; fi < nfuncs; fi++) {
        current_fn = fi;
        func_label[fi] = clen;
        int reg = 0;
        for (int pi = 0; pi < funcs[fi].nparams; pi++) {
            if (funcs[fi].param_elem[pi] == 0) {
                int slot = var_slot(funcs[fi].params[pi], 1);
                if (reg == 0) { emit1(0x48); emit1(0x89); emit1(0x3d); }
                else if (reg == 1) { emit1(0x48); emit1(0x89); emit1(0x35); }
                else if (reg == 2) { emit1(0x48); emit1(0x89); emit1(0x15); }
                else if (reg == 3) { emit1(0x48); emit1(0x89); emit1(0x0d); }
                else if (reg == 4) { emit1(0x4c); emit1(0x89); emit1(0x05); }
                else { emit1(0x4c); emit1(0x89); emit1(0x0d); }
                if (nvar_patch >= MAX_PATCH) die("too many patches");
                var_patch[nvar_patch].pos = clen;
                var_patch[nvar_patch].var = slot;
                var_patch[nvar_patch].store = 1;
                nvar_patch++;
                emit4(0);
                reg++;
            } else {
                int si = slice_slot(funcs[fi].params[pi], 1, funcs[fi].param_elem[pi]);
                for (int k = 0; k < 2; k++) {
                    if (reg == 0) { emit1(0x48); emit1(0x89); emit1(0x3d); }
                    else if (reg == 1) { emit1(0x48); emit1(0x89); emit1(0x35); }
                    else if (reg == 2) { emit1(0x48); emit1(0x89); emit1(0x15); }
                    else if (reg == 3) { emit1(0x48); emit1(0x89); emit1(0x0d); }
                    else if (reg == 4) { emit1(0x4c); emit1(0x89); emit1(0x05); }
                    else { emit1(0x4c); emit1(0x89); emit1(0x0d); }
                    if (nstruct_patch >= MAX_PATCH) die("too many struct patches");
                    struct_patch[nstruct_patch].pos = clen;
                    struct_patch[nstruct_patch].off = slices[si].off + (u32)k * 8u;
                    nstruct_patch++;
                    emit4(0);
                    reg++;
                }
            }
        }
        emit_list(funcs[fi].b0);
        emit1(0x48); emit1(0x31); emit1(0xc0);
        emit1(0xc3);
    }

    u32 total = build_elf();
    if (write_file(out_path, out, total) != 0) die("cannot write output");
    return 0;
}

#ifdef _WIN32
int main(int argc, char **argv) { (void)argc; (void)argv; return seed_main(argc, argv); }
#else
__asm__(
    ".global _start\n"
    ".type _start,@function\n"
    "_start:\n"
    "  xor %rbp, %rbp\n"
    "  mov (%rsp), %rdi\n"
    "  lea 8(%rsp), %rsi\n"
    "  and $-16, %rsp\n"
    "  call seed_main\n"
    "  mov %eax, %edi\n"
    "  mov $60, %eax\n"
    "  syscall\n"
    ".size _start, .-_start\n"
);
#endif
