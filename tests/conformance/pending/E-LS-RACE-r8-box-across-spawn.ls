// EXPECT: E-LS-RACE
// R8 negative (W1): `box` must not cross a domain boundary.
//
// R8-transfer accepts m ∈ {iso, atom, frozen}.  `box` is core mode `uniq`,
// but it is region-local: the only way across is an explicit
// `transfer b` (box → iso), which also requires b @ heap and T: 'heap.
// Rule: semantics.md §2.3.9; 00 §4.3.
struct Config { depth: U32 }

fn use_cfg_box(c: box[Config]) -> U32 { c.depth }

fn r8_box_across_spawn(c: box[Config]) eff(Spawn) {
    let h = spawn use_cfg_box(move c);   // E-LS-RACE
    join(h);
}
