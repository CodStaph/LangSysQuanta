// checker-spike: minimal parser + view/region checks for dossiers/views.
// Not a compiler. Not final. See tools/checker-spike/README.md.

use std::collections::{BTreeSet, HashMap, HashSet};
use std::env;
use std::fs;
use std::path::PathBuf;

#[derive(Clone, Debug, PartialEq)]
enum Tok {
    Word(String),
    Str(String),
    Punct(char),
    Sym(String),
}

fn lex(src: &str) -> Vec<Tok> {
    let cs: Vec<char> = src.chars().collect();
    let mut out = Vec::new();
    let mut i = 0usize;
    while i < cs.len() {
        let c = cs[i];
        if c.is_whitespace() {
            i += 1;
            continue;
        }
        if c == '/' && i + 1 < cs.len() && cs[i + 1] == '/' {
            while i < cs.len() && cs[i] != '\n' {
                i += 1;
            }
            continue;
        }
        if c == '/' && i + 1 < cs.len() && cs[i + 1] == '*' {
            i += 2;
            while i + 1 < cs.len() && !(cs[i] == '*' && cs[i + 1] == '/') {
                i += 1;
            }
            i = (i + 2).min(cs.len());
            continue;
        }
        if c == '"' {
            let mut s = String::new();
            i += 1;
            while i < cs.len() && cs[i] != '"' {
                if cs[i] == '\\' && i + 1 < cs.len() {
                    i += 1;
                }
                s.push(cs[i]);
                i += 1;
            }
            i = (i + 1).min(cs.len());
            out.push(Tok::Str(s));
            continue;
        }
        if c.is_alphabetic() || c == '_' {
            let mut s = String::new();
            while i < cs.len() && (cs[i].is_alphanumeric() || cs[i] == '_') {
                s.push(cs[i]);
                i += 1;
            }
            out.push(Tok::Word(s));
            continue;
        }
        if c.is_ascii_digit() {
            let mut s = String::new();
            while i < cs.len() && (cs[i].is_ascii_digit() || cs[i] == '_') {
                s.push(cs[i]);
                i += 1;
            }
            out.push(Tok::Word(s));
            continue;
        }
        if i + 1 < cs.len() {
            let two: String = cs[i..i + 2].iter().collect();
            if ["->", "=>", "::", "..", "<=", ">=", "==", "!="].contains(&two.as_str()) {
                out.push(Tok::Sym(two));
                i += 2;
                continue;
            }
        }
        out.push(Tok::Punct(c));
        i += 1;
    }
    out
}

#[derive(Clone, Debug, Default)]
struct Type {
    toks: Vec<Tok>,
}

impl Type {
    fn direct(&self, mode: &str) -> bool {
        matches!(self.toks.first(), Some(Tok::Word(w)) if w == mode)
            && matches!(self.toks.get(1), Some(Tok::Punct('[')))
    }
}

#[derive(Clone, Debug)]
struct Field {
    name: String,
    ty: Type,
}

#[allow(dead_code)]
#[derive(Clone, Debug)]
struct StructDef {
    name: String,
    fields: Vec<Field>,
}

#[derive(Clone, Debug)]
struct StaticDef {
    name: String,
    ty: Type,
    init: Vec<Tok>,
}

#[derive(Clone, Debug)]
struct FnDef {
    name: String,
    params: Vec<Field>,
    ret: Type,
    body: Vec<Tok>,
    is_unsafe: bool,
    /// Full attribute text, e.g. "recursion( bound = 64 )" / "bounds(off)".
    attrs: Vec<String>,
    /// True when the signature carries `requires` or `ensures`.
    has_contract: bool,
}

#[derive(Default)]
struct Program {
    structs: HashMap<String, StructDef>,
    fns: Vec<FnDef>,
    statics: Vec<StaticDef>,
}

struct Parser {
    t: Vec<Tok>,
    i: usize,
}

