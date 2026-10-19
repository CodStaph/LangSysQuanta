// R8 positive (W1): `val` may cross a domain only when thread ⊑ Rgn(v).
//
// R8-transfer:  m = frozen ⇒ C' = C ∪ { thread ⊑ Rgn(v) }
//
// A `static` value has Rgn(v) = static, and thread ⊑ heap ⊑ static,
// so the constraint is satisfiable and the spawn is accepted.
// Rule: semantics.md §2.3.9; region lattice in §2.4.
struct Config { depth: U32 }

static CFG: val[Config] = Config { depth: 4 };

fn use_cfg(c: val[Config]) -> U32 { c.depth }

fn r8_val_static() eff(Spawn) {
    let h = spawn use_cfg(CFG);      // OK: thread ⊑ static
    join(h);
}
