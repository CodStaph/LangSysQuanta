/*
 * seed.c — bootstrap stage0 for LangSysQuanta.
 *
 * M0 scope: parse a tiny B-LS program:
 *     fn main() -> Int { write("..."); return N; }
 * and emit a static x86_64 Linux ELF that performs write(2) + exit(2).
 *
 * No libc on Linux, no assembler, no linker, no LLVM.
 * Windows is a developer convenience only (CRT file I/O); the Linux build
 * uses raw syscalls. See bootstrap/README.md.
 */

typedef unsigned char u8;
typedef unsigned int u32;
typedef unsigned long long u64;
typedef int i32;
typedef long long i64;

#ifdef _WIN32
/* Windows is a developer convenience host, not the target. */
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
#define CODE_MAX 65536u
#define DATA_MAX 65536u
#define OUT_MAX (IN_MAX + CODE_MAX + DATA_MAX)
#define MAX_WRITES 32
#define MAX_STR 512

static char inbuf[IN_MAX];
static u8 code[CODE_MAX];
static u32 clen;
static u8 data[DATA_MAX];
static u32 dlen;
static u8 out[OUT_MAX];

struct Write {
    char s[MAX_STR];
    u32 len;
};

static struct Write writes[MAX_WRITES];
static u32 nwrites;
static u32 ret_value;
static u32 disp_pos[MAX_WRITES];

static const char *P;
static int line_no = 1;

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
#else
    char buf[16];
    int n = 0;
    u32 v = (u32)line_no;
    if (v == 0) buf[n++] = '0';
    char tmp[16];
    int t = 0;
    while (v) {
        tmp[t++] = (char)('0' + (v % 10));
        v /= 10;
    }
    while (t) buf[n++] = tmp[--t];
    buf[n++] = '\n';
    syscall3(1, 2, (long)buf, (long)n);
#endif
    for (;;) {
#ifdef _WIN32
        exit(1);
#else
        syscall1(60, 1);
#endif
    }
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

static void parse_string(struct Write *w) {
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
        if (n + 1 >= MAX_STR) die("string too long");
        w->s[n++] = c;
    }
    if (*P != '"') die("unterminated string");
    P++;
    w->s[n] = 0;
    w->len = n;
}

