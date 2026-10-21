//! Surface parser and semantic checker for the checked L-Sys subset.
//!
//! The subset is deliberately small but exercises the Stage-2 obligations this
//! milestone targets:
//!
//! * `region R { ... }` scopes and `Buffer[T]` ownership/lifetime checks;
//! * generic functions/types with several parameters, trait bounds and full
//!   (nested, occurs-checked) unification;
//! * `val`/`ref` parameter modes, `eff(...)` effects, `requires`/`ensures`
//!   contracts and `comptime` blocks;
//! * fallible `Buffer.try_new` plus a statically simulated arena budget with
//!   LIFO reclamation at region/function exit.
//!
//! It is intentionally *not* a full L-Sys parser: no modules, traits/impls,
//! match, loops over generic collections, or code generation.

use std::collections::{BTreeMap, BTreeSet};
use std::fmt;

use crate::arena::{Allocation, Arena, ArenaReport};
use crate::state::Place;
use crate::state::{Region, RegionTree};

// ---------------------------------------------------------------------------
// Diagnostics and public entry points
// ---------------------------------------------------------------------------

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Span {
    pub start: usize,
    pub end: usize,
}

impl Span {
    fn new(start: usize, end: usize) -> Self {
        Self { start, end }
    }
    fn join(self, other: Span) -> Span {
        Span::new(self.start.min(other.start), self.end.max(other.end))
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Diagnostic {
    pub code: &'static str,
    pub span: Span,
    pub message: String,
    /// LS-P17: a fix-it must never suggest `unsafe`, a new cap, or `Ffi`.
    pub fixit: Option<String>,
}

impl fmt::Display for Diagnostic {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}: {}", self.code, self.message)?;
        if let Some(fixit) = &self.fixit {
            write!(f, " [fix-it: {}]", fixit)?;
        }
        Ok(())
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct CheckOptions {
    /// Simulated arena budget in bytes.
    pub arena_budget: usize,
}

impl Default for CheckOptions {
    fn default() -> Self {
        Self {
            arena_budget: 1 << 20,
        }
    }
}

#[derive(Clone, Debug)]
pub struct CheckReport {
    pub diagnostics: Vec<Diagnostic>,
    pub arena: ArenaReport,
    pub functions: usize,
    pub regions: usize,
}

impl CheckReport {
    pub fn ok(&self) -> bool {
        self.diagnostics.is_empty()
    }
}

pub fn check_source(src: &str, options: CheckOptions) -> CheckReport {
    let program = match parse(src) {
        Ok(p) => p,
        Err(d) => {
            let mut checker = Checker::new(options);
            checker.diagnostics.push(d);
            return checker.finish(0);
        }
    };
    let mut checker = Checker::new(options);
    checker.check_program(&program);
    checker.finish(program.functions.len())
}

pub fn parse_source(src: &str) -> Result<(), Diagnostic> {
    parse(src).map(|_| ())
}

/// 1-based line/column for a byte offset (Unicode scalar columns).
pub fn line_col(src: &str, offset: usize) -> (usize, usize) {
    let offset = offset.min(src.len());
    let mut line = 1;
    let mut col = 1;
    for ch in src[..offset].chars() {
        if ch == '\n' {
            line += 1;
            col = 1;
        } else {
            col += 1;
        }
    }
    (line, col)
}

// ---------------------------------------------------------------------------
// Lexer
// ---------------------------------------------------------------------------

#[derive(Clone, Debug, PartialEq)]
enum TokKind {
    Ident(String),
    Int(i64),
    Str(String),
    Punct(String),
    Eof,
}

#[derive(Clone, Debug)]
struct Token {
    kind: TokKind,
    span: Span,
}

fn lex(src: &str) -> Result<Vec<Token>, Diagnostic> {
    let bytes = src.as_bytes();
    let mut i = 0;
    let mut out = Vec::new();
    while i < bytes.len() {
        let ch = src[i..].chars().next().unwrap();
        if ch.is_whitespace() {
            i += ch.len_utf8();
            continue;
        }
        if ch == '/' && bytes.get(i + 1) == Some(&b'/') {
            i += 2;
            while i < bytes.len() && bytes[i] != b'\n' {
                i += 1;
            }
            continue;
        }
        if ch == '/' && bytes.get(i + 1) == Some(&b'*') {
            let start = i;
            i += 2;
            let mut depth = 1;
            while i < bytes.len() && depth > 0 {
                if bytes[i] == b'/' && bytes.get(i + 1) == Some(&b'*') {
                    depth += 1;
                    i += 2;
                } else if bytes[i] == b'*' && bytes.get(i + 1) == Some(&b'/') {
                    depth -= 1;
                    i += 2;
                } else {
                    i += 1;
                }
            }
            if depth > 0 {
                return Err(err("E-LS-PARSE", start, i, "unterminated block comment"));
            }
            continue;
        }
        let start = i;
        if ch.is_ascii_digit() {
            i += 1;
            while i < bytes.len() && bytes[i].is_ascii_digit() {
                i += 1;
            }
            if i < bytes.len() && (bytes[i].is_ascii_alphabetic() || bytes[i] == b'_') {
                return Err(err(
                    "E-LS-PARSE",
                    start,
                    i,
                    "invalid integer literal suffix",
                ));
            }
            let text = &src[start..i];
            let value = text.parse::<i64>().map_err(|_| {
                err(
                    "E-LS-PARSE",
                    start,
                    i,
                    format!("integer literal out of range: {}", text),
                )
            })?;
            out.push(Token {
                kind: TokKind::Int(value),
                span: Span::new(start, i),
            });
            continue;
        }
        if ch == '"' {
            i += 1;
            let mut value = String::new();
            let mut closed = false;
            while i < bytes.len() {
                let c = src[i..].chars().next().unwrap();
                if c == '"' {
                    i += 1;
                    closed = true;
                    break;
                }
                if c == '\\' {
                    i += 1;
                    if i >= bytes.len() {
                        break;
                    }
                    let esc = src[i..].chars().next().unwrap();
                    i += esc.len_utf8();
                    match esc {
                        'n' => value.push('\n'),
                        't' => value.push('\t'),
                        'r' => value.push('\r'),
                        '0' => value.push('\0'),
                        '\\' => value.push('\\'),
                        '"' => value.push('"'),
                        'u' => {
                            if i >= bytes.len() || bytes[i] != b'{' {
                                return Err(err("E-LS-PARSE", start, i, "expected `{` after \\u"));
                            }
                            i += 1;
                            let hex_start = i;
                            while i < bytes.len() && bytes[i] != b'}' {
                                i += 1;
                            }
                            if i >= bytes.len() {
                                return Err(err("E-LS-PARSE", start, i, "unterminated \\u escape"));
                            }
                            let hex = &src[hex_start..i];
                            i += 1;
                            let cp = u32::from_str_radix(hex, 16).map_err(|_| {
                                err("E-LS-PARSE", hex_start, i, "invalid \\u escape")
                            })?;
                            let c = char::from_u32(cp).ok_or_else(|| {
                                err("E-LS-PARSE", hex_start, i, "invalid Unicode scalar")
                            })?;
                            value.push(c);
                        }
                        other => {
                            return Err(err(
                                "E-LS-PARSE",
                                i - other.len_utf8(),
                                i,
                                format!("unknown escape `\\{}`", other),
                            ))
                        }
                    }
                    continue;
                }
                if c == '\n' {
                    return Err(err("E-LS-PARSE", start, i, "newline in string literal"));
                }
                value.push(c);
                i += c.len_utf8();
            }
            if !closed {
                return Err(err("E-LS-PARSE", start, i, "unterminated string literal"));
            }
            out.push(Token {
                kind: TokKind::Str(value),
                span: Span::new(start, i),
            });
            continue;
        }
        if ch == '_' || ch.is_alphabetic() {
            i += ch.len_utf8();
            while i < bytes.len() {
                let c = src[i..].chars().next().unwrap();
                if c == '_' || c.is_alphanumeric() {
                    i += c.len_utf8();
                } else {
                    break;
                }
            }
            out.push(Token {
                kind: TokKind::Ident(src[start..i].to_string()),
                span: Span::new(start, i),
            });
            continue;
        }
        let two = if i + 1 < bytes.len() {
            Some(&src[i..i + 2])
        } else {
            None
        };
        if let Some(p) = two {
            if matches!(
                p,
                "->" | "==" | "!=" | "<=" | ">=" | "&&" | "||" | "+=" | "-=" | "*=" | "/=" | "%="
            ) {
                i += 2;
                out.push(Token {
                    kind: TokKind::Punct(p.to_string()),
                    span: Span::new(start, i),
                });
                continue;
            }
        }
        if "(){}[],:;.+-*/%<>=!?&|".contains(ch) {
            i += ch.len_utf8();
            out.push(Token {
                kind: TokKind::Punct(ch.to_string()),
                span: Span::new(start, i),
            });
            continue;
        }
        return Err(err(
            "E-LS-PARSE",
            start,
            i + ch.len_utf8(),
            format!("unexpected character `{}`", ch),
        ));
    }
    out.push(Token {
        kind: TokKind::Eof,
        span: Span::new(src.len(), src.len()),
    });
    Ok(out)
}

fn err(code: &'static str, start: usize, end: usize, msg: impl Into<String>) -> Diagnostic {
    Diagnostic {
        code,
        span: Span::new(start, end),
        message: msg.into(),
        fixit: None,
    }
}

fn err_fix(
    code: &'static str,
    start: usize,
    end: usize,
    msg: impl Into<String>,
    fixit: impl Into<String>,
) -> Diagnostic {
    Diagnostic {
        code,
        span: Span::new(start, end),
        message: msg.into(),
        fixit: Some(fixit.into()),
    }
}

// ---------------------------------------------------------------------------
// AST
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
struct Program {
    structs: Vec<StructDef>,
    enums: Vec<EnumDef>,
    functions: Vec<FnDef>,
    statics: Vec<StaticDef>,
}

#[derive(Clone, Debug)]
struct StaticDef {
    name: String,
    ty: Ty,
    init: Expr,
    span: Span,
}

#[derive(Clone, Debug)]
struct GenericParam {
    name: String,
    bounds: Vec<String>,
    span: Span,
}

#[derive(Clone, Debug)]
struct StructDef {
    name: String,
    generics: Vec<GenericParam>,
    fields: Vec<(String, Ty, Span)>,
    span: Span,
}

#[derive(Clone, Debug)]
struct EnumDef {
    name: String,
    generics: Vec<GenericParam>,
    variants: Vec<VariantDef>,
    span: Span,
}

#[derive(Clone, Debug)]
struct VariantDef {
    name: String,
    payload: Vec<Ty>,
    span: Span,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
enum ParamMode {
    Owned,
    Val,
    Ref,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Hash)]
enum ModeTag {
    Boxed,
    Iso,
    Val,
    Ref,
    Shared,
    Atom,
    Raw,
}

impl fmt::Display for ModeTag {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str(match self {
            ModeTag::Boxed => "box",
            ModeTag::Iso => "iso",
            ModeTag::Val => "val",
            ModeTag::Ref => "ref",
            ModeTag::Shared => "shared",
            ModeTag::Atom => "atom",
            ModeTag::Raw => "rawptr",
        })
    }
}

#[derive(Clone, Debug)]
struct ParamDef {
    mode: ParamMode,
    name: String,
    ty: Ty,
    span: Span,
}

#[derive(Clone, Debug)]
struct FnDef {
    name: String,
    generics: Vec<GenericParam>,
    params: Vec<ParamDef>,
    ret: Ty,
    effects: Vec<String>,
    requires: Vec<Expr>,
    ensures: Vec<Expr>,
    body: Block,
    span: Span,
}

#[derive(Clone, Debug)]
struct Block {
    stmts: Vec<Stmt>,
    span: Span,
}

#[derive(Clone, Debug)]
enum Stmt {
    Let {
        name: String,
        ann: Option<Ty>,
        init: Expr,
        span: Span,
    },
    Region {
        name: String,
        body: Block,
        span: Span,
    },
    Return {
        value: Option<Expr>,
        span: Span,
    },
    If {
        cond: Expr,
        then_block: Block,
        else_block: Option<Block>,
        span: Span,
    },
    While {
        cond: Expr,
        body: Block,
        span: Span,
    },
    Comptime {
        body: Block,
        span: Span,
    },
    Drop {
        value: Expr,
        span: Span,
    },
    Borrow {
        mutable: bool,
        place: Expr,
        alias: String,
        body: Block,
        span: Span,
    },
    Assign {
        place: Expr,
        op: String,
        value: Expr,
        span: Span,
    },
    Expr(Expr),
}

#[derive(Clone, Debug)]
struct Expr {
    kind: ExprKind,
    span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
enum ExprKind {
    Int(i64),
    Bool(bool),
    Str(String),
    Var(String),
    Field(Box<Expr>, String),
    Call {
        callee: Box<Expr>,
        type_args: Vec<Ty>,
        args: Vec<Expr>,
    },
    Unary {
        op: String,
        value: Box<Expr>,
    },
    Binary {
        op: String,
        left: Box<Expr>,
        right: Box<Expr>,
    },
    Try(Box<Expr>),
    Index {
        base: Box<Expr>,
        index: Box<Expr>,
    },
    StructLit {
        mode: Option<ModeTag>,
        name: String,
        fields: Vec<(String, Expr)>,
    },
    Freeze(Box<Expr>),
    Spawn(Box<Expr>),
    Move(Box<Expr>),
}

#[derive(Clone, Debug, Eq, PartialEq, Hash)]
enum Ty {
    Unit,
    Int,
    U8,
    Bool,
    Str,
    Slice(Box<Ty>),
    Buffer(Box<Ty>),
    Option(Box<Ty>),
    Result(Box<Ty>, Box<Ty>),
    Named(String, Vec<Ty>),
    Mode(ModeTag, Box<Ty>),
    Atomic(Box<Ty>),
    Array(Box<Ty>, u32),
    Lock(Box<Ty>, u32),
    Guard(Box<Ty>, u32),
    Const(u32),
    JoinHandle,
    Param(String),
    Var(u32),
    Error,
}

impl fmt::Display for Ty {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Ty::Unit => f.write_str("Unit"),
            Ty::Int => f.write_str("Int"),
            Ty::U8 => f.write_str("U8"),
            Ty::Bool => f.write_str("Bool"),
            Ty::Str => f.write_str("Str"),
            Ty::Slice(t) => write!(f, "Slice[{}]", t),
            Ty::Buffer(t) => write!(f, "Buffer[{}]", t),
            Ty::Option(t) => write!(f, "Option[{}]", t),
            Ty::Result(t, e) => write!(f, "Result[{}, {}]", t, e),
            Ty::Named(n, args) => {
                if args.is_empty() {
                    f.write_str(n)
                } else {
                    write!(
                        f,
                        "{}[{}]",
                        n,
                        args.iter()
                            .map(|t| t.to_string())
                            .collect::<Vec<_>>()
                            .join(", ")
                    )
                }
            }
            Ty::Mode(m, t) => write!(f, "{}[{}]", m, t),
            Ty::Atomic(t) => write!(f, "Atomic[{}]", t),
            Ty::Array(t, n) => write!(f, "Array[{}, {}]", t, n),
            Ty::Lock(t, r) => write!(f, "Lock[{}, {}]", t, r),
            Ty::Guard(t, r) => write!(f, "Guard[{}, {}]", t, r),
            Ty::Const(n) => write!(f, "{}", n),
            Ty::JoinHandle => f.write_str("JoinHandle"),
            Ty::Param(n) => f.write_str(n),
            Ty::Var(v) => write!(f, "?{}", v),
            Ty::Error => f.write_str("<error>"),
        }
    }
}

// ---------------------------------------------------------------------------
// Parser
// ---------------------------------------------------------------------------

#[allow(dead_code)]
struct Parser<'a> {
    src: &'a str,
    toks: Vec<Token>,
    pos: usize,
    type_params: Vec<String>,
    // `if x { ... }` must not parse `x { ... }` as a struct literal.
    struct_lit_ok: bool,
}

fn parse(src: &str) -> Result<Program, Diagnostic> {
    let toks = lex(src)?;
    Parser {
        src,
        toks,
        pos: 0,
        type_params: Vec::new(),
        struct_lit_ok: true,
    }
    .program()
}

impl<'a> Parser<'a> {
    fn peek(&self) -> &Token {
        &self.toks[self.pos]
    }

    fn bump(&mut self) -> Token {
        let t = self.toks[self.pos].clone();
        if self.pos + 1 < self.toks.len() {
            self.pos += 1;
        }
        t
    }

