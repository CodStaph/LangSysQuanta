// EXPECT: E-LS-RACE
// R8 negative (W1): `ref` must not cross a domain boundary.
//
// m = mut ∉ {iso, atom, frozen}  ⇒  R8-transfer fails.
// Diagnostic precedence (spec/feature-coverage.md §4): at a `spawn` entry R8
// is checked before R4, so this reports E-LS-RACE, not E-LS-REGION-ESCAPE.
// Rule: semantics.md §2.3.9.
struct Config { depth: U32 }

fn use_cfg_ref(c: ref[Config]) -> U32 { c.depth }

fn r8_ref_across_spawn(c: ref[Config]) eff(Spawn) {
    let h = spawn use_cfg_ref(c);        // E-LS-RACE
    join(h);
}