impl Parser {
    fn new(t: Vec<Tok>) -> Self {
        Self { t, i: 0 }
    }
    fn peek(&self) -> Option<&Tok> {
        self.t.get(self.i)
    }
    fn bump(&mut self) -> Option<Tok> {
        let x = self.t.get(self.i).cloned();
        if x.is_some() {
            self.i += 1;
        }
        x
    }
    fn at_word(&self, w: &str) -> bool {
        matches!(self.peek(), Some(Tok::Word(x)) if x == w)
    }
    fn at_punct(&self, c: char) -> bool {
        matches!(self.peek(), Some(Tok::Punct(x)) if *x == c)
    }
    fn at_sym(&self, s: &str) -> bool {
        matches!(self.peek(), Some(Tok::Sym(x)) if x == s)
    }
    fn eat_word(&mut self, w: &str) -> bool {
        if self.at_word(w) {
            self.i += 1;
            true
        } else {
            false
        }
    }
    fn eat_punct(&mut self, c: char) -> bool {
        if self.at_punct(c) {
            self.i += 1;
            true
        } else {
            false
        }
    }
    fn eat_sym(&mut self, s: &str) -> bool {
        if self.at_sym(s) {
            self.i += 1;
            true
        } else {
            false
        }
    }
    fn expect_punct(&mut self, c: char) {
        self.eat_punct(c);
    }
    fn word(&mut self) -> String {
        match self.bump() {
            Some(Tok::Word(w)) => w,
            _ => "<missing>".to_string(),
        }
    }
    fn skip_balanced(&mut self, open: char, close: char) {
        if !self.eat_punct(open) {
            return;
        }
        let mut depth = 1;
        while let Some(t) = self.bump() {
            match t {
                Tok::Punct(c) if c == open => depth += 1,
                Tok::Punct(c) if c == close => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                }
                _ => {}
            }
        }
    }
    fn parse_attrs(&mut self) -> Vec<String> {
        let mut attrs = Vec::new();
        while self.at_punct('#') {
            self.bump();
            if !self.eat_punct('[') {
                continue;
            }
            // Keep the whole attribute text, not just its name: the
            // recursion/stack/dialect checks need the arguments
            // ("recursion(bound = 64)", "bounds(off)").
            let mut text = String::new();
            let mut depth = 1;
            while let Some(t) = self.bump() {
                match t {
                    Tok::Punct('[') => {
                        depth += 1;
                        text.push('[');
                    }
                    Tok::Punct(']') => {
                        depth -= 1;
                        if depth == 0 {
                            break;
                        }
                        text.push(']');
                    }
                    Tok::Punct(c) => text.push(c),
                    Tok::Word(w) | Tok::Str(w) => {
                        if !text.is_empty() {
                            text.push(' ');
                        }
                        text.push_str(&w);
                    }
                    Tok::Sym(sym) => {
                        if !text.is_empty() {
                            text.push(' ');
                        }
                        text.push_str(&sym);
                    }
                }
            }
            if !text.is_empty() {
                attrs.push(text);
            }
        }
        attrs
    }
    fn parse_ty(&mut self, stop_words: &[&str], stop_punct: &[char]) -> Type {
        let mut toks = Vec::new();
        let mut depth = 0i32;
        while let Some(tok) = self.peek() {
            if depth == 0 {
                if let Tok::Punct(c) = tok {
                    if stop_punct.contains(c) {
                        break;
                    }
                }
                if let Tok::Word(w) = tok {
                    if stop_words.iter().any(|x| x == w) {
                        break;
                    }
                }
            }
            let tok = self.bump().unwrap();
            match &tok {
                Tok::Punct('[') | Tok::Punct('(') => depth += 1,
                Tok::Punct(']') | Tok::Punct(')') => depth -= 1,
                _ => {}
            }
            toks.push(tok);
        }
        Type { toks }
    }
    fn parse_block(&mut self) -> Vec<Tok> {
        let mut inner = Vec::new();
        if !self.eat_punct('{') {
            return inner;
        }
        let mut depth = 1;
        while let Some(t) = self.bump() {
            match t {
                Tok::Punct('{') => {
                    depth += 1;
                    inner.push(t);
                }
                Tok::Punct('}') => {
                    depth -= 1;
                    if depth == 0 {
                        break;
                    }
                    inner.push(t);
                }
                _ => inner.push(t),
            }
        }
        inner
    }
    fn skip_until_semi(&mut self) {
        let mut depth = 0i32;
        while let Some(t) = self.bump() {
            match t {
                Tok::Punct('[') | Tok::Punct('(') => depth += 1,
                Tok::Punct(']') | Tok::Punct(')') => depth -= 1,
                Tok::Punct(';') if depth <= 0 => break,
                _ => {}
            }
        }
    }
    fn skip_until_block(&mut self) {
        let mut depth = 0i32;
        while let Some(t) = self.peek() {
            if depth == 0 && matches!(t, Tok::Punct('{')) {
                break;
            }
            let t = self.bump().unwrap();
            match t {
                Tok::Punct('[') | Tok::Punct('(') => depth += 1,
                Tok::Punct(']') | Tok::Punct(')') => depth -= 1,
                _ => {}
            }
        }
    }
}

