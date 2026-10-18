//! ls-sem: L-Sys semantic checker skeleton.
//!
//! First slice: Σ = (Γ, Λ, M, H), place paths, aliases*, Q2 cap context,
//! Q6 C ABI scalar mapping, and the Q7 target matrix.

pub mod abi;
pub mod cap_context;
pub mod state;
pub mod target;

pub use abi::{check_signature, layout, map_scalar, CType, LSysType};
pub use cap_context::{CapDiagnostic, Capability, Knobs, Module, ModuleTree};
pub use state::{
    demo_bad, selftest, AliasOccurrence, Bid, Binding, Borrow, DemoResult, Mode, PathSeg, Place,
    RecoverError, Region, Sigma,
};
pub use target::{by_triple, Atomics, DataModel, Endian, FloatAbi, Target};