static void parse_program(void) {
    expect_word("fn");
    expect_word("main");
    expect_char('(');
    expect_char(')');
    expect_char('-');
    expect_char('>');
    expect_word("Int");
    expect_char('{');

    while (!at_char('}')) {
        if (at_word("write")) {
            P += 5;
            expect_char('(');
            if (nwrites >= MAX_WRITES) die("too many writes");
            parse_string(&writes[nwrites]);
            expect_char(')');
            expect_char(';');
            nwrites++;
        } else if (at_word("return")) {
            P += 6;
            ret_value = parse_number();
            expect_char(';');
        } else {
            die("unexpected statement");
        }
    }
    expect_char('}');
    skip();
    if (*P) die("trailing input");
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

static void emit_writes(void) {
    for (u32 i = 0; i < nwrites; i++) {
        emit1(0xb8); /* mov eax, 1 (write) */
        emit4(1);
        emit1(0xbf); /* mov edi, 1 (stdout) */
        emit4(1);
        emit1(0x48); /* lea rsi, [rip + disp32] */
        emit1(0x8d);
        emit1(0x35);
        disp_pos[i] = clen;
        emit4(0);
        emit1(0xba); /* mov edx, len */
        emit4(writes[i].len);
        emit1(0x0f); /* syscall */
        emit1(0x05);
    }

    emit1(0xb8); /* mov eax, 60 (exit) */
    emit4(60);
    emit1(0xbf); /* mov edi, ret */
    emit4(ret_value);
    emit1(0x0f);
    emit1(0x05);
}

static void put16(u8 *p, u32 v) {
    p[0] = (u8)(v & 0xff);
    p[1] = (u8)((v >> 8) & 0xff);
}

static void put32(u8 *p, u32 v) {
    p[0] = (u8)(v & 0xff);
    p[1] = (u8)((v >> 8) & 0xff);
    p[2] = (u8)((v >> 16) & 0xff);
    p[3] = (u8)((v >> 24) & 0xff);
}

static void put64(u8 *p, u64 v) {
    for (int i = 0; i < 8; i++) p[i] = (u8)((v >> (8 * i)) & 0xff);
}

static u32 build_elf(void) {
    for (u32 i = 0; i < nwrites; i++) {
        memcopy(data + dlen, writes[i].s, writes[i].len);
        dlen += writes[i].len;
    }
    /* Recompute offsets deterministically and patch RIP displacements. */
    u32 data_off = 0;
    u64 base = 0x400000ull;
    u64 code_vaddr = base + 120ull;
    for (u32 i = 0; i < nwrites; i++) {
        u64 instr_end = code_vaddr + (u64)disp_pos[i] + 4ull;
        u64 msg_vaddr = code_vaddr + (u64)clen + (u64)data_off;
        i64 disp = (i64)msg_vaddr - (i64)instr_end;
        put32(code + disp_pos[i], (u32)(i32)disp);
        data_off += writes[i].len;
    }

    u32 total = 120u + clen + dlen;
    memzero(out, 120);
    out[0] = 0x7f;
    out[1] = 'E';
    out[2] = 'L';
    out[3] = 'F';
    out[4] = 2; /* ELFCLASS64 */
    out[5] = 1; /* little endian */
    out[6] = 1; /* version */
    put16(out + 16, 2);          /* e_type = ET_EXEC */
    put16(out + 18, 62);         /* e_machine = x86_64 */
    put32(out + 20, 1);          /* e_version */
    put64(out + 24, code_vaddr); /* e_entry */
    put64(out + 32, 64);         /* e_phoff */
    put64(out + 40, 0);          /* e_shoff */
    put32(out + 48, 0);          /* e_flags */
    put16(out + 52, 64);         /* e_ehsize */
    put16(out + 54, 56);         /* e_phentsize */
    put16(out + 56, 1);          /* e_phnum */
    put16(out + 58, 0);          /* e_shentsize */
    put16(out + 60, 0);          /* e_shnum */
    put16(out + 62, 0);          /* e_shstrndx */

    put32(out + 64, 1);        /* PT_LOAD */
    put32(out + 68, 5);        /* PF_R | PF_X */
    put64(out + 72, 0);        /* p_offset */
    put64(out + 80, base);     /* p_vaddr */
    put64(out + 88, base);     /* p_paddr */
    put64(out + 96, total);    /* p_filesz */
    put64(out + 104, total);   /* p_memsz */
    put64(out + 112, 0x1000);  /* p_align */

    memcopy(out + 120, code, clen);
    memcopy(out + 120 + clen, data, dlen);
    return total;
}

static int read_file(const char *path, char *buf, u32 cap) {
#ifdef _WIN32
    void *f = fopen(path, "rb");
    if (!f) return -1;
    usize n = fread(buf, 1, cap - 1, f);
    fclose(f);
    if (n >= cap) return -1;
    buf[n] = 0;
    return (int)n;
#else
    long fd = syscall4(257, -100, (long)path, 0, 0); /* openat */
    if (fd < 0) return -1;
    long n = syscall3(0, fd, (long)buf, (long)(cap - 1)); /* read */
    syscall1(3, fd);                                      /* close */
    if (n < 0) return -1;
    buf[n] = 0;
    return (int)n;
#endif
}

static int write_file(const char *path, const u8 *buf, u32 len) {
#ifdef _WIN32
    void *f = fopen(path, "wb");
    if (!f) return -1;
    usize n = fwrite(buf, 1, len, f);
    fclose(f);
    return n == len ? 0 : -1;
#else
    long fd = syscall4(257, -100, (long)path, 0x241, 0644); /* O_WRONLY|O_CREAT|O_TRUNC */
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
    emit_writes();
    u32 total = build_elf();
    if (write_file(out_path, out, total) != 0) die("cannot write output");
    return 0;
}

#ifdef _WIN32
int main(int argc, char **argv) { return seed_main(argc, argv); }
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