    fn at_punct(&self, p: &str) -> bool {
        matches!(&self.peek().kind, TokKind::Punct(x) if x == p)
    }

    fn at_ident(&self, name: &str) -> bool {
        matches!(&self.peek().kind, TokKind::Ident(x) if x == name)
    }

    fn eat_punct(&mut self, p: &str) -> bool {
        if self.at_punct(p) {
            self.bump();
            true
        } else {
            false
        }
    }

    fn expect_punct(&mut self, p: &str) -> Result<Token, Diagnostic> {
        if self.at_punct(p) {
            Ok(self.bump())
        } else {
            let t = self.peek();
            Err(err(
                "E-LS-PARSE",
                t.span.start,
                t.span.end,
                format!("expected `{}`, found {}", p, describe(&t.kind)),
            ))
        }
    }

    fn expect_ident(&mut self) -> Result<(String, Span), Diagnostic> {
        let t = self.peek().clone();
        match t.kind {
            TokKind::Ident(name) => {
                self.bump();
                Ok((name, t.span))
            }
            _ => Err(err(
                "E-LS-PARSE",
                t.span.start,
                t.span.end,
                format!("expected identifier, found {}", describe(&t.kind)),
            )),
        }
    }

    fn peek_is_ident(&self) -> bool {
        matches!(self.peek().kind, TokKind::Ident(_))
    }

    fn next_is_ident(&self) -> bool {
        matches!(
            self.toks.get(self.pos + 1).map(|t| &t.kind),
            Some(TokKind::Ident(_))
        )
    }

    fn expect_keyword(&mut self, kw: &str) -> Result<Span, Diagnostic> {
        if self.at_ident(kw) {
            Ok(self.bump().span)
        } else {
            let t = self.peek();
            Err(err(
                "E-LS-PARSE",
                t.span.start,
                t.span.end,
                format!("expected `{}`, found {}", kw, describe(&t.kind)),
            ))
        }
    }

    fn program(mut self) -> Result<Program, Diagnostic> {
        let mut out = Program {
            structs: Vec::new(),
            enums: Vec::new(),
            functions: Vec::new(),
            statics: Vec::new(),
        };
        while !matches!(self.peek().kind, TokKind::Eof) {
            if self.eat_punct(";") {
                continue;
            }
            if self.at_ident("struct") {
                out.structs.push(self.struct_def()?);
            } else if self.at_ident("enum") {
                out.enums.push(self.enum_def()?);
            } else if self.at_ident("fn") {
                out.functions.push(self.fn_def()?);
            } else if self.at_ident("static") {
                out.statics.push(self.static_def()?);
            } else {
                let t = self.peek();
                return Err(err(
                    "E-LS-PARSE",
                    t.span.start,
                    t.span.end,
                    "expected `struct`, `enum`, `fn` or `static` item",
                ));
            }
        }
        Ok(out)
    }

    fn generics(&mut self) -> Result<Vec<GenericParam>, Diagnostic> {
        let mut out = Vec::new();
        if !self.eat_punct("[") {
            return Ok(out);
        }
        loop {
            let (name, span) = self.expect_ident()?;
            let mut bounds = Vec::new();
            if self.eat_punct(":") {
                loop {
                    let (bound, _) = self.expect_ident()?;
                    bounds.push(bound);
                    if !self.eat_punct("+") {
                        break;
                    }
                }
            }
            out.push(GenericParam { name, bounds, span });
            if !self.eat_punct(",") {
                break;
            }
        }
        self.expect_punct("]")?;
        Ok(out)
    }

    fn struct_def(&mut self) -> Result<StructDef, Diagnostic> {
        let start = self.expect_keyword("struct")?;
        let (name, _) = self.expect_ident()?;
        let generics = self.generics()?;
        let saved = self.type_params.len();
        self.type_params
            .extend(generics.iter().map(|g| g.name.clone()));
        let result = self.struct_body(&name, generics, start);
        self.type_params.truncate(saved);
        result
    }

    fn static_def(&mut self) -> Result<StaticDef, Diagnostic> {
        let start = self.expect_keyword("static")?;
        let (name, _) = self.expect_ident()?;
        self.expect_punct(":")?;
        let ty = self.ty()?;
        self.expect_punct("=")?;
        let init = self.expr()?;
        let semi = self.expect_punct(";")?;
        Ok(StaticDef {
            name,
            ty,
            init,
            span: start.join(semi.span),
        })
    }

    fn struct_body(
        &mut self,
        name: &str,
        generics: Vec<GenericParam>,
        start: Span,
    ) -> Result<StructDef, Diagnostic> {
        self.expect_punct("{")?;
        let mut fields = Vec::new();
        while !self.eat_punct("}") {
            let (fname, fspan) = self.expect_ident()?;
            self.expect_punct(":")?;
            let ty = self.ty()?;
            fields.push((fname, ty, fspan));
            if !self.eat_punct(",") {
                self.expect_punct("}")?;
                break;
            }
        }
        Ok(StructDef {
            name: name.to_string(),
            generics,
            fields,
            span: start.join(self.toks[self.pos.saturating_sub(1)].span),
        })
    }

    fn enum_def(&mut self) -> Result<EnumDef, Diagnostic> {
        let start = self.expect_keyword("enum")?;
        let (name, _) = self.expect_ident()?;
        let generics = self.generics()?;
        let saved = self.type_params.len();
        self.type_params
            .extend(generics.iter().map(|g| g.name.clone()));
        let result = self.enum_body(&name, generics, start);
        self.type_params.truncate(saved);
        result
    }

    fn enum_body(
        &mut self,
        name: &str,
        generics: Vec<GenericParam>,
        start: Span,
    ) -> Result<EnumDef, Diagnostic> {
        self.expect_punct("{")?;
        let mut variants = Vec::new();
        while !self.eat_punct("}") {
            let (vname, vspan) = self.expect_ident()?;
            let mut payload = Vec::new();
            if self.eat_punct("(") {
                if !self.eat_punct(")") {
                    loop {
                        payload.push(self.ty()?);
                        if !self.eat_punct(",") {
                            break;
                        }
                    }
                    self.expect_punct(")")?;
                }
            }
            let span = vspan.join(self.toks[self.pos.saturating_sub(1)].span);
            variants.push(VariantDef {
                name: vname,
                payload,
                span,
            });
            if !self.eat_punct(",") {
                self.expect_punct("}")?;
                break;
            }
        }
        Ok(EnumDef {
            name: name.to_string(),
            generics,
            variants,
            span: start.join(self.toks[self.pos.saturating_sub(1)].span),
        })
    }

    fn fn_def(&mut self) -> Result<FnDef, Diagnostic> {
        let start = self.expect_keyword("fn")?;
        let (name, _) = self.expect_ident()?;
        let generics = self.generics()?;
        let saved = self.type_params.len();
        self.type_params
            .extend(generics.iter().map(|g| g.name.clone()));
        let result = self.fn_body(&name, generics, start);
        self.type_params.truncate(saved);
        result
    }

    fn fn_body(
        &mut self,
        name: &str,
        generics: Vec<GenericParam>,
        start: Span,
    ) -> Result<FnDef, Diagnostic> {
        self.expect_punct("(")?;
        let mut params = Vec::new();
        if !self.eat_punct(")") {
            loop {
                let mode = if self.at_ident("val") && self.next_is_ident() {
                    self.bump();
                    ParamMode::Val
                } else if self.at_ident("ref") && self.next_is_ident() {
                    self.bump();
                    ParamMode::Ref
                } else {
                    ParamMode::Owned
                };
                let (pname, pspan) = self.expect_ident()?;
                self.expect_punct(":")?;
                let ty = self.ty()?;
                params.push(ParamDef {
                    mode,
                    name: pname,
                    ty,
                    span: pspan,
                });
                if !self.eat_punct(",") {
                    break;
                }
            }
            self.expect_punct(")")?;
        }
        let ret = if self.eat_punct("->") {
            self.ty()?
        } else {
            Ty::Unit
        };
        let mut effects = Vec::new();
        let mut requires = Vec::new();
        let mut ensures = Vec::new();
        loop {
            if self.at_ident("eff") {
                self.bump();
                self.expect_punct("(")?;
                if !self.eat_punct(")") {
                    loop {
                        let (e, _) = self.expect_ident()?;
                        effects.push(e);
                        if !self.eat_punct(",") {
                            break;
                        }
                    }
                    self.expect_punct(")")?;
                }
            } else if self.at_ident("requires") {
                self.bump();
                let saved = self.struct_lit_ok;
                self.struct_lit_ok = false;
                let e = self.expr()?;
                self.struct_lit_ok = saved;
                requires.push(e);
            } else if self.at_ident("ensures") {
                self.bump();
                let saved = self.struct_lit_ok;
                self.struct_lit_ok = false;
                let e = self.expr()?;
                self.struct_lit_ok = saved;
                ensures.push(e);
            } else {
                break;
            }
        }
        let body = self.block()?;
        Ok(FnDef {
            name: name.to_string(),
            generics,
            params,
            ret,
            effects,
            requires,
            ensures,
            span: start.join(body.span),
            body,
        })
    }

    fn ty(&mut self) -> Result<Ty, Diagnostic> {
        let (name, span) = self.expect_ident()?;
        let mode = match name.as_str() {
            "box" => Some(ModeTag::Boxed),
            "iso" => Some(ModeTag::Iso),
            "val" => Some(ModeTag::Val),
            "ref" => Some(ModeTag::Ref),
            "shared" => Some(ModeTag::Shared),
            "atom" => Some(ModeTag::Atom),
            "rawptr" => Some(ModeTag::Raw),
            _ => None,
        };
        let mut args = Vec::new();
        if self.eat_punct("[") {
            if !self.eat_punct("]") {
                loop {
                    match self.peek().kind {
                        TokKind::Int(n) => {
                            self.bump();
                            args.push(Ty::Const(n as u32));
                        }
                        _ => args.push(self.ty()?),
                    }
                    if !self.eat_punct(",") {
                        break;
                    }
                }
                self.expect_punct("]")?;
            }
        }
        if let Some(m) = mode {
            let mut args = args.into_iter();
            let Some(inner) = args.next() else {
                return Err(err(
                    "E-LS-PARSE",
                    span.start,
                    span.end,
                    format!("`{}` requires a type argument", name),
                ));
            };
            return Ok(Ty::Mode(m, Box::new(inner)));
        }
        let builtin = match (name.as_str(), args.len()) {
            ("Unit", 0) => Some(Ty::Unit),
            ("Int", 0) => Some(Ty::Int),
            ("U8", 0) => Some(Ty::U8),
            ("Bool", 0) => Some(Ty::Bool),
            ("Str", 0) => Some(Ty::Str),
            ("Slice", 1) => Some(Ty::Slice(Box::new(args.remove(0)))),
            ("Buffer", 1) => Some(Ty::Buffer(Box::new(args.remove(0)))),
            ("Option", 1) => Some(Ty::Option(Box::new(args.remove(0)))),
            ("Result", 2) => {
                let e = args.remove(1);
                let t = args.remove(0);
                Some(Ty::Result(Box::new(t), Box::new(e)))
            }
            ("Atomic", 1) => Some(Ty::Atomic(Box::new(args.remove(0)))),
            ("Array", 2) => {
                let n = args.remove(1);
                let t = args.remove(0);
                match n {
                    Ty::Const(n) => Some(Ty::Array(Box::new(t), n)),
                    _ => None,
                }
            }
            ("Lock", 2) => {
                let r = args.remove(1);
                let t = args.remove(0);
                match r {
                    Ty::Const(r) => Some(Ty::Lock(Box::new(t), r)),
                    _ => None,
                }
            }
            _ => None,
        };
        if let Some(ty) = builtin {
            return Ok(ty);
        }
        if args.is_empty() && self.type_params.iter().any(|p| p == &name) {
            return Ok(Ty::Param(name));
        }
        if name == "AllocError" || name == "Error" {
            if args.is_empty() {
                return Ok(Ty::Named(name, Vec::new()));
            }
        }
        Ok(Ty::Named(name, args))
    }

    fn block(&mut self) -> Result<Block, Diagnostic> {
        let start = self.expect_punct("{")?.span;
        let mut stmts = Vec::new();
        while !self.eat_punct("}") {
            if self.eat_punct(";") {
                continue;
            }
            if matches!(self.peek().kind, TokKind::Eof) {
                return Err(err(
                    "E-LS-PARSE",
                    start.start,
                    start.end,
                    "unterminated block",
                ));
            }
            stmts.push(self.stmt()?);
        }
        Ok(Block {
            stmts,
            span: start.join(self.toks[self.pos.saturating_sub(1)].span),
        })
    }

    fn stmt(&mut self) -> Result<Stmt, Diagnostic> {
        let t = self.peek().clone();
        if self.at_ident("let") {
            self.bump();
            if self.at_ident("mut") {
                self.bump();
            }
            let (name, nspan) = self.expect_ident()?;
            let ann = if self.eat_punct(":") {
                Some(self.ty()?)
            } else {
                None
            };
            self.expect_punct("=")?;
            let init = self.expr()?;
            let semi = self.expect_punct(";")?;
            return Ok(Stmt::Let {
                name,
                ann,
                init,
                span: t.span.join(semi.span).join(nspan),
            });
        }
        if self.at_ident("region") {
            self.bump();
            let (name, _) = self.expect_ident()?;
            let body = self.block()?;
            return Ok(Stmt::Region {
                name,
                span: t.span.join(body.span),
                body,
            });
        }
        if self.at_ident("return") {
            self.bump();
            let value = if self.at_punct(";") {
                None
            } else {
                Some(self.expr()?)
            };
            let semi = self.expect_punct(";")?;
            return Ok(Stmt::Return {
                value,
                span: t.span.join(semi.span),
            });
        }
        if self.at_ident("if") {
            self.bump();
            let saved = self.struct_lit_ok;
            self.struct_lit_ok = false;
            let cond = self.expr()?;
            self.struct_lit_ok = saved;
            let then_block = self.block()?;
            let else_block = if self.at_ident("else") {
                self.bump();
                if self.at_ident("if") {
                    let nested = self.stmt()?;
                    let span = nested_span(&nested);
                    Some(Block {
                        stmts: vec![nested],
                        span,
                    })
                } else {
                    Some(self.block()?)
                }
            } else {
                None
            };
            return Ok(Stmt::If {
                cond,
                then_block,
                else_block,
                span: t.span,
            });
        }
        if self.at_ident("while") {
            self.bump();
            let saved = self.struct_lit_ok;
            self.struct_lit_ok = false;
            let cond = self.expr()?;
            self.struct_lit_ok = saved;
            let body = self.block()?;
            let span = t.span.join(body.span);
            return Ok(Stmt::While { cond, body, span });
        }
        if self.at_ident("comptime") {
            self.bump();
            let body = self.block()?;
            return Ok(Stmt::Comptime {
                span: t.span.join(body.span),
                body,
            });
        }
        if self.at_ident("drop") {
            self.bump();
            let value = self.expr()?;
            let semi = self.expect_punct(";")?;
            return Ok(Stmt::Drop {
                value,
                span: t.span.join(semi.span),
            });
        }
        if self.at_ident("borrow") {
            self.bump();
            let mutable = if self.at_ident("mut") {
                self.bump();
                true
            } else {
                false
            };
            let place = self.expr()?;
            self.expect_keyword("as")?;
            let (alias, _) = self.expect_ident()?;
            let body = self.block()?;
            let span = t.span.join(body.span);
            return Ok(Stmt::Borrow {
                mutable,
                place,
                alias,
                body,
                span,
            });
        }
        let expr = self.expr()?;
        for op in ["=", "+=", "-=", "*=", "/=", "%="] {
            if self.at_punct(op) {
                self.bump();
                let value = self.expr()?;
                let semi = self.expect_punct(";")?;
                let span = expr.span.join(semi.span);
                return Ok(Stmt::Assign {
                    place: expr,
                    op: op.to_string(),
                    value,
                    span,
                });
            }
        }
        if self.eat_punct(";") {
            return Ok(Stmt::Expr(expr));
        }
        if self.at_punct("}") {
            return Ok(Stmt::Expr(expr)); // tail expression
        }
        Err(err(
            "E-LS-PARSE",
            self.peek().span.start,
            self.peek().span.end,
            "expected `;` or `}` after expression statement",
        ))
    }

    fn expr(&mut self) -> Result<Expr, Diagnostic> {
        self.binary(0)
    }