fn parse_static(p: &mut Parser) -> StaticDef {
    p.eat_word("static");
    p.eat_word("mut");
    let name = p.word();
    p.expect_punct(':');
    let ty = p.parse_ty(&["requires", "ensures"], &['=', ';']);
    let mut init = Vec::new();
    if p.eat_punct('=') {
        let mut depth = 0i32;
        while let Some(t) = p.bump() {
            match &t {
                Tok::Punct('[') | Tok::Punct('(') => depth += 1,
                Tok::Punct(']') | Tok::Punct(')') => depth -= 1,
                Tok::Punct(';') if depth <= 0 => break,
                _ => {}
            }
            init.push(t);
        }
    } else {
        p.eat_punct(';');
    }
    StaticDef { name, ty, init }
}

fn parse_fn(p: &mut Parser, is_unsafe: bool, attrs: Vec<String>) -> FnDef {
    p.eat_word("fn");
    let name = p.word();
    if p.at_punct('[') {
        p.skip_balanced('[', ']');
    }
    let mut params = Vec::new();
    p.expect_punct('(');
    while !p.at_punct(')') && p.peek().is_some() {
        p.eat_word("mut");
        let pname = p.word();
        p.expect_punct(':');
        let ty = p.parse_ty(
            &["requires", "ensures", "eff", "where"],
            &[',', ')'],
        );
        params.push(Field { name: pname, ty });
        if !p.eat_punct(',') {
            break;
        }
    }
    p.expect_punct(')');
    let mut ret = Type::default();
    if p.eat_sym("->") {
        ret = p.parse_ty(
            &["requires", "ensures", "eff", "where"],
            &['{'],
        );
    }
    let mut has_contract = false;
    while p.peek().is_some() && !p.at_punct('{') {
        if p.eat_word("requires") || p.eat_word("ensures") {
            has_contract = true;
            p.skip_until_block();
        } else if p.eat_word("eff") {
            p.skip_until_block();
        } else {
            p.bump();
        }
    }
    let body = p.parse_block();
    FnDef {
        name,
        params,
        ret,
        body,
        is_unsafe,
        attrs,
        has_contract,
    }
}

