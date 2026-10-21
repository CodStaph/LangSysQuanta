// Minimal unsat-core sample (L1): returning a region-local Buffer.
//
// Reproduce:
//   cargo run --quiet --manifest-path tools/ls-sem/Cargo.toml -- \
//     check tools/ls-sem/tests/fixtures/unsat_core_escape.ls
//
// Expected: E-LS-REGION-ESCAPE with
//   core (1 minimal): [return: `fn@make#…` ⊑ `R#…`]
//   witness: `R#…` ⊑ `fn@make#…` (region nesting)
// and a fix-it that does NOT suggest `unsafe`.
fn make() -> Buffer[Int] eff(Alloc) {
    region R {
        let b: Buffer[Int] = Buffer.new[Int](2, R);
        return b;
    }
}