    fn binary(&mut self, min_prec: u8) -> Result<Expr, Diagnostic> {
        let mut left = self.unary()?;
        loop {
            let (op, prec) = match &self.peek().kind {
                TokKind::Punct(p) => match p.as_str() {
                    "||" => ("||".to_string(), 1),
                    "&&" => ("&&".to_string(), 2),
                    "==" | "!=" => (p.clone(), 3),
                    "<" | "<=" | ">" | ">=" => (p.clone(), 4),
                    "+" | "-" => (p.clone(), 5),
                    "*" | "/" | "%" => (p.clone(), 6),
                    _ => break,
                },
                _ => break,
            };
            if prec < min_prec {
                break;
            }
            let opt = self.bump();
            let right = self.binary(prec + 1)?;
            left = Expr {
                span: left.span.join(right.span),
                kind: ExprKind::Binary {
                    op,
                    left: Box::new(left),
                    right: Box::new(right),
                },
            };
            let _ = opt;
        }
        Ok(left)
    }

    fn unary(&mut self) -> Result<Expr, Diagnostic> {
        for (kw, make) in [("freeze", 0u8), ("spawn", 1u8), ("move", 2u8)] {
            if self.at_ident(kw) {
                let t = self.bump();
                let value = self.unary()?;
                let span = t.span.join(value.span);
                let kind = match make {
                    0 => ExprKind::Freeze(Box::new(value)),
                    1 => ExprKind::Spawn(Box::new(value)),
                    _ => ExprKind::Move(Box::new(value)),
                };
                return Ok(Expr { kind, span });
            }
        }
        if self.at_punct("!") || self.at_punct("-") {
            let t = self.bump();
            let op = match t.kind {
                TokKind::Punct(p) => p,
                _ => unreachable!(),
            };
            let value = self.unary()?;
            return Ok(Expr {
                span: t.span.join(value.span),
                kind: ExprKind::Unary {
                    op,
                    value: Box::new(value),
                },
            });
        }
        self.postfix()
    }

    fn postfix(&mut self) -> Result<Expr, Diagnostic> {
        let mut expr = self.primary()?;
        loop {
            if self.eat_punct(".") {
                let (name, nspan) = self.expect_ident()?;
                expr = Expr {
                    span: expr.span.join(nspan),
                    kind: ExprKind::Field(Box::new(expr), name),
                };
                continue;
            }
            if self.at_punct("[") {
                // Ambiguous: `f[T](x)` (type args + call) vs `p[i]` (index).
                // Try the type-argument form; fall back to indexing.
                let save = self.pos;
                let open = self.bump();
                let mut type_args: Vec<Ty> = Vec::new();
                let mut ok = true;
                if !self.eat_punct("]") {
                    loop {
                        match self.peek().kind {
                            TokKind::Int(n) => {
                                self.bump();
                                type_args.push(Ty::Const(n as u32));
                            }
                            _ => match self.ty() {
                                Ok(ty) => type_args.push(ty),
                                Err(_) => {
                                    ok = false;
                                    break;
                                }
                            },
                        }
                        if !self.eat_punct(",") {
                            break;
                        }
                    }
                    if ok {
                        ok = self.eat_punct("]");
                    }
                }
                if ok && self.at_punct("(") {
                    self.bump();
                    let (args, end) = self.args()?;
                    expr = Expr {
                        span: open.span.join(end),
                        kind: ExprKind::Call {
                            callee: Box::new(expr),
                            type_args,
                            args,
                        },
                    };
                    continue;
                }
                self.pos = save;
                let open = self.bump();
                let index = self.expr()?;
                let close = self.expect_punct("]")?;
                expr = Expr {
                    span: open.span.join(close.span),
                    kind: ExprKind::Index {
                        base: Box::new(expr),
                        index: Box::new(index),
                    },
                };
                continue;
            }
            if self.eat_punct("(") {
                let (args, end) = self.args()?;
                expr = Expr {
                    span: expr.span.join(end),
                    kind: ExprKind::Call {
                        callee: Box::new(expr),
                        type_args: Vec::new(),
                        args,
                    },
                };
                continue;
            }
            if self.eat_punct("?") {
                let span = expr.span.join(self.toks[self.pos.saturating_sub(1)].span);
                expr = Expr {
                    span,
                    kind: ExprKind::Try(Box::new(expr)),
                };
                continue;
            }
            break;
        }
        Ok(expr)
    }

    fn struct_fields(&mut self) -> Result<Vec<(String, Expr)>, Diagnostic> {
        self.expect_punct("{")?;
        let mut fields = Vec::new();
        if !self.eat_punct("}") {
            loop {
                let (fname, fspan) = self.expect_ident()?;
                let value = if self.eat_punct(":") {
                    self.expr()?
                } else {
                    Expr {
                        kind: ExprKind::Var(fname.clone()),
                        span: fspan,
                    }
                };
                fields.push((fname, value));
                if !self.eat_punct(",") {
                    break;
                }
            }
            self.expect_punct("}")?;
        }
        Ok(fields)
    }

    fn args(&mut self) -> Result<(Vec<Expr>, Span), Diagnostic> {
        let mut args = Vec::new();
        if self.eat_punct(")") {
            return Ok((args, self.toks[self.pos.saturating_sub(1)].span));
        }
        loop {
            args.push(self.expr()?);
            if !self.eat_punct(",") {
                break;
            }
        }
        let close = self.expect_punct(")")?;
        Ok((args, close.span))
    }

    fn primary(&mut self) -> Result<Expr, Diagnostic> {
        let t = self.peek().clone();
        match t.kind {
            TokKind::Int(v) => {
                self.bump();
                Ok(Expr {
                    kind: ExprKind::Int(v),
                    span: t.span,
                })
            }
            TokKind::Str(v) => {
                self.bump();
                Ok(Expr {
                    kind: ExprKind::Str(v),
                    span: t.span,
                })
            }
            TokKind::Ident(name) => {
                self.bump();
                if name == "true" {
                    return Ok(Expr {
                        kind: ExprKind::Bool(true),
                        span: t.span,
                    });
                }
                if name == "false" {
                    return Ok(Expr {
                        kind: ExprKind::Bool(false),
                        span: t.span,
                    });
                }
                // `Order.X` is a value path, not a type or local.
                if name == "Order" {
                    return Ok(Expr {
                        kind: ExprKind::Var(name),
                        span: t.span,
                    });
                }
                if self.struct_lit_ok {
                    if let Some(mode) = mode_keyword(&name) {
                        if self.peek_is_ident()
                            && matches!(
                                self.toks.get(self.pos + 1).map(|t| &t.kind),
                                Some(TokKind::Punct(p)) if p == "{"
                            )
                        {
                            let (struct_name, _) = self.expect_ident()?;
                            let fields = self.struct_fields()?;
                            let end = self.toks[self.pos.saturating_sub(1)].span;
                            return Ok(Expr {
                                span: t.span.join(end),
                                kind: ExprKind::StructLit {
                                    mode: Some(mode),
                                    name: struct_name,
                                    fields,
                                },
                            });
                        }
                    }
                    if self.at_punct("{") {
                        let fields = self.struct_fields()?;
                        let end = self.toks[self.pos.saturating_sub(1)].span;
                        return Ok(Expr {
                            span: t.span.join(end),
                            kind: ExprKind::StructLit {
                                mode: None,
                                name,
                                fields,
                            },
                        });
                    }
                }
                Ok(Expr {
                    kind: ExprKind::Var(name),
                    span: t.span,
                })
            }
            TokKind::Punct(ref p) if p == "(" => {
                self.bump();
                let e = self.expr()?;
                self.expect_punct(")")?;
                Ok(e)
            }
            _ => Err(err(
                "E-LS-PARSE",
                t.span.start,
                t.span.end,
                format!("expected expression, found {}", describe(&t.kind)),
            )),
        }
    }
}

fn nested_span(stmt: &Stmt) -> Span {
    match stmt {
        Stmt::Let { span, .. }
        | Stmt::Region { span, .. }
        | Stmt::Return { span, .. }
        | Stmt::If { span, .. }
        | Stmt::While { span, .. }
        | Stmt::Comptime { span, .. }
        | Stmt::Drop { span, .. }
        | Stmt::Borrow { span, .. }
        | Stmt::Assign { span, .. } => *span,
        Stmt::Expr(e) => e.span,
    }
}

fn describe(kind: &TokKind) -> String {
    match kind {
        TokKind::Ident(s) => format!("`{}`", s),
        TokKind::Int(v) => format!("integer `{}`", v),
        TokKind::Str(_) => "string literal".to_string(),
        TokKind::Punct(p) => format!("`{}`", p),
        TokKind::Eof => "end of file".to_string(),
    }
}

// ---------------------------------------------------------------------------
// Type checker
// ---------------------------------------------------------------------------

#[derive(Clone, Debug)]
#[allow(dead_code)]
struct StructInfo {
    generics: Vec<GenericParam>,
    fields: Vec<(String, Ty)>,
    span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
struct EnumInfo {
    generics: Vec<GenericParam>,
    variants: Vec<VariantDef>,
    span: Span,
}

#[derive(Clone, Debug)]
#[allow(dead_code)]
struct FnInfo {
    generics: Vec<GenericParam>,
    params: Vec<ParamDef>,
    ret: Ty,
    effects: BTreeSet<String>,
    span: Span,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
struct BufferState {
    capacity: usize,
    len: usize,
    allocation: Option<Allocation>,
}

#[derive(Clone, Debug)]
struct VarInfo {
    ty: Ty,
    mode: ParamMode,
    region: Region,
    /// `Rgn*`: every region reachable through ref/val/box/slice fields.
    footprint: BTreeSet<Region>,
    moved: bool,
    borrowed: bool,
    buffer: Option<BufferState>,
    allocations: Vec<Allocation>,
}

#[derive(Clone, Debug)]
struct Constraint {
    ty: Ty,
    trait_name: String,
    span: Span,
}

#[allow(dead_code)]
struct FnCtx {
    name: String,
    ret: Ty,
    ambient: Region,
    /// Innermost lexical region (region block or the function ambient).
    current_region: Region,
    generics: BTreeMap<String, BTreeSet<String>>,
    scopes: Vec<BTreeMap<String, VarInfo>>,
    region_names: Vec<Vec<(String, Region)>>,
    used_effects: BTreeSet<String>,
    constraints: Vec<Constraint>,
    comptime_depth: usize,
    frozen: BTreeSet<Place>,
    borrowed: BTreeSet<Place>,
    guards: Vec<(String, u32)>,
}

impl FnCtx {
    fn lookup(&self, name: &str) -> Option<&VarInfo> {
        for scope in self.scopes.iter().rev() {
            if let Some(v) = scope.get(name) {
                return Some(v);
            }
        }
        None
    }

    fn lookup_mut(&mut self, name: &str) -> Option<&mut VarInfo> {
        for scope in self.scopes.iter_mut().rev() {
            if let Some(v) = scope.get_mut(name) {
                return Some(v);
            }
        }
        None
    }

    fn insert(&mut self, name: String, info: VarInfo) {
        self.scopes.last_mut().unwrap().insert(name, info);
    }

    fn visible_region(&self, name: &str) -> Option<Region> {
        for scope in self.region_names.iter().rev() {
            for (n, r) in scope.iter().rev() {
                if n == name {
                    return Some(r.clone());
                }
            }
        }
        None
    }
}

struct Checker {
    structs: BTreeMap<String, StructInfo>,
    enums: BTreeMap<String, EnumInfo>,
    functions: BTreeMap<String, FnInfo>,
    regions: RegionTree,
    region_static: Region,
    region_heap: Region,
    region_thread: Region,
    diagnostics: Vec<Diagnostic>,
    arena: Arena,
    next_var: u32,
    subst: BTreeMap<u32, Ty>,
    region_serial: usize,
    region_count: usize,
    statics: BTreeMap<String, VarInfo>,
}

impl Checker {
    fn new(options: CheckOptions) -> Self {
        let mut regions = RegionTree::default();
        let region_static = regions.add_root("static").expect("fresh region tree");
        let region_heap = regions
            .add_child("heap", &region_static)
            .expect("fresh region tree");
        let region_thread = regions
            .add_child("thread", &region_heap)
            .expect("fresh region tree");
        Self {
            structs: BTreeMap::new(),
            enums: BTreeMap::new(),
            functions: BTreeMap::new(),
            regions,
            region_static,
            region_heap,
            region_thread,
            diagnostics: Vec::new(),
            arena: Arena::new(options.arena_budget),
            next_var: 0,
            subst: BTreeMap::new(),
            region_serial: 0,
            region_count: 0,
            statics: BTreeMap::new(),
        }
    }

    fn finish(self, functions: usize) -> CheckReport {
        CheckReport {
            diagnostics: self.diagnostics,
            arena: self.arena.report(),
            functions,
            regions: self.region_count,
        }
    }

    fn error(&mut self, code: &'static str, span: Span, msg: impl Into<String>) {
        self.diagnostics.push(err(code, span.start, span.end, msg));
    }

    fn check_program(&mut self, program: &Program) {
        for def in &program.structs {
            self.register_struct(def);
        }
        for def in &program.enums {
            self.register_enum(def);
        }
        for def in &program.functions {
            self.register_fn(def);
        }
        self.check_decl_bounds(program);
        for def in &program.statics {
            self.check_static(def);
        }
        for def in &program.functions {
            self.check_fn(def);
        }
    }

    fn register_struct(&mut self, def: &StructDef) {
        if self.structs.contains_key(&def.name)
            || self.enums.contains_key(&def.name)
            || is_builtin_type(&def.name)
        {
            self.error(
                "E-LS-DUP",
                def.span,
                format!("type `{}` is already defined", def.name),
            );
            return;
        }
        self.check_generic_names(&def.generics, def.span);
        let mut seen = BTreeSet::new();
        for (name, _, span) in &def.fields {
            if !seen.insert(name.clone()) {
                self.error("E-LS-DUP", *span, format!("duplicate field `{}`", name));
            }
        }
        self.structs.insert(
            def.name.clone(),
            StructInfo {
                generics: def.generics.clone(),
                fields: def
                    .fields
                    .iter()
                    .map(|(n, t, _)| (n.clone(), t.clone()))
                    .collect(),
                span: def.span,
            },
        );
    }

    fn register_enum(&mut self, def: &EnumDef) {
        if self.structs.contains_key(&def.name)
            || self.enums.contains_key(&def.name)
            || is_builtin_type(&def.name)
        {
            self.error(
                "E-LS-DUP",
                def.span,
                format!("type `{}` is already defined", def.name),
            );
            return;
        }
        self.check_generic_names(&def.generics, def.span);
        let mut seen = BTreeSet::new();
        for v in &def.variants {
            if !seen.insert(v.name.clone()) {
                self.error(
                    "E-LS-DUP",
                    v.span,
                    format!("duplicate variant `{}`", v.name),
                );
            }
        }
        self.enums.insert(
            def.name.clone(),
            EnumInfo {
                generics: def.generics.clone(),
                variants: def.variants.clone(),
                span: def.span,
            },
        );
    }

    fn register_fn(&mut self, def: &FnDef) {
        if self.functions.contains_key(&def.name) {
            self.error(
                "E-LS-DUP",
                def.span,
                format!("function `{}` is already defined", def.name),
            );
            return;
        }
        self.check_generic_names(&def.generics, def.span);
        let mut seen = BTreeSet::new();
        for p in &def.params {
            if !seen.insert(p.name.clone()) {
                self.error(
                    "E-LS-DUP",
                    p.span,
                    format!("duplicate parameter `{}`", p.name),
                );
            }
        }
        self.functions.insert(
            def.name.clone(),
            FnInfo {
                generics: def.generics.clone(),
                params: def.params.clone(),
                ret: def.ret.clone(),
                effects: def.effects.iter().cloned().collect(),
                span: def.span,
            },
        );
    }

    fn check_generic_names(&mut self, generics: &[GenericParam], span: Span) {
        let mut seen = BTreeSet::new();
        for g in generics {
            if !seen.insert(g.name.clone()) {
                self.error(
                    "E-LS-DUP",
                    g.span,
                    format!("duplicate generic parameter `{}`", g.name),
                );
            }
            if !is_known_trait(&g.bounds) {
                self.error(
                    "E-LS-TRAIT",
                    g.span,
                    format!(
                        "unknown trait bound(s) on `{}`: {}",
                        g.name,
                        g.bounds.join(", ")
                    ),
                );
            }
        }
        let _ = span;
    }