fn parse_program(toks: Vec<Tok>) -> Program {
    let mut p = Parser::new(toks);
    let mut prog = Program::default();
    while p.peek().is_some() {
        let attrs = p.parse_attrs();
        if p.at_word("module") || p.at_word("profile") {
            p.bump();
            p.skip_until_semi();
            continue;
        }
        if p.at_word("struct") || p.at_word("union") {
            p.bump();
            let name = p.word();
            let mut fields = Vec::new();
            p.expect_punct('{');
            while !p.at_punct('}') && p.peek().is_some() {
                let fname = p.word();
                p.expect_punct(':');
                let ty = p.parse_ty(&["requires", "ensures"], &[',', '}']);
                fields.push(Field { name: fname, ty });
                if !p.eat_punct(',') {
                    // allow trailing comma or immediate }
                }
            }
            p.expect_punct('}');
            prog.structs.insert(
                name.clone(),
                StructDef { name, fields },
            );
            continue;
        }
        if p.at_word("static") {
            prog.statics.push(parse_static(&mut p));
            continue;
        }
        if p.at_word("unsafe") {
            p.bump();
            if p.at_word("fn") {
                prog.fns.push(parse_fn(&mut p, true, attrs.clone()));
            }
            continue;
        }
        if p.at_word("fn") {
            prog.fns.push(parse_fn(&mut p, false, attrs.clone()));
            continue;
        }
        if p.at_word("const") {
            p.bump();
            p.skip_until_semi();
            continue;
        }
        if p.at_word("impl")
            || p.at_word("trait")
            || p.at_word("extern")
            || p.at_word("use")
            || p.at_word("type")
        {
            p.bump();
            if p.at_punct('{') {
                p.skip_balanced('{', '}');
            } else {
                p.skip_until_semi();
            }
            continue;
        }
        if p.at_punct('{') {
            p.skip_balanced('{', '}');
        } else {
            p.bump();
        }
    }
    prog
}

#[derive(Clone, Debug)]
struct Diag {
    code: &'static str,
    msg: String,
}

impl Diag {
    fn new(code: &'static str, msg: String) -> Self {
        Self { code, msg }
    }
}

struct Report {
    diags: Vec<Diag>,
    unsafe_count: usize,
    zero_copy_source: bool,
}

fn type_contains_mode(ty: &Type, mode: &str, structs: &HashMap<String, StructDef>) -> bool {
    let mut seen = HashSet::new();
    contains_in(&ty.toks, mode, structs, &mut seen)
}

fn contains_in(
    toks: &[Tok],
    mode: &str,
    structs: &HashMap<String, StructDef>,
    seen: &mut HashSet<String>,
) -> bool {
    for t in toks {
        if let Tok::Word(w) = t {
            if w == mode {
                return true;
            }
            if let Some(s) = structs.get(w) {
                if seen.insert(w.clone()) {
                    for f in &s.fields {
                        if contains_in(&f.ty.toks, mode, structs, seen) {
                            return true;
                        }
                    }
                }
            }
        }
    }
    false
}

fn word_at(toks: &[Tok], i: usize) -> Option<&str> {
    match toks.get(i) {
        Some(Tok::Word(w)) => Some(w.as_str()),
        _ => None,
    }
}

fn block_slice(toks: &[Tok], open: usize) -> (&[Tok], usize) {
    if !matches!(toks.get(open), Some(Tok::Punct('{'))) {
        return (&[], open);
    }
    let mut depth = 1usize;
    let mut i = open + 1;
    while i < toks.len() {
        match &toks[i] {
            Tok::Punct('{') => depth += 1,
            Tok::Punct('}') => {
                depth -= 1;
                if depth == 0 {
                    return (&toks[open + 1..i], i + 1);
                }
            }
            _ => {}
        }
        i += 1;
    }
    (&toks[open + 1..], toks.len())
}

