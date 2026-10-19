// EXPECT: E-LS-IRQ
// R6 negative — PENDING CHECKER (surface is frozen in v2.2; do not count toward
// the L1 gate until ls-sem tracks Guard liveness).
//
// Surface (00 §4.3): `lock` returns a Guard, i.e. `let g = m.lock();`.
// There is no `lock ... { }` keyword form; see spec/modes.md §2.2.
//
// R6-atom:  atomicOp(E) ∨ (lockCtx(E) ∧ rankOk(E))
// rankOk:   ∀ live Guards (g1, g2): acquire(g1) < acquire(g2) ⇒ rank(g1) ≤ rank(g2)
//
// `a` has rank 2 and `b` has rank 1; acquiring b after a violates monotonicity.
// Guards are !Copy, non-movable and released only at scope exit, so the live set
// is a stack and rankOk is a local check — no whole-program fixpoint.
struct State { value: U64 }

fn r6_lock_rank(a: Lock[State, 2], b: Lock[State, 1]) eff(Atomic) {
    let ga = a.lock();
    let gb = b.lock();              // E-LS-IRQ: rank 1 < 2
    gb.value += 1;
}