    fn check_decl_bounds(&mut self, program: &Program) {
        for def in &program.structs {
            let map = param_map(&def.generics);
            let params = bound_map(&def.generics);
            for (_, ty, span) in &def.fields {
                let mut constraints = Vec::new();
                self.collect_type_constraints(ty, &map, &params, *span, &mut constraints);
                self.solve_constraints(&constraints, &params);
            }
        }
        for def in &program.enums {
            let map = param_map(&def.generics);
            let params = bound_map(&def.generics);
            for v in &def.variants {
                for ty in &v.payload {
                    let mut constraints = Vec::new();
                    self.collect_type_constraints(ty, &map, &params, v.span, &mut constraints);
                    self.solve_constraints(&constraints, &params);
                }
            }
        }
    }

    fn check_fn(&mut self, def: &FnDef) {
        let ambient_name = format!("fn@{}#{}", def.name, self.region_serial);
        self.region_serial += 1;
        let ambient = match self.regions.add_child(ambient_name, &self.region_thread) {
            Ok(r) => r,
            Err(e) => {
                self.error("E-LS-REGION", def.span, format!("region error: {:?}", e));
                return;
            }
        };
        let generics = def
            .generics
            .iter()
            .map(|g| (g.name.clone(), g.bounds.iter().cloned().collect()))
            .collect::<BTreeMap<_, BTreeSet<_>>>();
        let mut ctx = FnCtx {
            name: def.name.clone(),
            ret: def.ret.clone(),
            ambient: ambient.clone(),
            current_region: ambient.clone(),
            generics,
            scopes: vec![BTreeMap::new()],
            region_names: vec![vec![
                ("static".to_string(), self.region_static.clone()),
                ("heap".to_string(), self.region_heap.clone()),
                ("thread".to_string(), self.region_thread.clone()),
                ("$fn".to_string(), ambient.clone()),
            ]],
            used_effects: BTreeSet::new(),
            constraints: Vec::new(),
            comptime_depth: 0,
            frozen: BTreeSet::new(),
            borrowed: BTreeSet::new(),
            guards: Vec::new(),
        };
        for p in &def.params {
            ctx.insert(
                p.name.clone(),
                VarInfo {
                    ty: p.ty.clone(),
                    mode: p.mode,
                    region: ambient.clone(),
                    footprint: [ambient.clone()].into_iter().collect(),
                    moved: false,
                    borrowed: false,
                    buffer: None,
                    allocations: Vec::new(),
                },
            );
        }
        // Requires clauses may only read parameters and must be pure.
        let mut contract_ctx_effects = BTreeSet::new();
        for req in &def.requires {
            let mut effects = BTreeSet::new();
            let ty = self.infer(req, &mut ctx, &mut effects);
            self.expect_bool(&ty.ty, req.span, "requires");
            contract_ctx_effects.extend(effects);
        }
        if !contract_ctx_effects.is_empty() {
            self.error(
                "E-LS-EFFECT",
                def.span,
                format!(
                    "requires clauses must be pure, found {}",
                    join_set(&contract_ctx_effects)
                ),
            );
        }
        let save_effects = ctx.used_effects.clone();
        ctx.used_effects = BTreeSet::new();
        // Ensures clauses additionally see `result`.
        ctx.insert(
            "result".to_string(),
            VarInfo {
                ty: def.ret.clone(),
                mode: ParamMode::Val,
                region: ambient.clone(),
                footprint: [ambient.clone()].into_iter().collect(),
                moved: false,
                borrowed: false,
                buffer: None,
                allocations: Vec::new(),
            },
        );
        let mut ensures_effects = BTreeSet::new();
        for ens in &def.ensures {
            let mut effects = BTreeSet::new();
            let ty = self.infer(ens, &mut ctx, &mut effects);
            self.expect_bool(&ty.ty, ens.span, "ensures");
            ensures_effects.extend(effects);
        }
        ctx.used_effects = save_effects;
        if !ensures_effects.is_empty() {
            self.error(
                "E-LS-EFFECT",
                def.span,
                format!(
                    "ensures clauses must be pure, found {}",
                    join_set(&ensures_effects)
                ),
            );
        }

        let mark = self.arena.mark();
        self.check_block(&def.body, &mut ctx);
        let _ = self.arena.reset_to(mark);
        if ctx.used_effects.iter().any(|e| !def.effects.contains(e)) {
            let missing = ctx
                .used_effects
                .iter()
                .filter(|e| !def.effects.contains(*e))
                .cloned()
                .collect::<BTreeSet<_>>();
            self.error(
                "E-LS-EFFECT",
                def.span,
                format!(
                    "function `{}` uses undeclared effect(s): {}",
                    def.name,
                    join_set(&missing)
                ),
            );
        }
        let constraints = std::mem::take(&mut ctx.constraints);
        self.solve_constraints(&constraints, &ctx.generics);
        for (name, info) in ctx.scopes.first().cloned().unwrap_or_default() {
            if name != "result" {
                self.check_binding_resolved(&info.ty, def.span, &format!("parameter `{}`", name));
            }
        }
    }

    // -- declarations / traits ------------------------------------------------

    fn check_static(&mut self, def: &StaticDef) {
        let generics = BTreeSet::new();
        self.check_type(&def.ty, def.span, &generics);
        let mut ctx = FnCtx {
            name: format!("static@{}", def.name),
            ret: Ty::Unit,
            ambient: self.region_static.clone(),
            current_region: self.region_static.clone(),
            generics: BTreeMap::new(),
            scopes: vec![BTreeMap::new()],
            region_names: vec![vec![
                ("static".to_string(), self.region_static.clone()),
                ("heap".to_string(), self.region_heap.clone()),
                ("thread".to_string(), self.region_thread.clone()),
            ]],
            used_effects: BTreeSet::new(),
            constraints: Vec::new(),
            comptime_depth: 0,
            frozen: BTreeSet::new(),
            borrowed: BTreeSet::new(),
            guards: Vec::new(),
        };
        let mut effects = BTreeSet::new();
        let init = self.infer(&def.init, &mut ctx, &mut effects);
        self.unify(&def.ty, &init.ty, def.span);
        self.statics.insert(
            def.name.clone(),
            VarInfo {
                ty: def.ty.clone(),
                mode: ParamMode::Val,
                region: self.region_static.clone(),
                footprint: [self.region_static.clone()].into_iter().collect(),
                moved: false,
                borrowed: false,
                buffer: None,
                allocations: Vec::new(),
            },
        );
    }

    fn check_binding_resolved(&mut self, ty: &Ty, span: Span, what: &str) {
        let ty = self.resolve(ty);
        if let Some(var) = first_unresolved(&ty) {
            self.error(
                "E-LS-INFER",
                span,
                format!(
                    "cannot infer type of {}: unresolved type variable ?{}",
                    what, var
                ),
            );
        }
    }

    fn type_exists(&mut self, ty: &Ty, span: Span) -> bool {
        if let Ty::Named(name, _) = ty {
            if is_builtin_type(name) {
                return true;
            }
        }
        match ty {
            Ty::Named(name, args) if name == "AllocError" || name == "Error" => {
                if args.is_empty() {
                    return true;
                }
                self.diagnostics.push(err(
                    "E-LS-ARITY",
                    span.start,
                    span.end,
                    format!("type `{}` expects no type arguments", name),
                ));
                false
            }
            Ty::Named(name, args) => {
                let Some(info) = self
                    .structs
                    .get(name)
                    .map(|s| s.generics.len())
                    .or_else(|| self.enums.get(name).map(|e| e.generics.len()))
                else {
                    self.diagnostics.push(err(
                        "E-LS-UNKNOWN-TYPE",
                        span.start,
                        span.end,
                        format!("unknown type `{}`", name),
                    ));
                    return false;
                };
                if info != args.len() {
                    self.diagnostics.push(err(
                        "E-LS-ARITY",
                        span.start,
                        span.end,
                        format!(
                            "type `{}` expects {} type argument(s), got {}",
                            name,
                            info,
                            args.len()
                        ),
                    ));
                    return false;
                }
                true
            }
            Ty::Slice(t) | Ty::Buffer(t) | Ty::Option(t) => self.type_exists(t, span),
            Ty::Result(t, e) => self.type_exists(t, span) && self.type_exists(e, span),
            Ty::Mode(_, t) | Ty::Atomic(t) | Ty::Array(t, _) | Ty::Lock(t, _) | Ty::Guard(t, _) => {
                self.type_exists(t, span)
            }
            Ty::Const(_) | Ty::JoinHandle => true,
            _ => true,
        }
    }

    fn check_type(&mut self, ty: &Ty, span: Span, generics: &BTreeSet<String>) {
        match ty {
            Ty::Param(name) => {
                if !generics.contains(name) {
                    self.error(
                        "E-LS-UNKNOWN-TYPE",
                        span,
                        format!("type parameter `{}` is not in scope", name),
                    );
                }
            }
            Ty::Named(_, args) => {
                if !self.type_exists(ty, span) {
                    return;
                }
                for a in args {
                    self.check_type(a, span, generics);
                }
            }
            Ty::Slice(t) | Ty::Buffer(t) | Ty::Option(t) => self.check_type(t, span, generics),
            Ty::Result(t, e) => {
                self.check_type(t, span, generics);
                self.check_type(e, span, generics);
            }
            Ty::Mode(_, t) | Ty::Atomic(t) | Ty::Array(t, _) | Ty::Lock(t, _) | Ty::Guard(t, _) => {
                self.check_type(t, span, generics)
            }
            _ => {}
        }
    }

    fn check_block(&mut self, block: &Block, ctx: &mut FnCtx) {
        ctx.scopes.push(BTreeMap::new());
        ctx.region_names.push(Vec::new());
        let guard_mark = ctx.guards.len();
        let mark = self.arena.mark();
        for stmt in &block.stmts {
            self.check_stmt(stmt, ctx);
        }
        let _ = self.arena.reset_to(mark);
        ctx.guards.truncate(guard_mark);
        ctx.region_names.pop();
        ctx.scopes.pop();
    }

    fn check_stmt(&mut self, stmt: &Stmt, ctx: &mut FnCtx) {
        match stmt {
            Stmt::Let {
                name,
                ann,
                init,
                span,
            } => {
                let mut effects = BTreeSet::new();
                self.check_plain_shared(init, init.span, ctx);
                let inferred = self.infer(init, ctx, &mut effects);
                self.check_move(init, &inferred.ty, ctx, init.span, "initializer");
                let ty = if let Some(ann) = ann {
                    let set = self.generic_set(ctx);
                    self.check_type(ann, *span, &set);
                    if !self.unify(ann, &inferred.ty, *span) {
                        self.error(
                            "E-LS-TYPE",
                            *span,
                            format!(
                                "let `{}` annotation `{}` does not match initializer `{}`",
                                name, ann, inferred.ty
                            ),
                        );
                    }
                    ann.clone()
                } else {
                    let resolved = self.resolve(&inferred.ty);
                    if first_unresolved(&resolved).is_some() {
                        self.error(
                            "E-LS-INFER",
                            *span,
                            format!("cannot infer type of `{}`: add a type annotation", name),
                        );
                    }
                    resolved
                };
                let region = inferred
                    .region
                    .unwrap_or_else(|| ctx.current_region.clone());
                if matches!(ty, Ty::Buffer(_)) && first_unresolved(&ty).is_none() {
                    // Buffer values carry their owning region.
                }
                ctx.insert(
                    name.clone(),
                    VarInfo {
                        ty: ty.clone(),
                        mode: ParamMode::Owned,
                        region,
                        footprint: inferred.footprint.clone(),
                        moved: false,
                        borrowed: false,
                        buffer: inferred.buffer.clone(),
                        allocations: inferred.allocations.clone(),
                    },
                );
                self.merge_effects(ctx, &effects);
                let _ = ty;
            }
            Stmt::Region { name, body, span } => {
                if ctx.visible_region(name).is_some() {
                    self.error(
                        "E-LS-REGION",
                        *span,
                        format!("region `{}` shadows an active region", name),
                    );
                }
                let parent = ctx
                    .region_names
                    .iter()
                    .rev()
                    .flat_map(|scope| scope.iter().rev())
                    .next()
                    .map(|(_, r)| r.clone())
                    .unwrap_or_else(|| ctx.current_region.clone());
                let unique = format!("{}#{}", name, self.region_serial);
                self.region_serial += 1;
                let region = match self.regions.add_child(unique, &parent) {
                    Ok(r) => r,
                    Err(e) => {
                        self.error("E-LS-REGION", *span, format!("region error: {:?}", e));
                        return;
                    }
                };
                self.region_count += 1;
                let mark = self.arena.mark();
                let saved_region = ctx.current_region.clone();
                ctx.current_region = region.clone();
                ctx.region_names.push(vec![(name.clone(), region)]);
                self.check_block(body, ctx);
                ctx.region_names.pop();
                ctx.current_region = saved_region;
                let reclaimed = self.arena.reset_to(mark).unwrap_or(0);
                let _ = reclaimed;
            }
            Stmt::Return { value, span } => {
                let mut effects = BTreeSet::new();
                if let Some(value) = value {
                    let inferred = self.infer(value, ctx, &mut effects);
                    let ret = self.resolve(&ctx.ret);
                    if !self.unify(&ret, &inferred.ty, *span) {
                        self.error(
                            "E-LS-TYPE",
                            *span,
                            format!(
                                "return type `{}` does not match value `{}`",
                                ret, inferred.ty
                            ),
                        );
                    }
                    self.check_escape(&inferred, ctx, *span, "return value");
                    self.check_move(value, &inferred.ty, ctx, *span, "return value");
                } else if !matches!(self.resolve(&ctx.ret), Ty::Unit) {
                    self.error(
                        "E-LS-TYPE",
                        *span,
                        format!("function must return `{}`", ctx.ret),
                    );
                }
                self.merge_effects(ctx, &effects);
            }
            Stmt::If {
                cond,
                then_block,
                else_block,
                span,
            } => {
                let mut effects = BTreeSet::new();
                let ty = self.infer(cond, ctx, &mut effects);
                self.expect_bool(&ty.ty, cond.span, "if condition");
                self.merge_effects(ctx, &effects);
                self.check_block(then_block, ctx);
                if let Some(block) = else_block {
                    self.check_block(block, ctx);
                }
                let _ = span;
            }
            Stmt::While { cond, body, .. } => {
                let mut effects = BTreeSet::new();
                let ty = self.infer(cond, ctx, &mut effects);
                self.expect_bool(&ty.ty, cond.span, "while condition");
                self.merge_effects(ctx, &effects);
                self.check_block(body, ctx);
            }
            Stmt::Comptime { body, span } => {
                ctx.comptime_depth += 1;
                self.check_block(body, ctx);
                ctx.comptime_depth -= 1;
                let _ = span;
            }
            Stmt::Drop { value, span } => {
                let mut effects = BTreeSet::new();
                let inferred = self.infer(value, ctx, &mut effects);
                if self.is_copy(&inferred.ty) {
                    self.error(
                        "E-LS-TYPE",
                        *span,
                        format!(
                            "drop requires an owning non-Copy place, found `{}`",
                            inferred.ty
                        ),
                    );
                }
                self.check_live_use(value, ctx, *span, "drop");
                self.check_move(value, &inferred.ty, ctx, *span, "drop");
                if inferred.allocations.is_empty() {
                    if let Some(state) = inferred.buffer {
                        self.reclaim_buffer(&state);
                    }
                } else {
                    self.reclaim_allocations(&inferred.allocations);
                }
                self.merge_effects(ctx, &effects);
            }
            Stmt::Borrow {
                mutable,
                place,
                alias,
                body,
                span,
            } => {
                let mut effects = BTreeSet::new();
                let base = self.infer(place, ctx, &mut effects);
                self.merge_effects(ctx, &effects);
                let target = place_of(place);
                if target.is_none() {
                    self.error("E-LS-MODE", *span, "borrow requires a place");
                }
                if let Some(p) = &target {
                    ctx.borrowed.insert(p.clone());
                }
                let inner = match self.resolve(&base.ty) {
                    Ty::Mode(_, t) => *t,
                    t => t,
                };
                let alias_ty = Ty::Mode(
                    if *mutable { ModeTag::Ref } else { ModeTag::Val },
                    Box::new(inner),
                );
                ctx.scopes.push(BTreeMap::new());
                ctx.insert(
                    alias.clone(),
                    VarInfo {
                        ty: alias_ty,
                        mode: if *mutable {
                            ParamMode::Ref
                        } else {
                            ParamMode::Val
                        },
                        region: ctx.ambient.clone(),
                        // A borrow aliases the target place: its footprint is
                        // the target's region (A-5: nested refs are tracked).
                        footprint: base.footprint.clone(),
                        moved: false,
                        borrowed: false,
                        buffer: None,
                        allocations: Vec::new(),
                    },
                );
                self.check_block(body, ctx);
                ctx.scopes.pop();
                if let Some(p) = target {
                    ctx.borrowed.remove(&p);
                }
            }
            Stmt::Assign {
                place,
                op,
                value,
                span,
            } => {
                let mut effects = BTreeSet::new();
                let base = self.infer(place, ctx, &mut effects);
                let target = place_of(place);
                if let Some(p) = &target {
                    let frozen = ctx.frozen.iter().any(|q| q.overlaps(p));
                    let borrowed = ctx.borrowed.iter().any(|q| q.overlaps(p));
                    if frozen || borrowed {
                        self.error(
                            "E-LS-ALIAS",
                            *span,
                            format!("cannot write `{}`: a live alias covers this place", p),
                        );
                    }
                    if let Some(info) = ctx.lookup(&p.root) {
                        if var_mode(info) == Some(ModeTag::Shared) && ctx.guards.is_empty() {
                            self.error(
                                "E-LS-RACE",
                                *span,
                                format!(
                                    "write to `{}` requires an atomic operation or a live Guard",
                                    p
                                ),
                            );
                        }
                    }
                }
                if op != "=" {
                    self.check_plain_shared(place, *span, ctx);
                }
                let v = self.infer(value, ctx, &mut effects);
                self.unify(&base.ty, &v.ty, value.span);
                self.check_move(value, &v.ty, ctx, value.span, "assignment");
                self.merge_effects(ctx, &effects);
            }
            Stmt::Expr(expr) => {
                let mut effects = BTreeSet::new();
                self.check_plain_shared(expr, expr.span, ctx);
                let ty = self.infer(expr, ctx, &mut effects);
                let resolved = self.resolve(&ty.ty);
                if first_unresolved(&resolved).is_some() {
                    self.error(
                        "E-LS-INFER",
                        expr.span,
                        "cannot infer type of expression result",
                    );
                }
                self.merge_effects(ctx, &effects);
            }
        }
    }

