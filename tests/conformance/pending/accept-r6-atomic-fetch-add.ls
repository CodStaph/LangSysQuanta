// R6 positive (W1): atomic access on shared[Atomic[U64]] with an explicit order.
//
// R6-atom:  atomicOp(E) ∨ (lockCtx(E) ∧ rankOk(E))
// S16:      op ∈ {load, store, rmw}, ord legal ⇒ may step
// gate:     `shared[Atomic[T]]` requires eff(Atomic) (00 §5.7)
//
// Surface (v2.2, resolved): the method form is the surface; `elaboration.md`
// E21 lowers `p.op(a)` to the core redex `atomic(ord, op, p, a)`.  The static
// premise is `atomicOp(E)` (not "inside atomic(...)"), see semantics.md §2.3.7.
// `op`/`ord` legality is the closed table in spec/effects.md §2.1.
fn r6_atomic_fetch_add(c: shared[Atomic[U64]]) eff(Atomic) {
    c.fetch_add(1, Order.SeqCst);
}
