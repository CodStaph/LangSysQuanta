// Boundary positive (TM-0, spec/test-matrix.md §3.2): two locks acquired in
// rank order — one step from reject/E-LS-IRQ-r6-lock-rank.ls (which acquires
// the low-rank lock after the high-rank one).
// rankOk: ∀ live Guards g1, g2: acquire(g1) < acquire(g2) ⇒ rank(g1) ≥ rank(g2)
// Acquiring rank 1 first and rank 2 second keeps the live-guard stack
// monotonic, so the spawn-free lock context is accepted.
// Rule: semantics.md §2.3.7 (R6-atom / rankOk).
struct State { value: U64 }

fn accept_irq_rank_order(a: Lock[State, 1], b: Lock[State, 2]) eff(Atomic) {
    let ga = a.lock();             // rank 1 acquired first
    let gb = b.lock();             // rank 2 second: monotonic live stack
    gb.value += 1;
}