    fn generic_set(&self, ctx: &FnCtx) -> BTreeSet<String> {
        ctx.generics.keys().cloned().collect()
    }

    fn merge_effects(&mut self, ctx: &mut FnCtx, effects: &BTreeSet<String>) {
        for e in effects {
            if !is_known_effect(e) {
                continue;
            }
            ctx.used_effects.insert(e.clone());
        }
    }

    fn expect_bool(&mut self, ty: &Ty, span: Span, what: &str) {
        if !self.unify(&Ty::Bool, ty, span) {
            self.error(
                "E-LS-TYPE",
                span,
                format!("{} must be `Bool`, found `{}`", what, ty),
            );
        }
    }

    fn check_plain_shared(&mut self, expr: &Expr, span: Span, ctx: &FnCtx) {
        if let Some(place) = place_of(expr) {
            if let Some(info) = ctx.lookup(&place.root) {
                if var_mode(info) == Some(ModeTag::Shared) && ctx.guards.is_empty() {
                    self.error(
                        "E-LS-RACE",
                        span,
                        format!(
                            "plain access to `{}` requires an atomic operation or a live Guard",
                            place
                        ),
                    );
                }
            }
        }
    }

    fn transfer_mode(&self, expr: &Expr, ctx: &FnCtx) -> (Option<ModeTag>, BTreeSet<Region>) {
        match &expr.kind {
            ExprKind::Move(inner) => self.transfer_mode(inner, ctx),
            _ => {
                if let Some(place) = place_of(expr) {
                    if let Some(info) = ctx
                        .lookup(&place.root)
                        .or_else(|| self.statics.get(&place.root))
                    {
                        return (var_mode(info), info.footprint.clone());
                    }
                }
                (None, BTreeSet::new())
            }
        }
    }

    fn check_spawn(&mut self, inner: &Expr, ctx: &FnCtx) {
        let args: &[Expr] = match &inner.kind {
            ExprKind::Call { args, .. } => args,
            _ => {
                self.error("E-LS-MODE", inner.span, "spawn requires a call expression");
                return;
            }
        };
        for arg in args {
            let (mode, footprint) = self.transfer_mode(arg, ctx);
            match mode {
                Some(ModeTag::Iso) | Some(ModeTag::Atom) => {}
                Some(ModeTag::Val) => {
                    if let Some(r) = footprint
                        .iter()
                        .find(|r| !self.regions.outlives(r, &self.region_thread))
                    {
                        self.error(
                            "E-LS-RACE",
                            arg.span,
                            format!(
                                "`val` field in region `{}` cannot cross a domain (requires thread ⊑ Rgn*(v))",
                                r.0
                            ),
                        );
                    }
                }
                _ => self.error(
                    "E-LS-RACE",
                    arg.span,
                    "cross-domain transfer requires `iso`, `atom`, or a region-safe `val`",
                ),
            }
        }
    }

    fn check_escape(&mut self, value: &Inferred, ctx: &FnCtx, span: Span, what: &str) {
        if value.footprint.is_empty() {
            return;
        }
        let offending = value
            .footprint
            .iter()
            .find(|r| !self.regions.outlives(r, &ctx.ambient));
        if let Some(region) = offending {
            {
                // Core: return requires `ambient ⊑ value_region`; the region
                // tree says `value_region ⊑ ambient`.  The single required
                // constraint is already unsatisfiable because `ambient` is a
                // fixed site-bound region, so the 1-element core is minimal.
                let witness = if self.regions.outlives(&ctx.ambient, region) {
                    format!(
                        "; witness: `{}` ⊑ `{}` (region nesting)",
                        region.0, ctx.ambient.0
                    )
                } else {
                    String::new()
                };
                self.diagnostics.push(err_fix(
                    "E-LS-REGION-ESCAPE",
                    span.start,
                    span.end,
                    format!(
                        "{} escapes region `{}` (function ambient is `{}`); core (1 minimal): [return: `{}` ⊑ `{}`]{}",
                        what, region.0, ctx.ambient.0, ctx.ambient.0, region.0, witness
                    ),
                    "copy the value, allocate it in `heap`, or narrow the returned region",
                ));
            }
        }
    }

    fn check_move(&mut self, expr: &Expr, ty: &Ty, ctx: &mut FnCtx, span: Span, what: &str) {
        if self.is_copy(ty) {
            return;
        }
        let mut blocked = false;
        if let Some(place) = place_of(expr) {
            let frozen = ctx.frozen.iter().any(|q| q.overlaps(&place));
            let borrowed = ctx.borrowed.iter().any(|q| q.overlaps(&place));
            if frozen || borrowed {
                self.error(
                    "E-LS-ALIAS",
                    span,
                    format!("cannot move `{}` while it is borrowed or frozen", place),
                );
                blocked = true;
            }
        }
        if let ExprKind::Var(name) = &expr.kind {
            if let Some(info) = ctx.lookup(name) {
                if info.borrowed {
                    self.error(
                        "E-LS-ALIAS",
                        span,
                        format!("cannot move {} while `{}` has live slices", what, name),
                    );
                    blocked = true;
                } else if info.mode != ParamMode::Owned {
                    self.error(
                        "E-LS-MODE",
                        span,
                        format!(
                            "cannot move {} from `{}` parameter `{}`",
                            what,
                            match info.mode {
                                ParamMode::Val => "val",
                                ParamMode::Ref => "ref",
                                ParamMode::Owned => "owned",
                            },
                            name
                        ),
                    );
                } else if info.moved {
                    self.error("E-LS-MOVE", span, format!("use of moved value `{}`", name));
                }
            }
            if !blocked {
                if let Some(info) = ctx.lookup_mut(name) {
                    if info.mode == ParamMode::Owned {
                        info.moved = true;
                    }
                }
            }
        }
    }

    fn reclaim_allocations(&mut self, allocations: &[Allocation]) {
        let mut i = allocations.len();
        while i > 0 {
            i -= 1;
            let allocation = allocations[i];
            if allocation.offset + allocation.size == self.arena.used() {
                let _ = self.arena.reset_to(allocation.offset);
            }
        }
    }

    fn reclaim_buffer(&mut self, state: &BufferState) {
        let Some(allocation) = state.allocation else {
            return;
        };
        if allocation.offset + allocation.size == self.arena.used() {
            let _ = self.arena.reset_to(allocation.offset);
        }
    }

    fn check_live_use(&mut self, expr: &Expr, ctx: &FnCtx, span: Span, what: &str) {
        if let ExprKind::Var(name) = &expr.kind {
            if let Some(info) = ctx.lookup(name) {
                if info.moved {
                    self.error(
                        "E-LS-MOVE",
                        span,
                        format!("use of moved value `{}` as {}", name, what),
                    );
                }
            }
        }
    }

    fn infer(&mut self, expr: &Expr, ctx: &mut FnCtx, effects: &mut BTreeSet<String>) -> Inferred {
        if ctx.comptime_depth > 0 && !is_const_expr(expr) {
            self.error(
                "E-LS-COMPTIME",
                expr.span,
                "comptime block may only contain constant expressions",
            );
        }
        match &expr.kind {
            ExprKind::Int(_) => Inferred::plain(Ty::Int),
            ExprKind::Bool(_) => Inferred::plain(Ty::Bool),
            ExprKind::Str(_) => Inferred::new(Ty::Str, Some(self.region_static.clone())),
            ExprKind::Var(name) => {
                if name == "Order" {
                    return Inferred::plain(Ty::Named("Order".to_string(), Vec::new()));
                }
                if ctx.comptime_depth > 0 {
                    self.error(
                        "E-LS-COMPTIME",
                        expr.span,
                        format!("`{}` is not a compile-time constant", name),
                    );
                }
                if let Some(info) = ctx.lookup(name) {
                    let mut value = Inferred::new(info.ty.clone(), Some(info.region.clone()));
                    value.footprint = info.footprint.clone();
                    value.buffer = info.buffer;
                    value.allocations = info.allocations.clone();
                    value
                } else if let Some(info) = self.statics.get(name) {
                    Inferred::new(info.ty.clone(), Some(info.region.clone()))
                } else {
                    self.error(
                        "E-LS-UNBOUND",
                        expr.span,
                        format!("unknown name `{}`", name),
                    );
                    Inferred::plain(Ty::Error)
                }
            }
            ExprKind::Field(recv, field) => {
                let base = self.infer(recv, ctx, effects);
                self.check_live_use(recv, ctx, expr.span, "field access");
                if let Ty::Guard(inner, _) = self.resolve(&base.ty) {
                    let inner = self.resolve(&inner);
                    if let Ty::Named(name, args) = inner {
                        if let Some(info) = self.structs.get(&name).cloned() {
                            let map = type_param_map(&info.generics, &args);
                            if let Some((_, fty)) = info.fields.iter().find(|(n, _)| n == field) {
                                return Inferred::new(substitute(fty, &map), base.region.clone())
                                    .extend_footprint(base.footprint.clone());
                            }
                        }
                    }
                }
                let mut base_ty = self.resolve(&base.ty);
                if let Ty::Mode(_, inner) = base_ty.clone() {
                    base_ty = self.resolve(&inner);
                }
                if let Ty::Named(n, _) = &base_ty {
                    if n == "Order" {
                        return Inferred::plain(Ty::Named("OrderValue".to_string(), Vec::new()));
                    }
                }
                if field == "len" || field == "cap" {
                    let resolved = base_ty.clone();
                    let ok = if field == "cap" {
                        matches!(resolved, Ty::Buffer(_))
                    } else {
                        matches!(resolved, Ty::Buffer(_) | Ty::Slice(_) | Ty::Str)
                    };
                    if ok {
                        return Inferred::plain(Ty::Int);
                    }
                    self.error(
                        "E-LS-TYPE",
                        expr.span,
                        format!("`.{}` is not available on `{}`", field, base.ty),
                    );
                    return Inferred::plain(Ty::Error);
                }
                if let Ty::Named(name, args) = base_ty {
                    if let Some(info) = self.structs.get(&name).cloned() {
                        let map = type_param_map(&info.generics, &args);
                        if let Some((_, fty)) = info.fields.iter().find(|(n, _)| n == field) {
                            let fty = substitute(fty, &map);
                            return Inferred::new(
                                fty,
                                Some(base.region.unwrap_or_else(|| ctx.ambient.clone())),
                            )
                            .extend_footprint(base.footprint.clone());
                        }
                        self.error(
                            "E-LS-UNKNOWN-FIELD",
                            expr.span,
                            format!("type `{}` has no field `{}`", name, field),
                        );
                        return Inferred::plain(Ty::Error);
                    }
                }
                self.error(
                    "E-LS-TYPE",
                    expr.span,
                    format!("`{}` has no field `{}`", base.ty, field),
                );
                Inferred::plain(Ty::Error)
            }
            ExprKind::Call {
                callee,
                type_args,
                args,
            } => self.infer_call(expr, callee, type_args, args, ctx, effects),
            ExprKind::Unary { op, value } => {
                let v = self.infer(value, ctx, effects);
                match op.as_str() {
                    "!" => {
                        self.expect_bool(&v.ty, expr.span, "operand of `!`");
                        Inferred::plain(Ty::Bool)
                    }
                    "-" => {
                        if !self.unify(&Ty::Int, &v.ty, expr.span) {
                            self.error(
                                "E-LS-TYPE",
                                expr.span,
                                format!("unary `-` requires `Int`, found `{}`", v.ty),
                            );
                        }
                        Inferred::plain(Ty::Int)
                    }
                    _ => Inferred::plain(Ty::Error),
                }
            }
            ExprKind::Binary { op, left, right } => {
                let l = self.infer(left, ctx, effects);
                let r = self.infer(right, ctx, effects);
                match op.as_str() {
                    "&&" | "||" => {
                        self.expect_bool(&l.ty, left.span, "left operand");
                        self.expect_bool(&r.ty, right.span, "right operand");
                        Inferred::plain(Ty::Bool)
                    }
                    "==" | "!=" => {
                        if !self.unify(&l.ty, &r.ty, expr.span) {
                            self.error(
                                "E-LS-TYPE",
                                expr.span,
                                format!("cannot compare `{}` with `{}`", l.ty, r.ty),
                            );
                        }
                        ctx.constraints.push(Constraint {
                            ty: l.ty.clone(),
                            trait_name: "Eq".to_string(),
                            span: expr.span,
                        });
                        Inferred::plain(Ty::Bool)
                    }
                    "<" | "<=" | ">" | ">=" => {
                        if !self.unify(&l.ty, &r.ty, expr.span) {
                            self.error(
                                "E-LS-TYPE",
                                expr.span,
                                format!("cannot compare `{}` with `{}`", l.ty, r.ty),
                            );
                        }
                        ctx.constraints.push(Constraint {
                            ty: l.ty.clone(),
                            trait_name: "Ord".to_string(),
                            span: expr.span,
                        });
                        Inferred::plain(Ty::Bool)
                    }
                    "+" | "-" | "*" | "/" | "%" => {
                        let ty = if matches!(self.resolve(&l.ty), Ty::Var(_)) {
                            r.ty.clone()
                        } else {
                            l.ty.clone()
                        };
                        if !self.unify(&ty, &r.ty, expr.span) {
                            self.error(
                                "E-LS-TYPE",
                                expr.span,
                                format!("arithmetic operands differ: `{}` and `{}`", l.ty, r.ty),
                            );
                        }
                        ctx.constraints.push(Constraint {
                            ty: ty.clone(),
                            trait_name: "Arith".to_string(),
                            span: expr.span,
                        });
                        Inferred::plain(self.resolve(&ty))
                    }
                    _ => Inferred::plain(Ty::Error),
                }
            }
            ExprKind::Index { base, index } => {
                let b = self.infer(base, ctx, effects);
                let i = self.infer(index, ctx, effects);
                self.unify(&Ty::Int, &i.ty, index.span);
                let mut cur = self.resolve(&b.ty);
                loop {
                    match cur.clone() {
                        Ty::Array(t, _) | Ty::Buffer(t) => {
                            cur = self.resolve(&t);
                            break;
                        }
                        Ty::Mode(_, t) => cur = self.resolve(&t),
                        other => {
                            self.error(
                                "E-LS-TYPE",
                                expr.span,
                                format!("`{}` is not indexable", other),
                            );
                            return Inferred::plain(Ty::Error);
                        }
                    }
                }
                Inferred::new(cur, b.region).extend_footprint(b.footprint.clone())
            }
            ExprKind::StructLit { mode, name, fields } => {
                let Some(info) = self.structs.get(name).cloned() else {
                    self.error(
                        "E-LS-UNKNOWN-TYPE",
                        expr.span,
                        format!("unknown struct `{}`", name),
                    );
                    return Inferred::plain(Ty::Error);
                };
                let mut footprint = BTreeSet::new();
                for (fname, fexpr) in fields {
                    let v = self.infer(fexpr, ctx, effects);
                    footprint.extend(v.footprint.iter().cloned());
                    if let Some((_, fty)) = info.fields.iter().find(|(n, _)| n == fname) {
                        self.unify(fty, &v.ty, fexpr.span);
                    } else {
                        self.error(
                            "E-LS-UNKNOWN-FIELD",
                            fexpr.span,
                            format!("struct `{}` has no field `{}`", name, fname),
                        );
                    }
                }
                let base = Ty::Named(name.clone(), Vec::new());
                let ty = match mode {
                    Some(m) => Ty::Mode(*m, Box::new(base)),
                    None => base,
                };
                Inferred::new(ty, Some(ctx.current_region.clone())).extend_footprint(footprint)
            }
            ExprKind::Freeze(inner) => {
                let base = self.infer(inner, ctx, effects);
                if let Some(p) = place_of(inner) {
                    ctx.frozen.insert(p);
                }
                let inner_ty = match self.resolve(&base.ty) {
                    Ty::Mode(_, t) => *t,
                    t => t,
                };
                Inferred::new(Ty::Mode(ModeTag::Val, Box::new(inner_ty)), base.region)
                    .extend_footprint(base.footprint.clone())
            }
            ExprKind::Spawn(inner) => {
                // The spawned function's effects run in the target domain;
                // requiring the spawner to declare them would be wrong.
                let mut spawned_effects = BTreeSet::new();
                let _ = self.infer(inner, ctx, &mut spawned_effects);
                self.check_spawn(inner, ctx);
                Inferred::plain(Ty::JoinHandle)
            }
            ExprKind::Move(inner) => {
                let v = self.infer(inner, ctx, effects);
                self.check_move(inner, &v.ty, ctx, expr.span, "move");
                v
            }
            ExprKind::Try(inner) => {
                let v = self.infer(inner, ctx, effects);
                match self.resolve(&v.ty) {
                    Ty::Result(ok, err) => {
                        match self.resolve(&ctx.ret) {
                            Ty::Result(_, fn_err) => {
                                if !self.unify(&err, &fn_err, expr.span) {
                                    self.error(
                                        "E-LS-QUESTION",
                                        expr.span,
                                        format!(
                                            "`?` error type `{}` does not match function error type `{}`",
                                            err, fn_err
                                        ),
                                    );
                                }
                            }
                            other => {
                                self.error(
                                    "E-LS-QUESTION",
                                    expr.span,
                                    format!(
                                        "`?` requires a `Result` return type, found `{}`",
                                        other
                                    ),
                                );
                            }
                        }
                        Inferred {
                            ty: *ok,
                            region: v.region,
                            footprint: v.footprint,
                            buffer: v.buffer,
                            allocations: v.allocations,
                        }
                    }
                    other => {
                        self.error(
                            "E-LS-QUESTION",
                            expr.span,
                            format!("`?` requires `Result`, found `{}`", other),
                        );
                        Inferred::plain(Ty::Error)
                    }
                }
            }
        }
    }