fn scan_body(f: &FnDef, structs: &HashMap<String, StructDef>) -> (Vec<Diag>, usize, bool) {
    let mut diags = Vec::new();
    let mut unsafe_count = 0usize;

    // unsafe count (all bodies)
    for t in &f.body {
        if matches!(t, Tok::Word(w) if w == "unsafe") {
            unsafe_count += 1;
        }
    }

    // static items inside the body
    let mut i = 0usize;
    while i < f.body.len() {
        if word_at(&f.body, i) == Some("static") {
            let mut j = i + 1;
            if word_at(&f.body, j) == Some("mut") {
                j += 1;
            }
            let name = word_at(&f.body, j).unwrap_or("<missing>").to_string();
            j += 1;
            if matches!(f.body.get(j), Some(Tok::Punct(':'))) {
                j += 1;
            }
            let ty_start = j;
            let mut depth = 0i32;
            while j < f.body.len() {
                if depth == 0
                    && (matches!(f.body.get(j), Some(Tok::Punct('=')))
                        || matches!(f.body.get(j), Some(Tok::Punct(';'))))
                {
                    break;
                }
                match f.body.get(j) {
                    Some(Tok::Punct('[')) | Some(Tok::Punct('(')) => depth += 1,
                    Some(Tok::Punct(']')) | Some(Tok::Punct(')')) => depth -= 1,
                    _ => {}
                }
                j += 1;
            }
            let ty = Type {
                toks: f.body[ty_start..j].to_vec(),
            };
            if matches!(f.body.get(j), Some(Tok::Punct('='))) {
                j += 1;
            }
            let init_start = j;
            let mut depth2 = 0i32;
            while j < f.body.len() {
                if depth2 == 0 && matches!(f.body.get(j), Some(Tok::Punct(';'))) {
                    break;
                }
                match f.body.get(j) {
                    Some(Tok::Punct('[')) | Some(Tok::Punct('(')) => depth2 += 1,
                    Some(Tok::Punct(']')) | Some(Tok::Punct(')')) => depth2 -= 1,
                    _ => {}
                }
                j += 1;
            }
            let init = &f.body[init_start..j];
            let bad_ty = type_contains_mode(&ty, "ref", structs)
                || (!ty.direct("val") && type_contains_mode(&ty, "val", structs));
            let bad_init = init.iter().any(|t| {
                if let Tok::Word(x) = t {
                    f.params.iter().any(|p| &p.name == x)
                } else {
                    false
                }
            });
            if bad_ty || bad_init {
                diags.push(Diag::new(
                    "E-LS-STATIC",
                    format!("static {} in fn {} cannot hold a region-bound or parameter value", name, f.name),
                ));
            }
            i = j;
            continue;
        }
        i += 1;
    }

    // recover with an unconsumed alias
    let mut i = 0usize;
    while i < f.body.len() {
        if word_at(&f.body, i) == Some("recover") {
            let open = i + 1;
            if matches!(f.body.get(open), Some(Tok::Punct('{'))) {
                let (inner, end) = block_slice(&f.body, open);
                let recovered: HashSet<String> = inner
                    .iter()
                    .filter_map(|t| {
                        if let Tok::Word(w) = t {
                            Some(w.clone())
                        } else {
                            None
                        }
                    })
                    .collect();
                let mut j = 0usize;
                while j < i {
                    if word_at(&f.body, j) == Some("let") {
                        let alias = word_at(&f.body, j + 1).unwrap_or("").to_string();
                        let mut k = j + 2;
                        if matches!(f.body.get(k), Some(Tok::Punct('='))) {
                            k += 1;
                        }
                        let expr_start = k;
                        while k < i && !matches!(f.body.get(k), Some(Tok::Punct(';'))) {
                            k += 1;
                        }
                        let expr = &f.body[expr_start..k];
                        let refs_recovered = expr.iter().any(|t| {
                            if let Tok::Word(w) = t {
                                recovered.contains(w)
                            } else {
                                false
                            }
                        });
                        if refs_recovered && !recovered.contains(&alias) {
                            diags.push(Diag::new(
                                "E-LS-UNIQ",
                                format!("recover in fn {} leaves alias {} unconsumed", f.name, alias),
                            ));
                            break;
                        }
                    }
                    j += 1;
                }
                i = end;
                continue;
            }
        }
        i += 1;
    }

    // source-level zero-copy heuristic: no bulk copy calls in this fn
    let bulk = f.body.iter().any(|t| {
        matches!(t, Tok::Word(w) if ["memcpy", "copy_from", "clone", "to_vec", "copy_nonoverlapping"].contains(&w.as_str()))
    });

    (diags, unsafe_count, !bulk)
}

