//! ls-sem: L-Sys semantic checker skeleton.
//!
//! First slice: Σ = (Γ, Λ, M, H), place paths, aliases*, and the
//! `bad()` replay from `spec/t4-proof.md`. Parsing/conformance lands next.

pub mod state;

pub use state::{
    demo_bad, selftest, AliasOccurrence, Bid, Binding, Borrow, DemoResult, Mode, PathSeg, Place,
    RecoverError, Region, Sigma,
};
