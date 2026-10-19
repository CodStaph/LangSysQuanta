// R8 positive (W1): `iso` is the only mode that may move ownership across domains.
//
// R8-transfer:  m = iso ⇒ live(Λ,v) = ∅ ∧ Holders(Σ,b) = ∅    (b ∈ A)
// R8-spawn:     Σ' = Σ_v[H(source(v)) := ∅, Λ -= A]
//
// `move q` clears the source, so the spawning domain no longer holds the value.
// Rule: semantics.md §2.3.9.
struct Queue { head: USize, tail: USize }

fn consume(q: iso[Queue]) eff(Write) {
    let n = q.head;
}

fn r8_iso_spawn(sys: Cap[Sys]) eff(Spawn) {
    let q: iso[Queue] = iso Queue { head: 0, tail: 0 };
    let h = spawn consume(move q);   // OK: unique ownership transferred
    join(h);
}
