// Combined positive (TM-0, D-TM-3): iso ownership transfer + spawn/join
// domain crossing + R6 method-form atomic op, all legal together.
//
// Rules stacked (>=3, spec/test-matrix.md §4):
//   iso Task { ... } + move t        R8 iso transfer       (semantics §2.3.9)
//   spawn consumer / join(h)         domain spawn/join     (00 §4.3)
//   c.fetch_add(1, Order.SeqCst)     R6 atomic op on shared[Atomic[U64]]
// The spawned closure owns the Task uniquely, so R8-transfer premises hold.
struct Task { budget: U64 }

fn consumer(t: iso[Task]) eff(Write) {
    let used = t.budget;
}

fn combined_spawn_iso_atomic(c: shared[Atomic[U64]]) -> Unit eff(Spawn, Atomic, Write) {
    let t: iso[Task] = iso Task { budget: 4 };
    let h = spawn consumer(move t);   // OK: unique ownership crosses domain
    c.fetch_add(1, Order.SeqCst);     // OK: atomic op with explicit order
    join(h);
}