    fn infer_call(
        &mut self,
        whole: &Expr,
        callee: &Expr,
        type_args: &[Ty],
        args: &[Expr],
        ctx: &mut FnCtx,
        effects: &mut BTreeSet<String>,
    ) -> Inferred {
        let path = callee_path(callee);
        let path_key = path.as_ref().map(|p| p.join("."));
        if path_key.as_deref() == Some("Buffer.slice") {
            return self.infer_buffer_slice(whole, type_args, args, ctx, effects);
        }
        if path_key.as_deref() == Some("Buffer.new")
            || path_key.as_deref() == Some("Buffer.try_new")
        {
            let fallible = path_key.as_deref() == Some("Buffer.try_new");
            return self.infer_buffer_new(whole, type_args, args, ctx, effects, fallible);
        }
        if path_key.as_deref() == Some("Array.zeroed") {
            return Inferred::plain(self.fresh_var());
        }
        if path_key.as_deref() == Some("join") {
            if args.len() != 1 {
                self.error("E-LS-ARITY", whole.span, "join expects one handle");
            } else {
                let _ = self.infer(&args[0], ctx, effects);
            }
            return Inferred::plain(Ty::Unit);
        }
        if path_key.as_deref() == Some("write") {
            effects.insert("Io".to_string());
            if args.len() != 1 {
                self.error("E-LS-ARITY", whole.span, "write expects one argument");
            } else {
                let a = self.infer(&args[0], ctx, effects);
                if !self.unify(&Ty::Str, &a.ty, args[0].span) {
                    self.error(
                        "E-LS-TYPE",
                        args[0].span,
                        format!("write expects `Str`, found `{}`", a.ty),
                    );
                }
            }
            return Inferred::plain(Ty::Unit);
        }
        if let Some(p) = &path {
            if p.len() == 2 && (p[0] == "Option" || p[0] == "Result") {
                return self.infer_builtin_enum(whole, &p[0], &p[1], type_args, args, ctx, effects);
            }
        }
        // Method call: receiver.push(value) / receiver.release() / receiver.len.
        if let ExprKind::Field(recv, method) = &callee.kind {
            // `Region.allocator()` yields an `Alloc[Region]` handle bound to
            // that region, so `handle.alloc(v)` can be attributed to it.
            if method == "allocator" {
                if let ExprKind::Var(region_name) = &recv.kind {
                    if let Some(region) = ctx.visible_region(region_name) {
                        return Inferred::new(
                            Ty::Named(
                                "Alloc".to_string(),
                                vec![Ty::Named("Region".to_string(), Vec::new())],
                            ),
                            Some(region),
                        );
                    }
                }
            }
            if method == "alloc" {
                let base = self.infer(recv, ctx, effects);
                if let Ty::Named(name, _) = self.resolve(&base.ty) {
                    if name == "Alloc" {
                        if args.len() != 1 {
                            self.error("E-LS-ARITY", whole.span, "alloc expects one value");
                            return Inferred::plain(Ty::Error);
                        }
                        let value = self.infer(&args[0], ctx, effects);
                        return Inferred::new(
                            Ty::Mode(ModeTag::Boxed, Box::new(value.ty)),
                            base.region,
                        );
                    }
                }
            }
            if !is_type_path(callee) && method == "lock" {
                let base = self.infer(recv, ctx, effects);
                match self.resolve(&base.ty) {
                    Ty::Lock(inner, rank) => {
                        if let Some((_, last)) = ctx.guards.last() {
                            if rank < *last {
                                self.error(
                                    "E-LS-IRQ",
                                    whole.span,
                                    format!(
                                        "lock rank {} acquired while rank {} is live (monotonicity violated)",
                                        rank, last
                                    ),
                                );
                            }
                        }
                        ctx.guards
                            .push((format!("guard#{}", ctx.guards.len()), rank));
                        return Inferred::new(Ty::Guard(inner, rank), None);
                    }
                    other => {
                        self.error(
                            "E-LS-TYPE",
                            whole.span,
                            format!("`.lock` requires `Lock[T, rank]`, found `{}`", other),
                        );
                        return Inferred::plain(Ty::Error);
                    }
                }
            }
            if !is_type_path(callee) && is_atomic_method(method) {
                let base = self.infer(recv, ctx, effects);
                let inner = match self.resolve(&base.ty) {
                    Ty::Mode(ModeTag::Shared, t) => *t,
                    other => {
                        self.error(
                            "E-LS-RACE",
                            whole.span,
                            format!(
                                "`{}` requires `shared[Atomic[T]]`, found `{}`",
                                method, other
                            ),
                        );
                        return Inferred::plain(Ty::Error);
                    }
                };
                let elem = match self.resolve(&inner) {
                    Ty::Atomic(t) => *t,
                    other => {
                        self.error(
                            "E-LS-RACE",
                            whole.span,
                            format!("`{}` requires `Atomic[T]`, found `{}`", method, other),
                        );
                        return Inferred::plain(Ty::Error);
                    }
                };
                for a in args {
                    let _ = self.infer(a, ctx, effects);
                }
                let ret = if method == "store" { Ty::Unit } else { elem };
                return Inferred::plain(ret);
            }
            if !is_type_path(callee) && method == "release" {
                let base = self.infer(recv, ctx, effects);
                match self.resolve(&base.ty) {
                    Ty::Buffer(_) => {
                        if !args.is_empty() {
                            self.error(
                                "E-LS-ARITY",
                                whole.span,
                                "Buffer.release expects no arguments",
                            );
                        }
                        if !matches!(recv.kind, ExprKind::Var(_) | ExprKind::Field(..)) {
                            self.error("E-LS-MODE", whole.span, "Buffer.release requires a place");
                        }
                        self.check_move(recv, &base.ty, ctx, whole.span, "Buffer release");
                        if base.allocations.is_empty() {
                            if let Some(state) = base.buffer {
                                self.reclaim_buffer(&state);
                            }
                        } else {
                            self.reclaim_allocations(&base.allocations);
                        }
                        if let ExprKind::Var(name) = &recv.kind {
                            if let Some(info) = ctx.lookup_mut(name) {
                                info.buffer = None;
                            }
                        }
                        return Inferred::plain(Ty::Unit);
                    }
                    other => {
                        self.error(
                            "E-LS-TYPE",
                            whole.span,
                            format!("`.release` requires `Buffer[T]`, found `{}`", other),
                        );
                        return Inferred::plain(Ty::Error);
                    }
                }
            }
            if !is_type_path(callee) && method == "push" {
                let base = self.infer(recv, ctx, effects);
                self.check_live_use(recv, ctx, whole.span, "Buffer receiver");
                match self.resolve(&base.ty) {
                    Ty::Buffer(elem) => {
                        if args.len() != 1 {
                            self.error("E-LS-ARITY", whole.span, "Buffer.push expects one value");
                            return Inferred::plain(Ty::Unit);
                        }
                        if let Some(mut state) = base.buffer {
                            if state.len >= state.capacity {
                                self.error(
                                    "E-LS-BUFFER-CAP",
                                    whole.span,
                                    format!(
                                        "Buffer.push exceeds capacity {} (already {} element(s))",
                                        state.capacity, state.len
                                    ),
                                );
                            } else {
                                state.len += 1;
                                if let ExprKind::Var(name) = &recv.kind {
                                    if let Some(info) = ctx.lookup_mut(name) {
                                        info.buffer = Some(state);
                                    }
                                }
                            }
                        }
                        let value = self.infer(&args[0], ctx, effects);
                        if !self.unify(&elem, &value.ty, args[0].span) {
                            self.error(
                                "E-LS-TYPE",
                                args[0].span,
                                format!("Buffer.push expects `{}`, found `{}`", elem, value.ty),
                            );
                        }
                        let dst = base
                            .region
                            .clone()
                            .unwrap_or_else(|| ctx.current_region.clone());
                        if let Some(src) = value
                            .footprint
                            .iter()
                            .find(|src| !self.regions.can_store(src, &dst))
                        {
                            self.diagnostics.push(err_fix(
                                "E-LS-REGION-ESCAPE",
                                args[0].span.start,
                                args[0].span.end,
                                format!(
                                    "field in region `{}` cannot be stored in Buffer of region `{}`; core (1 minimal): [store: `{}` ⊑ `{}`]",
                                    src.0, dst.0, dst.0, src.0
                                ),
                                "store the value in a region that outlives it (e.g. `heap`), or copy it".to_string(),
                            ));
                        }
                        self.check_move(
                            &args[0],
                            &value.ty,
                            ctx,
                            args[0].span,
                            "value into Buffer",
                        );
                        return Inferred::plain(Ty::Unit);
                    }
                    other => {
                        self.error(
                            "E-LS-TYPE",
                            whole.span,
                            format!("`.push` requires `Buffer[T]`, found `{}`", other),
                        );
                        return Inferred::plain(Ty::Error);
                    }
                }
            }
        }
        if let Some(path) = path {
            if let Some(info) = self.functions.get(&path[0]).cloned() {
                if path.len() != 1 {
                    self.error(
                        "E-LS-UNBOUND",
                        callee.span,
                        format!("unknown function `{}`", path.join(".")),
                    );
                    return Inferred::plain(Ty::Error);
                }
                return self.infer_user_fn(whole, &info, type_args, args, ctx, effects);
            }
            if let Some(info) = self.enums.get(&path[0]).cloned() {
                if path.len() != 2 {
                    self.error(
                        "E-LS-UNBOUND",
                        callee.span,
                        format!("unknown constructor `{}`", path.join(".")),
                    );
                    return Inferred::plain(Ty::Error);
                }
                return self.infer_user_enum(
                    whole, &path[0], &info, &path[1], type_args, args, ctx, effects,
                );
            }
            if let Some(info) = self.structs.get(&path[0]).cloned() {
                if path.len() != 2 || path[1] != "new" {
                    self.error(
                        "E-LS-UNBOUND",
                        callee.span,
                        format!("unknown constructor `{}`", path.join(".")),
                    );
                    return Inferred::plain(Ty::Error);
                }
                return self
                    .infer_struct_new(whole, &path[0], &info, type_args, args, ctx, effects);
            }
            self.error(
                "E-LS-UNBOUND",
                callee.span,
                format!("unknown function `{}`", path.join(".")),
            );
            return Inferred::plain(Ty::Error);
        }
        let base = self.infer(callee, ctx, effects);
        self.error(
            "E-LS-TYPE",
            whole.span,
            format!("`{}` is not callable", base.ty),
        );
        Inferred::plain(Ty::Error)
    }

    fn infer_buffer_slice(
        &mut self,
        whole: &Expr,
        type_args: &[Ty],
        args: &[Expr],
        ctx: &mut FnCtx,
        effects: &mut BTreeSet<String>,
    ) -> Inferred {
        if args.len() != 3 {
            self.error(
                "E-LS-ARITY",
                whole.span,
                "Buffer.slice expects (buffer, start, len)",
            );
            return Inferred::plain(Ty::Error);
        }
        let base = self.infer(&args[0], ctx, effects);
        self.check_live_use(&args[0], ctx, whole.span, "Buffer.slice receiver");
        let elem = match self.resolve(&base.ty) {
            Ty::Buffer(elem) => *elem,
            other => {
                self.error(
                    "E-LS-TYPE",
                    args[0].span,
                    format!("Buffer.slice requires Buffer[T], found `{}`", other),
                );
                return Inferred::plain(Ty::Error);
            }
        };
        if type_args.len() > 1 {
            self.error(
                "E-LS-ARITY",
                whole.span,
                "Buffer.slice accepts at most one type argument",
            );
        }
        if let Some(t) = type_args.first() {
            if !self.unify(t, &elem, whole.span) {
                self.error(
                    "E-LS-TYPE",
                    whole.span,
                    format!(
                        "Buffer.slice type argument `{}` does not match element `{}`",
                        t, elem
                    ),
                );
            }
        }
        let start = self.infer(&args[1], ctx, effects);
        let len = self.infer(&args[2], ctx, effects);
        if !self.unify(&Ty::Int, &start.ty, args[1].span) {
            self.error("E-LS-TYPE", args[1].span, "Buffer.slice start must be Int");
        }
        if !self.unify(&Ty::Int, &len.ty, args[2].span) {
            self.error("E-LS-TYPE", args[2].span, "Buffer.slice len must be Int");
        }
        if let Some(state) = base.buffer {
            if let (Some(s0), Some(n)) = (const_int(&args[1]), const_int(&args[2])) {
                if s0 < 0 || n < 0 || (s0 as usize).saturating_add(n as usize) > state.capacity {
                    self.error(
                        "E-LS-BUFFER-CAP",
                        whole.span,
                        format!(
                            "Buffer.slice range [{}, {}) exceeds capacity {}",
                            s0,
                            s0.saturating_add(n),
                            state.capacity
                        ),
                    );
                }
            }
        }
        if let ExprKind::Var(name) = &args[0].kind {
            if let Some(info) = ctx.lookup_mut(name) {
                info.borrowed = true;
            }
        }
        Inferred::new(Ty::Slice(Box::new(elem)), base.region)
    }