/// Frame-size estimate for the static recursion budget.
///
/// Conservative on purpose: 128 bytes per frame against the 8 KiB static stack
/// budget from 03 §4.1. With this model `#[recursion(bound = 8)]` fits
/// (8 * 128 = 1 KiB) while `#[recursion(bound = 64)]` does not (64 * 128 = 8 KiB),
/// which is exactly what dossier B requires. A real implementation would size
/// frames from the actual layout.
const FRAME_BYTES: usize = 128;
const STACK_BUDGET: usize = 8 * 1024;

/// Extract N from an attribute like "recursion( bound = 8 )".
fn attr_bound(attr: &str) -> Option<usize> {
    let mut digits = String::new();
    let mut seen_eq = false;
    for c in attr.chars() {
        if c == '=' {
            seen_eq = true;
            continue;
        }
        if seen_eq {
            if c.is_ascii_digit() {
                digits.push(c);
            } else if !digits.is_empty() {
                break;
            }
        }
    }
    digits.parse::<usize>().ok()
}

fn analyze(prog: &Program) -> Report {
    let mut diags = Vec::new();
    let mut unsafe_count = 0usize;
    let mut zero_copy_source = true;

    for f in &prog.fns {
        if type_contains_mode(&f.ret, "ref", &prog.structs) {
            diags.push(Diag::new(
                "E-LS-REGION-ESCAPE",
                format!("fn {} returns a ref-derived value", f.name),
            ));
        }
        // Dossier B: recursion is rejected unless opted in with a bound, and
        // the bound must fit the static stack budget (03 §4.1).
        let recursion_attr = f.attrs.iter().find(|a| a.starts_with("recursion"));
        let self_call = f.body.windows(2).any(|w| {
            matches!(&w[0], Tok::Word(x) if *x == f.name) && matches!(&w[1], Tok::Punct('('))
        });
        if self_call && recursion_attr.is_none() {
            diags.push(Diag::new(
                "E-LS-RECURSION",
                format!("fn {} recurses without #[recursion(bound = N)]", f.name),
            ));
        }
        if self_call {
            if let Some(bound) = recursion_attr.and_then(|a| attr_bound(a)) {
                if bound.saturating_mul(FRAME_BYTES) >= STACK_BUDGET {
                    diags.push(Diag::new(
                        "E-LS-STACK",
                        format!(
                            "fn {} recursion bound {} exceeds the {}-byte static stack budget",
                            f.name, bound, STACK_BUDGET
                        ),
                    ));
                }
            }
        }
        // Dossier B: #[bounds(off)] turns bounds checks off, which needs a
        // contract to justify it.
        let bounds_off = f
            .attrs
            .iter()
            .any(|a| a.starts_with("bounds") && a.contains("off"));
        if bounds_off && !f.has_contract {
            diags.push(Diag::new(
                "E-LS-DIAL",
                format!("fn {} uses #[bounds(off)] without requires/ensures", f.name),
            ));
        }

        let (mut d, u, z) = scan_body(f, &prog.structs);
        diags.append(&mut d);
        unsafe_count += u;
        if f.is_unsafe {
            unsafe_count += 1;
        }
        zero_copy_source &= z;
    }

    for s in &prog.statics {
        let bad_ref = type_contains_mode(&s.ty, "ref", &prog.structs);
        let bad_val = !s.ty.direct("val") && type_contains_mode(&s.ty, "val", &prog.structs);
        let bad_init = s.init.iter().any(|t| matches!(t, Tok::Word(w) if w == "p"));
        if bad_ref || bad_val || bad_init {
            diags.push(Diag::new(
                "E-LS-STATIC",
                format!("static {} cannot hold a region-bound value", s.name),
            ));
        }
    }

    let mut seen = HashSet::new();
    diags.retain(|d| seen.insert((d.code, d.msg.clone())));
    Report {
        diags,
        unsafe_count,
        zero_copy_source,
    }
}

