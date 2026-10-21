//! ls-sem: L-Sys semantic checker skeleton.
//!
//! First slice: Σ = (Γ, Λ, M, H), place paths, aliases*, Q2 cap context,
//! Q6 C ABI scalar mapping, and the Q7 target matrix.

pub mod abi;
pub mod arena;
pub mod cap_context;
pub mod runtime;
pub mod state;
pub mod surface;
pub mod target;

pub use abi::{check_signature, layout, map_scalar, CType, LSysType};
pub use arena::{AllocError, Allocation, Arena, ArenaReport};
pub use cap_context::{CapDiagnostic, Capability, Knobs, Module, ModuleTree};
pub use runtime::{RuntimeArena, RuntimeBuffer, RuntimeError, RuntimeSlice};
pub use state::{
    demo_bad, selftest, AliasOccurrence, Bid, Binding, Borrow, Buffer, BufferFull, DemoResult,
    Mode, PathSeg, Place, RecoverError, Region, RegionError, RegionTree, Sigma,
};
pub use surface::{
    check_source, line_col, parse_source, CheckOptions, CheckReport, Diagnostic, Span,
};
pub use target::{by_triple, Atomics, DataModel, Endian, FloatAbi, Target};
