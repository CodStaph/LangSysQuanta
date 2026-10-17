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
    E_EQ, E_NE, E_LT, E_LE, E_GT, E_GE, E_NEG
};

struct Expr {
    int kind;
    u32 val;
    int a, b;
    char name[64];
};

enum { S_LET, S_ASSIGN, S_WRITE, S_RETURN, S_WHILE, S_IF };

struct Stmt {
    int kind;
    int e;            /* expr index */
    int b0, b1;       /* then body */
    int e0, e1;       /* else body */
    char name[64];
    char str[512];
    u32 len;
};

static struct Expr exprs[MAX_EXPR];
static int nexpr;
static struct Stmt stmts[MAX_STMT];
static int nstmt;

/* ---------- variables / strings ---------- */

static char var_names[MAX_VARS][64];
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

static int parse_primary(void) {
    skip();
    if (at_char('(')) {
        P++;
        int e = parse_expr();
        expect_char(')');
        return e;
    }
    if (*P >= '0' && *P <= '9') {
        int e = new_expr(E_NUM);
        exprs[e].val = parse_number();
        return e;
    }
    int e = new_expr(E_VAR);
    parse_ident(exprs[e].name, sizeof(exprs[e].name));
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

static int parse_cmp(void) {
    int e = parse_add();
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
        int r = parse_add();
        int n = new_expr(kind);
        exprs[n].a = e;
        exprs[n].b = r;
        e = n;
    }
    return e;
}

static int parse_expr(void) { return parse_cmp(); }

/* ---------- statements ---------- */

static void parse_block(int *start, int *end) {
    expect_char('{');
    *start = nstmt;
    while (!at_char('}')) {
        if (nstmt >= MAX_STMT) die("too many statements");
        int idx = nstmt++;
        struct Stmt *s = &stmts[idx];
        memzero(s, sizeof(*s));
        s->e = -1;
        s->b0 = s->b1 = s->e0 = s->e1 = -1;

        if (at_word("let")) {
            P += 3;
            parse_ident(s->name, sizeof(s->name));
            expect_char('=');
            s->e = parse_expr();
            expect_char(';');
            s->kind = S_LET;
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
        } else {
            parse_ident(s->name, sizeof(s->name));
            expect_char('=');
            s->e = parse_expr();
            expect_char(';');
            s->kind = S_ASSIGN;
        }
    }
    expect_char('}');
    *end = nstmt;
}

static void parse_program(void) {
    expect_word("fn");
    expect_word("main");
    expect_char('(');
    expect_char(')');
    expect_char('-');
    expect_char('>');
    expect_word("Int");
    parse_block(&main_b0, &main_b1);
    skip();
    if (*P) die("trailing input");
}

/* ---------- codegen ---------- */

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
    for (int i = 0; i < var_count; i++)
        if (slen(var_names[i]) == slen(name) && memcmp_str(var_names[i], name)) return i;
    if (!create) die("unknown variable");
    if (var_count >= MAX_VARS) die("too many variables");
    memcopy(var_names[var_count], name, slen(name) + 1);
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

static void emit_expr(int idx) {
    struct Expr *e = &exprs[idx];
    switch (e->kind) {
    case E_NUM:
        emit1(0x48); emit1(0xb8); emit8(e->val);
        break;
    case E_VAR:
        emit_var_load(var_slot(e->name, 0));
        break;
    case E_NEG:
        emit_expr(e->a);
        emit1(0x48); emit1(0xf7); emit1(0xd8); /* neg rax */
        break;
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

static void emit_jump(u32 target) {
    emit1(0xe9);
    if (njump_patch >= MAX_PATCH) die("too many jumps");
    jump_patch[njump_patch].pos = clen;
    jump_patch[njump_patch].target = target;
    njump_patch++;
    emit4(0);
}

static void emit_stmts(int start, int end);

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
        emit1(0x48); emit1(0x89); emit1(0xc7); /* mov rdi, rax */
        emit1(0xb8); emit4(60);
        emit1(0x0f); emit1(0x05);
        break;
    case S_WHILE: {
        u32 start = clen;
        emit_expr(s->e);
        emit1(0x48); emit1(0x85); emit1(0xc0); /* test rax, rax */
        int p = njump_patch;
        emit_jump_cond(0); /* patch later */
        emit_stmts(s->b0, s->b1);
        emit_jump(start);
        u32 end = clen;
        jump_patch[p].target = end;
        break;
    }
    case S_IF: {
        emit_expr(s->e);
        emit1(0x48); emit1(0x85); emit1(0xc0);
        int p_else = njump_patch;
        emit_jump_cond(0);
        emit_stmts(s->b0, s->b1);
        if (s->e0 >= 0) {
            int p_end = njump_patch;
            emit_jump(0);
            u32 else_label = clen;
            jump_patch[p_else].target = else_label;
            emit_stmts(s->e0, s->e1);
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

static void emit_stmts(int start, int end) {
    for (int i = start; i < end; i++) emit_stmt(i);
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

int seed_main(int argc, char **argv) {
    const char *in = 0;
    const char *out_path = "a.out";
    for (int i = 1; i < argc; i++) {
        if (argv[i][0] == '-' && argv[i][1] == 'o') {
            if (argv[i][2]) out_path = argv[i] + 2;
            else if (i + 1 < argc) out_path = argv[++i];
        } else {
            in = argv[i];
        }
    }
    if (!in) die("usage: seed <input.ls> [-o output]");
    if (read_file(in, inbuf, IN_MAX) < 0) die("cannot read input");

    P = inbuf;
    parse_program();

    /* Emit only the top-level main block; nested blocks live after it. */
    emit_stmts(main_b0, main_b1);
    emit1(0xb8); emit4(60);
    emit1(0xbf); emit4(0);
    emit1(0x0f); emit1(0x05);

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