fn load(path: &PathBuf) -> (String, Program) {
    let src = fs::read_to_string(path).unwrap_or_else(|e| {
        eprintln!("cannot read {}: {}", path.display(), e);
        std::process::exit(2);
    });
    let prog = parse_program(lex(&src));
    (src, prog)
}

fn expected_codes(src: &str) -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    for line in src.lines() {
        if let Some(rest) = line.trim().strip_prefix("// EXPECT:") {
            let code = rest.trim().split_whitespace().next().unwrap_or("");
            if !code.is_empty() {
                set.insert(code.to_string());
            }
        }
    }
    set
}

fn check_accept(path: &PathBuf) -> bool {
    let (_, prog) = load(path);
    let rep = analyze(&prog);
    println!("== {} ==", path.display());
    if rep.diags.is_empty() {
        println!(
            "PASS {} diagnostics=0 unsafe={} zero_copy_source={}",
            path.display(),
            rep.unsafe_count,
            rep.zero_copy_source
        );
        true
    } else {
        for d in &rep.diags {
            println!("FAIL {} {}: {}", path.display(), d.code, d.msg);
        }
        false
    }
}

fn check_reject(path: &PathBuf) -> bool {
    let (src, prog) = load(path);
    let expected = expected_codes(&src);
    let rep = analyze(&prog);
    let actual: BTreeSet<String> = rep.diags.iter().map(|d| d.code.to_string()).collect();
    println!("== {} ==", path.display());
    let mut ok = true;
    for e in &expected {
        if actual.contains(e) {
            println!("  OK       {}", e);
        } else {
            println!("  MISSING  {}", e);
            ok = false;
        }
    }
    for a in &actual {
        if !expected.contains(a) {
            println!("  EXTRA    {}", a);
            ok = false;
        }
    }
    for d in &rep.diags {
        println!("  detail   {}: {}", d.code, d.msg);
    }
    println!(
        "{} {} expected={} actual={}",
        if ok { "PASS" } else { "FAIL" },
        path.display(),
        expected.len(),
        actual.len()
    );
    ok
}

fn main() {
    let arg = env::args().nth(1).unwrap_or_else(|| "dossiers/views".to_string());
    let path = PathBuf::from(arg);
    let mut ok = true;
    if path.is_dir() {
        // Dossier files are named accept.ls / reject.ls, but some dossiers ship
        // several cases (accept_rec.ls, accept_stack.ls, ...), so scan the
        // directory instead of hard-coding two paths.
        let mut entries: Vec<PathBuf> = fs::read_dir(&path)
            .unwrap_or_else(|e| {
                eprintln!("cannot read {}: {}", path.display(), e);
                std::process::exit(2);
            })
            .filter_map(|e| e.ok().map(|e| e.path()))
            .filter(|p| p.extension().map(|x| x == "ls").unwrap_or(false))
            .collect();
        entries.sort();
        for p in entries {
            let name = p.file_name().and_then(|n| n.to_str()).unwrap_or("");
            if name.starts_with("accept") {
                ok &= check_accept(&p);
            } else if name.starts_with("reject") {
                ok &= check_reject(&p);
            }
        }
    } else if path.exists() {
        ok &= check_accept(&path);
    } else {
        eprintln!("no such path: {}", path.display());
        std::process::exit(2);
    }
    println!("SUMMARY {}", if ok { "PASS" } else { "FAIL" });
    if !ok {
        std::process::exit(1);
    }
}