    fn infer_buffer_new(
        &mut self,
        whole: &Expr,
        type_args: &[Ty],
        args: &[Expr],
        ctx: &mut FnCtx,
        effects: &mut BTreeSet<String>,
        fallible: bool,
    ) -> Inferred {
        effects.insert("Alloc".to_string());
        if args.len() != 2 {
            self.error(
                "E-LS-ARITY",
                whole.span,
                "Buffer allocation expects (capacity, region)",
            );
            return Inferred::plain(Ty::Error);
        }
        let elem = match type_args {
            [t] => t.clone(),
            [] => self.fresh_var(),
            _ => {
                self.error(
                    "E-LS-ARITY",
                    whole.span,
                    "Buffer allocation expects exactly one type argument",
                );
                return Inferred::plain(Ty::Error);
            }
        };
        let mut cap_effects = BTreeSet::new();
        let cap_value = match const_int(&args[0]) {
            Some(v) if v >= 0 => v as usize,
            Some(_) => {
                self.error(
                    "E-LS-ALLOC",
                    args[0].span,
                    "Buffer capacity must be a non-negative constant integer",
                );
                let _ = self.infer(&args[0], ctx, &mut cap_effects);
                0
            }
            None => {
                self.error(
                    "E-LS-ALLOC",
                    args[0].span,
                    "Buffer capacity must be a constant integer expression for static budget checking",
                );
                let _ = self.infer(&args[0], ctx, &mut cap_effects);
                0
            }
        };
        if cap_effects.iter().any(|e| e != "Alloc") {
            self.error(
                "E-LS-EFFECT",
                args[0].span,
                "capacity expression must be pure",
            );
        }
        let region = match &args[1].kind {
            ExprKind::Var(name) => match ctx.visible_region(name) {
                Some(r) => Some(r),
                None => {
                    self.error(
                        "E-LS-REGION",
                        args[1].span,
                        format!("unknown region `{}`", name),
                    );
                    None
                }
            },
            _ => {
                self.error(
                    "E-LS-REGION",
                    args[1].span,
                    "Buffer allocation requires a region name",
                );
                None
            }
        };
        let elem_size = self.size_of(&elem);
        let alloc = self
            .arena
            .alloc_elems(cap_value.max(1), elem_size.max(1), 8);
        let mut alloc_failed = false;
        match &alloc {
            Ok(_) => {}
            Err(_) => {
                alloc_failed = true;
                if !fallible {
                    self.error(
                        "E-LS-ALLOC",
                        whole.span,
                        format!(
                            "Buffer[{}] with capacity {} exceeds arena budget {}",
                            elem,
                            cap_value,
                            self.arena.budget()
                        ),
                    );
                }
            }
        }
        let buffer_ty = Ty::Buffer(Box::new(elem));
        if fallible {
            let result = Ty::Result(
                Box::new(buffer_ty),
                Box::new(Ty::Named("AllocError".to_string(), Vec::new())),
            );
            let _ = alloc_failed;
            Inferred::new(result, region).with_buffer(cap_value, alloc.as_ref().ok().copied())
        } else {
            Inferred::new(buffer_ty, region).with_buffer(cap_value, alloc.as_ref().ok().copied())
        }
    }

    fn infer_builtin_enum(
        &mut self,
        whole: &Expr,
        name: &str,
        variant: &str,
        type_args: &[Ty],
        args: &[Expr],
        ctx: &mut FnCtx,
        effects: &mut BTreeSet<String>,
    ) -> Inferred {
        let (ok_ty, err_ty) = match name {
            "Option" => {
                let t = if type_args.len() == 1 {
                    type_args[0].clone()
                } else {
                    if !type_args.is_empty() {
                        self.error("E-LS-ARITY", whole.span, "Option expects one type argument");
                    }
                    self.fresh_var()
                };
                (t, None)
            }
            "Result" => {
                let (t, e) = if type_args.len() == 2 {
                    (type_args[0].clone(), type_args[1].clone())
                } else if type_args.is_empty() {
                    (self.fresh_var(), self.fresh_var())
                } else {
                    self.error(
                        "E-LS-ARITY",
                        whole.span,
                        "Result expects two type arguments",
                    );
                    (self.fresh_var(), self.fresh_var())
                };
                (t, Some(e))
            }
            _ => unreachable!(),
        };
        let payload_ty = match (name, variant) {
            ("Option", "Some") => Some(ok_ty.clone()),
            ("Option", "None") => None,
            ("Result", "Ok") => Some(ok_ty.clone()),
            ("Result", "Err") => Some(err_ty.clone().unwrap_or_else(|| self.fresh_var())),
            _ => {
                self.error(
                    "E-LS-UNBOUND",
                    whole.span,
                    format!("unknown constructor `{}.{}`", name, variant),
                );
                return Inferred::plain(Ty::Error);
            }
        };
        let expected_args = usize::from(payload_ty.is_some());
        if args.len() != expected_args {
            self.error(
                "E-LS-ARITY",
                whole.span,
                format!(
                    "{}.{} expects {} argument(s), got {}",
                    name,
                    variant,
                    expected_args,
                    args.len()
                ),
            );
        }
        let mut value_region = None;
        let mut allocations = Vec::new();
        let mut footprint = BTreeSet::new();
        if let (Some(want), Some(arg)) = (payload_ty, args.first()) {
            let got = self.infer(arg, ctx, effects);
            footprint.extend(got.footprint.iter().cloned());
            if !self.unify(&want, &got.ty, arg.span) {
                self.error(
                    "E-LS-TYPE",
                    arg.span,
                    format!("payload type `{}` does not match `{}`", got.ty, want),
                );
            }
            value_region = self.merge_value_region(value_region, &got);
            allocations.extend(got.allocations.iter().copied());
            self.check_move(arg, &got.ty, ctx, arg.span, "payload");
        }
        for extra in args.iter().skip(expected_args) {
            let _ = self.infer(extra, ctx, effects);
        }
        let ty = match name {
            "Option" => Ty::Option(Box::new(ok_ty)),
            _ => Ty::Result(Box::new(ok_ty), Box::new(err_ty.unwrap())),
        };
        let mut value = Inferred::new(
            ty,
            value_region.or_else(|| Some(ctx.current_region.clone())),
        );
        value.footprint.extend(footprint);
        value.allocations = allocations;
        value
    }

    fn infer_user_enum(
        &mut self,
        whole: &Expr,
        name: &str,
        info: &EnumInfo,
        variant: &str,
        type_args: &[Ty],
        args: &[Expr],
        ctx: &mut FnCtx,
        effects: &mut BTreeSet<String>,
    ) -> Inferred {
        let map = self.instantiate_generics(&info.generics, type_args, whole.span);
        let vars = info
            .generics
            .iter()
            .map(|g| {
                map.get(&g.name)
                    .cloned()
                    .unwrap_or_else(|| self.fresh_var())
            })
            .collect::<Vec<_>>();
        let ty = Ty::Named(name.to_string(), vars.clone());
        let Some(v) = info.variants.iter().find(|v| v.name == variant) else {
            self.error(
                "E-LS-UNBOUND",
                whole.span,
                format!("enum `{}` has no variant `{}`", name, variant),
            );
            return Inferred::plain(Ty::Error);
        };
        if args.len() != v.payload.len() {
            self.error(
                "E-LS-ARITY",
                whole.span,
                format!(
                    "{}.{} expects {} payload value(s), got {}",
                    name,
                    variant,
                    v.payload.len(),
                    args.len()
                ),
            );
        }
        let mut value_region = None;
        let mut allocations = Vec::new();
        let mut footprint = BTreeSet::new();
        for (i, want) in v.payload.iter().enumerate() {
            let want = substitute(want, &map);
            if let Some(arg) = args.get(i) {
                let got = self.infer(arg, ctx, effects);
                if !self.unify(&want, &got.ty, arg.span) {
                    self.error(
                        "E-LS-TYPE",
                        arg.span,
                        format!("payload {} expects `{}`, found `{}`", i, want, got.ty),
                    );
                }
                value_region = self.merge_value_region(value_region, &got);
                allocations.extend(got.allocations.iter().copied());
                footprint.extend(got.footprint.iter().cloned());
                self.check_move(arg, &got.ty, ctx, arg.span, "payload");
            }
        }
        self.add_bound_constraints(&vars, &info.generics, &mut ctx.constraints, whole.span);
        let mut value = Inferred::new(
            ty,
            value_region.or_else(|| Some(ctx.current_region.clone())),
        );
        value.footprint.extend(footprint);
        value.allocations = allocations;
        value
    }

    fn infer_struct_new(
        &mut self,
        whole: &Expr,
        name: &str,
        info: &StructInfo,
        type_args: &[Ty],
        args: &[Expr],
        ctx: &mut FnCtx,
        effects: &mut BTreeSet<String>,
    ) -> Inferred {
        let map = self.instantiate_generics(&info.generics, type_args, whole.span);
        let vars = info
            .generics
            .iter()
            .map(|g| {
                map.get(&g.name)
                    .cloned()
                    .unwrap_or_else(|| self.fresh_var())
            })
            .collect::<Vec<_>>();
        let ty = Ty::Named(name.to_string(), vars.clone());
        if args.len() != info.fields.len() {
            self.error(
                "E-LS-ARITY",
                whole.span,
                format!(
                    "{}::new expects {} argument(s), got {}",
                    name,
                    info.fields.len(),
                    args.len()
                ),
            );
        }
        let mut value_region = None;
        let mut allocations = Vec::new();
        for (i, (fname, fty)) in info.fields.iter().enumerate() {
            let want = substitute(fty, &map);
            if let Some(arg) = args.get(i) {
                let got = self.infer(arg, ctx, effects);
                if !self.unify(&want, &got.ty, arg.span) {
                    self.error(
                        "E-LS-TYPE",
                        arg.span,
                        format!("field `{}` expects `{}`, found `{}`", fname, want, got.ty),
                    );
                }
                value_region = self.merge_value_region(value_region, &got);
                allocations.extend(got.allocations.iter().copied());
                self.check_move(arg, &got.ty, ctx, arg.span, "field value");
            }
        }
        self.add_bound_constraints(&vars, &info.generics, &mut ctx.constraints, whole.span);
        let mut value = Inferred::new(
            ty,
            value_region.or_else(|| Some(ctx.current_region.clone())),
        );
        value.allocations = allocations;
        value
    }

    fn infer_user_fn(
        &mut self,
        whole: &Expr,
        info: &FnInfo,
        type_args: &[Ty],
        args: &[Expr],
        ctx: &mut FnCtx,
        effects: &mut BTreeSet<String>,
    ) -> Inferred {
        let map = self.instantiate_generics(&info.generics, type_args, whole.span);
        if args.len() != info.params.len() {
            self.error(
                "E-LS-ARITY",
                whole.span,
                format!(
                    "function expects {} argument(s), got {}",
                    info.params.len(),
                    args.len()
                ),
            );
        }
        let vars = info
            .generics
            .iter()
            .map(|g| {
                map.get(&g.name)
                    .cloned()
                    .unwrap_or_else(|| self.fresh_var())
            })
            .collect::<Vec<_>>();
        for (i, param) in info.params.iter().enumerate() {
            let want = substitute(&param.ty, &map);
            if let Some(arg) = args.get(i) {
                let got = self.infer(arg, ctx, effects);
                if !self.unify(&want, &got.ty, arg.span) {
                    self.error(
                        "E-LS-TYPE",
                        arg.span,
                        format!("argument {} expects `{}`, found `{}`", i, want, got.ty),
                    );
                }
                match param.mode {
                    ParamMode::Ref => {
                        if !matches!(arg.kind, ExprKind::Var(_) | ExprKind::Field(..)) {
                            self.error(
                                "E-LS-MODE",
                                arg.span,
                                "`ref` parameter requires a place argument",
                            );
                        }
                    }
                    ParamMode::Owned => {
                        self.check_move(arg, &got.ty, ctx, arg.span, "argument");
                    }
                    ParamMode::Val => {}
                }
            }
        }
        for extra in args.iter().skip(info.params.len()) {
            let _ = self.infer(extra, ctx, effects);
        }
        for e in &info.effects {
            effects.insert(e.clone());
        }
        self.add_bound_constraints(&vars, &info.generics, &mut ctx.constraints, whole.span);
        Inferred::new(substitute(&info.ret, &map), Some(ctx.ambient.clone()))
    }

    fn instantiate_generics(
        &mut self,
        generics: &[GenericParam],
        explicit: &[Ty],
        span: Span,
    ) -> BTreeMap<String, Ty> {
        if !explicit.is_empty() && explicit.len() != generics.len() {
            self.error(
                "E-LS-ARITY",
                span,
                format!(
                    "expected {} type argument(s), got {}",
                    generics.len(),
                    explicit.len()
                ),
            );
        }
        let mut map = BTreeMap::new();
        for (i, g) in generics.iter().enumerate() {
            let ty = explicit.get(i).cloned().unwrap_or_else(|| self.fresh_var());
            map.insert(g.name.clone(), ty);
        }
        map
    }

    fn add_bound_constraints(
        &self,
        vars: &[Ty],
        generics: &[GenericParam],
        out: &mut Vec<Constraint>,
        span: Span,
    ) {
        for (v, g) in vars.iter().zip(generics) {
            for bound in &g.bounds {
                out.push(Constraint {
                    ty: v.clone(),
                    trait_name: bound.clone(),
                    span,
                });
            }
        }
    }

    fn fresh_var(&mut self) -> Ty {
        let v = self.next_var;
        self.next_var += 1;
        Ty::Var(v)
    }

    // -- unification ---------------------------------------------------------

    fn resolve(&self, ty: &Ty) -> Ty {
        match ty {
            Ty::Var(v) => self
                .subst
                .get(v)
                .map(|t| self.resolve(t))
                .unwrap_or_else(|| ty.clone()),
            Ty::Slice(t) => Ty::Slice(Box::new(self.resolve(t))),
            Ty::Buffer(t) => Ty::Buffer(Box::new(self.resolve(t))),
            Ty::Option(t) => Ty::Option(Box::new(self.resolve(t))),
            Ty::Result(t, e) => Ty::Result(Box::new(self.resolve(t)), Box::new(self.resolve(e))),
            Ty::Named(n, args) => {
                Ty::Named(n.clone(), args.iter().map(|a| self.resolve(a)).collect())
            }
            _ => ty.clone(),
        }
    }

    fn unify(&mut self, a: &Ty, b: &Ty, span: Span) -> bool {
        let a = self.resolve(a);
        let b = self.resolve(b);
        if a == b {
            return true;
        }
        match (&a, &b) {
            (Ty::Error, _) | (_, Ty::Error) => true,
            (Ty::Var(v), _) => self.bind_var(*v, &b, span),
            (_, Ty::Var(v)) => self.bind_var(*v, &a, span),
            (Ty::Slice(x), Ty::Slice(y))
            | (Ty::Buffer(x), Ty::Buffer(y))
            | (Ty::Option(x), Ty::Option(y)) => self.unify(x, y, span),
            (Ty::Result(x1, y1), Ty::Result(x2, y2)) => {
                self.unify(x1, x2, span) && self.unify(y1, y2, span)
            }
            (Ty::Mode(m1, x), Ty::Mode(m2, y)) if m1 == m2 => self.unify(x, y, span),
            // Mode erasure: `val[T]` / `iso[T]` are compatible with `T` at this
            // skeleton level (the mode is tracked separately in VarInfo).
            (Ty::Mode(_, x), y) if *x.as_ref() == *y => true,
            (x, Ty::Mode(_, y)) if *x == *y.as_ref() => true,
            (Ty::Atomic(x), Ty::Atomic(y)) => self.unify(x, y, span),
            (Ty::Array(x, n1), Ty::Array(y, n2)) if n1 == n2 => self.unify(x, y, span),
            (Ty::Lock(x, r1), Ty::Lock(y, r2)) if r1 == r2 => self.unify(x, y, span),
            (Ty::Guard(x, r1), Ty::Guard(y, r2)) if r1 == r2 => self.unify(x, y, span),
            (Ty::Const(a), Ty::Const(b)) => a == b,
            (Ty::Named(n1, a1), Ty::Named(n2, a2)) if n1 == n2 && a1.len() == a2.len() => {
                for (x, y) in a1.iter().zip(a2) {
                    if !self.unify(x, y, span) {
                        return false;
                    }
                }
                true
            }
            _ => {
                let _ = span;
                false
            }
        }
    }

    fn bind_var(&mut self, var: u32, ty: &Ty, span: Span) -> bool {
        if self.occurs(var, ty) {
            self.error(
                "E-LS-TYPE",
                span,
                format!("infinite type: ?{} occurs in `{}`", var, ty),
            );
            return false;
        }
        self.subst.insert(var, ty.clone());
        true
    }

