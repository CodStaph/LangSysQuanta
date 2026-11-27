// EXPECT-RUSTC: E0277
// Rust counterpart of E-LS-EFFECT-stale-trusted-lock:
// a claim of audited ability with no proof behind it. The nearest Rust
// form is handing a value of a plain type where a trait-bound proof is
// required.
trait Audited {
    fn ok(&self) -> bool;
}

fn consume(a: &dyn Audited) -> bool {
    a.ok()
}

fn stale_wrapper(x: &u32) -> bool {
    consume(x)
}