    fn occurs(&self, var: u32, ty: &Ty) -> bool {
        match self.resolve(ty) {
            Ty::Var(v) => v == var,
            Ty::Slice(t) | Ty::Buffer(t) | Ty::Option(t) => self.occurs(var, &t),
            Ty::Result(t, e) => self.occurs(var, &t) || self.occurs(var, &e),
            Ty::Named(_, args) => args.iter().any(|a| self.occurs(var, a)),
            Ty::Mode(_, t) | Ty::Atomic(t) | Ty::Array(t, _) | Ty::Lock(t, _) | Ty::Guard(t, _) => {
                self.occurs(var, &t)
            }
            _ => false,
        }
    }

    fn solve_constraints(
        &mut self,
        constraints: &[Constraint],
        bounds: &BTreeMap<String, BTreeSet<String>>,
    ) {
        for c in constraints {
            let ty = self.resolve(&c.ty);
            match &ty {
                Ty::Var(v) => {
                    self.error(
                        "E-LS-INFER",
                        c.span,
                        format!(
                            "cannot prove `{}: {}`: unresolved type variable ?{}",
                            ty, c.trait_name, v
                        ),
                    );
                }
                Ty::Param(name) => {
                    let has = bounds
                        .get(name)
                        .map(|b| b.contains(&c.trait_name))
                        .unwrap_or(false);
                    if !has {
                        self.error(
                            "E-LS-TRAIT",
                            c.span,
                            format!(
                                "type parameter `{}` does not satisfy `{}`; add `{}: {}`",
                                name, c.trait_name, name, c.trait_name
                            ),
                        );
                    }
                }
                _ => {
                    if !self.satisfies(&ty, &c.trait_name) {
                        self.error(
                            "E-LS-TRAIT",
                            c.span,
                            format!("type `{}` does not implement `{}`", ty, c.trait_name),
                        );
                    }
                }
            }
        }
    }

    fn satisfies(&self, ty: &Ty, trait_name: &str) -> bool {
        let ty = match self.resolve(ty) {
            Ty::Mode(_, inner) => self.resolve(&inner),
            other => other,
        };
        match trait_name {
            "Copy" => self.is_copy(&ty),
            "Eq" => self.is_eq(&ty),
            "Ord" => self.is_ord(&ty),
            "Arith" => matches!(ty, Ty::Int | Ty::U8),
            "Alloc" => matches!(ty, Ty::Buffer(_)),
            _ => false,
        }
    }

    fn merge_value_region(&self, acc: Option<Region>, value: &Inferred) -> Option<Region> {
        if self.is_copy(&value.ty) {
            return acc;
        }
        match (&acc, &value.region) {
            (None, r) => r.clone(),
            (Some(a), Some(b)) => self.regions.common(a, b).or_else(|| Some(a.clone())),
            (Some(a), None) => Some(a.clone()),
        }
    }

    fn is_copy(&self, ty: &Ty) -> bool {
        match self.resolve(ty) {
            Ty::Unit | Ty::Int | Ty::U8 | Ty::Bool => true,
            Ty::Str => true,
            Ty::Mode(ModeTag::Val, _) => true,
            Ty::Array(t, _) => self.is_copy(&t),
            Ty::Const(_) | Ty::JoinHandle => true,
            Ty::Mode(_, _) | Ty::Atomic(_) | Ty::Lock(_, _) | Ty::Guard(_, _) => false,
            Ty::Named(name, args) => {
                if let Some(s) = self.structs.get(&name) {
                    let map = type_param_map(&s.generics, &args);
                    s.fields
                        .iter()
                        .all(|(_, t)| self.is_copy(&substitute(t, &map)))
                } else if let Some(e) = self.enums.get(&name) {
                    let map = type_param_map(&e.generics, &args);
                    e.variants
                        .iter()
                        .all(|v| v.payload.iter().all(|t| self.is_copy(&substitute(t, &map))))
                } else {
                    name == "AllocError" || name == "Error"
                }
            }
            _ => false,
        }
    }

    fn is_eq(&self, ty: &Ty) -> bool {
        match self.resolve(ty) {
            Ty::Unit | Ty::Int | Ty::U8 | Ty::Bool | Ty::Str => true,
            Ty::Slice(t) | Ty::Option(t) => self.is_eq(&t),
            Ty::Buffer(_) => false,
            Ty::Array(t, _) => self.is_eq(&t),
            Ty::Mode(_, _) | Ty::Atomic(_) | Ty::Lock(_, _) | Ty::Guard(_, _) => false,
            Ty::Result(t, e) => self.is_eq(&t) && self.is_eq(&e),
            Ty::Named(name, args) => {
                if let Some(s) = self.structs.get(&name) {
                    let map = type_param_map(&s.generics, &args);
                    s.fields
                        .iter()
                        .all(|(_, t)| self.is_eq(&substitute(t, &map)))
                } else if let Some(e) = self.enums.get(&name) {
                    let map = type_param_map(&e.generics, &args);
                    e.variants
                        .iter()
                        .all(|v| v.payload.iter().all(|t| self.is_eq(&substitute(t, &map))))
                } else {
                    false
                }
            }
            _ => false,
        }
    }

    fn is_ord(&self, ty: &Ty) -> bool {
        match self.resolve(ty) {
            Ty::Unit | Ty::Int | Ty::U8 | Ty::Bool | Ty::Str => true,
            Ty::Slice(t) | Ty::Option(t) => self.is_ord(&t),
            Ty::Buffer(_) => false,
            Ty::Array(t, _) => self.is_ord(&t),
            Ty::Mode(_, _) | Ty::Atomic(_) | Ty::Lock(_, _) | Ty::Guard(_, _) => false,
            Ty::Result(t, e) => self.is_ord(&t) && self.is_ord(&e),
            Ty::Named(name, args) => {
                if let Some(s) = self.structs.get(&name) {
                    let map = type_param_map(&s.generics, &args);
                    s.fields
                        .iter()
                        .all(|(_, t)| self.is_ord(&substitute(t, &map)))
                } else if let Some(e) = self.enums.get(&name) {
                    let map = type_param_map(&e.generics, &args);
                    e.variants
                        .iter()
                        .all(|v| v.payload.iter().all(|t| self.is_ord(&substitute(t, &map))))
                } else {
                    false
                }
            }
            _ => false,
        }
    }

    fn size_of(&self, ty: &Ty) -> usize {
        match self.resolve(ty) {
            Ty::Unit => 0,
            Ty::U8 | Ty::Bool => 1,
            Ty::Int | Ty::Str => 8,
            Ty::Slice(_) => 16,
            Ty::Buffer(_) | Ty::Option(_) | Ty::Result(_, _) | Ty::Named(_, _) | Ty::Param(_) => 8,
            Ty::Mode(_, _)
            | Ty::Atomic(_)
            | Ty::Array(_, _)
            | Ty::Lock(_, _)
            | Ty::Guard(_, _)
            | Ty::Const(_)
            | Ty::JoinHandle => 8,
            Ty::Var(_) | Ty::Error => 8,
        }
    }

    fn collect_type_constraints(
        &self,
        ty: &Ty,
        map: &BTreeMap<String, Ty>,
        bounds: &BTreeMap<String, BTreeSet<String>>,
        span: Span,
        out: &mut Vec<Constraint>,
    ) {
        match ty {
            Ty::Param(name) => {
                if let Some(ty) = map.get(name) {
                    for b in bounds.get(name).cloned().unwrap_or_default() {
                        out.push(Constraint {
                            ty: ty.clone(),
                            trait_name: b,
                            span,
                        });
                    }
                }
            }
            Ty::Slice(t) | Ty::Buffer(t) | Ty::Option(t) => {
                self.collect_type_constraints(t, map, bounds, span, out)
            }
            Ty::Result(t, e) => {
                self.collect_type_constraints(t, map, bounds, span, out);
                self.collect_type_constraints(e, map, bounds, span, out);
            }
            Ty::Named(_, args) => {
                for a in args {
                    self.collect_type_constraints(a, map, bounds, span, out);
                }
            }
            _ => {}
        }
    }
}

#[derive(Clone, Debug)]
struct Inferred {
    ty: Ty,
    region: Option<Region>,
    /// `Rgn*`: every region reachable through ref/val/box/slice fields.
    footprint: BTreeSet<Region>,
    buffer: Option<BufferState>,
    allocations: Vec<Allocation>,
}

impl Inferred {
    fn plain(ty: Ty) -> Self {
        Self {
            ty,
            region: None,
            footprint: BTreeSet::new(),
            buffer: None,
            allocations: Vec::new(),
        }
    }
    fn new(ty: Ty, region: Option<Region>) -> Self {
        let footprint = region.iter().cloned().collect();
        Self {
            ty,
            region,
            footprint,
            buffer: None,
            allocations: Vec::new(),
        }
    }
    fn extend_footprint(mut self, fp: impl IntoIterator<Item = Region>) -> Self {
        self.footprint.extend(fp);
        self
    }
    fn with_buffer(mut self, capacity: usize, allocation: Option<Allocation>) -> Self {
        self.buffer = Some(BufferState {
            capacity,
            len: 0,
            allocation,
        });
        if let Some(a) = allocation {
            self.allocations.push(a);
        }
        self
    }
}

fn const_int(expr: &Expr) -> Option<i64> {
    match &expr.kind {
        ExprKind::Int(v) => Some(*v),
        ExprKind::Unary { op, value } if op == "-" => {
            const_int(value).and_then(|v| v.checked_neg())
        }
        ExprKind::Binary { op, left, right } => {
            let a = const_int(left)?;
            let b = const_int(right)?;
            match op.as_str() {
                "+" => a.checked_add(b),
                "-" => a.checked_sub(b),
                "*" => a.checked_mul(b),
                "/" => a.checked_div(b),
                "%" => a.checked_rem(b),
                _ => None,
            }
        }
        _ => None,
    }
}

fn is_const_expr(expr: &Expr) -> bool {
    match &expr.kind {
        ExprKind::Int(_) | ExprKind::Bool(_) | ExprKind::Str(_) => true,
        ExprKind::Unary { value, .. } => is_const_expr(value),
        ExprKind::Binary { left, right, .. } => is_const_expr(left) && is_const_expr(right),
        _ => false,
    }
}

fn mode_of_ty(ty: &Ty) -> Option<ModeTag> {
    match ty {
        Ty::Mode(m, _) => Some(*m),
        _ => None,
    }
}

fn var_mode(info: &VarInfo) -> Option<ModeTag> {
    mode_of_ty(&info.ty).or(match info.mode {
        ParamMode::Val => Some(ModeTag::Val),
        ParamMode::Ref => Some(ModeTag::Ref),
        ParamMode::Owned => None,
    })
}

fn place_of(expr: &Expr) -> Option<Place> {
    match &expr.kind {
        ExprKind::Var(name) => Some(Place::var(name)),
        ExprKind::Field(base, field) => place_of(base).map(|p| p.field(field)),
        ExprKind::Index { base, index } => {
            let idx = const_int(index)
                .map(|n| n.to_string())
                .unwrap_or_else(|| "_".to_string());
            place_of(base).map(|p| p.index(idx))
        }
        ExprKind::Move(inner) => place_of(inner),
        _ => None,
    }
}

fn is_atomic_method(method: &str) -> bool {
    matches!(
        method,
        "load"
            | "store"
            | "swap"
            | "fetch_add"
            | "fetch_sub"
            | "fetch_and"
            | "fetch_or"
            | "fetch_xor"
            | "compare_exchange"
    )
}

fn mode_keyword(name: &str) -> Option<ModeTag> {
    match name {
        "box" => Some(ModeTag::Boxed),
        "iso" => Some(ModeTag::Iso),
        "val" => Some(ModeTag::Val),
        "ref" => Some(ModeTag::Ref),
        "shared" => Some(ModeTag::Shared),
        "atom" => Some(ModeTag::Atom),
        "rawptr" => Some(ModeTag::Raw),
        _ => None,
    }
}

fn is_builtin_type(name: &str) -> bool {
    matches!(
        name,
        "Unit"
            | "Int"
            | "I8"
            | "I16"
            | "I32"
            | "I64"
            | "U8"
            | "U16"
            | "U32"
            | "U64"
            | "USize"
            | "Isize"
            | "F32"
            | "F64"
            | "Bool"
            | "Char"
            | "Str"
            | "Slice"
            | "Buffer"
            | "Option"
            | "Result"
            | "Alloc"
            | "Region"
            | "Heap"
            | "Cap"
            | "Sys"
            | "Error"
            | "AllocError"
    )
}

fn is_known_trait(bounds: &[String]) -> bool {
    bounds
        .iter()
        .all(|b| matches!(b.as_str(), "Copy" | "Eq" | "Ord" | "Arith" | "Alloc"))
}

fn is_known_effect(effect: &str) -> bool {
    matches!(
        effect,
        "Pure"
            | "Io"
            | "Alloc"
            | "Block"
            | "Panic"
            | "Write"
            | "Read"
            | "Atomic"
            | "Spawn"
            | "Irq"
            | "Dma"
            | "Hw"
            | "Asm"
            | "Unsafe"
            | "Ffi"
            | "Local"
    )
}

fn param_map(generics: &[GenericParam]) -> BTreeMap<String, Ty> {
    generics
        .iter()
        .map(|g| (g.name.clone(), Ty::Param(g.name.clone())))
        .collect()
}

fn type_param_map(generics: &[GenericParam], args: &[Ty]) -> BTreeMap<String, Ty> {
    generics
        .iter()
        .zip(args)
        .map(|(g, t)| (g.name.clone(), t.clone()))
        .collect()
}

fn bound_map(generics: &[GenericParam]) -> BTreeMap<String, BTreeSet<String>> {
    generics
        .iter()
        .map(|g| (g.name.clone(), g.bounds.iter().cloned().collect()))
        .collect()
}

fn substitute(ty: &Ty, map: &BTreeMap<String, Ty>) -> Ty {
    match ty {
        Ty::Param(name) => map.get(name).cloned().unwrap_or_else(|| ty.clone()),
        Ty::Slice(t) => Ty::Slice(Box::new(substitute(t, map))),
        Ty::Buffer(t) => Ty::Buffer(Box::new(substitute(t, map))),
        Ty::Option(t) => Ty::Option(Box::new(substitute(t, map))),
        Ty::Result(t, e) => Ty::Result(Box::new(substitute(t, map)), Box::new(substitute(e, map))),
        Ty::Named(n, args) => {
            Ty::Named(n.clone(), args.iter().map(|a| substitute(a, map)).collect())
        }
        Ty::Mode(m, t) => Ty::Mode(*m, Box::new(substitute(t, map))),
        Ty::Atomic(t) => Ty::Atomic(Box::new(substitute(t, map))),
        Ty::Array(t, n) => Ty::Array(Box::new(substitute(t, map)), *n),
        Ty::Lock(t, r) => Ty::Lock(Box::new(substitute(t, map)), *r),
        Ty::Guard(t, r) => Ty::Guard(Box::new(substitute(t, map)), *r),
        _ => ty.clone(),
    }
}

fn first_unresolved(ty: &Ty) -> Option<u32> {
    match ty {
        Ty::Var(v) => Some(*v),
        Ty::Slice(t) | Ty::Buffer(t) | Ty::Option(t) => first_unresolved(t),
        Ty::Result(t, e) => first_unresolved(t).or_else(|| first_unresolved(e)),
        Ty::Named(_, args) => args.iter().find_map(first_unresolved),
        Ty::Mode(_, t) | Ty::Atomic(t) | Ty::Array(t, _) | Ty::Lock(t, _) | Ty::Guard(t, _) => {
            first_unresolved(t)
        }
        _ => None,
    }
}

fn callee_path(expr: &Expr) -> Option<Vec<String>> {
    match &expr.kind {
        ExprKind::Var(name) => Some(vec![name.clone()]),
        ExprKind::Field(recv, name) => {
            let mut p = callee_path(recv)?;
            p.push(name.clone());
            Some(p)
        }
        _ => None,
    }
}

fn is_type_path(expr: &Expr) -> bool {
    match &expr.kind {
        ExprKind::Var(name) => name
            .chars()
            .next()
            .map(|c| c.is_uppercase())
            .unwrap_or(false),
        ExprKind::Field(recv, _) => is_type_path(recv),
        _ => false,
    }
}

fn join_set(set: &BTreeSet<String>) -> String {
    set.iter().cloned().collect::<Vec<_>>().join(", ")
}
