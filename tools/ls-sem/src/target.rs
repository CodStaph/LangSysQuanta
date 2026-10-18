//! Q7 target matrix (v0): x86_64 Linux, Cortex-M4F, RV32IMAC.
//!
//! The objective here is not codegen; it is the executable target capability
//! table that manifest/ABI checks consume.

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Endian {
    Little,
    Big,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum FloatAbi {
    None,
    Soft,
    Hard,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Atomics {
    None,
    U32,
    U64,
}

impl Atomics {
    pub fn bits(self) -> u8 {
        match self {
            Atomics::None => 0,
            Atomics::U32 => 32,
            Atomics::U64 => 64,
        }
    }
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct DataModel {
    pub pointer_bits: u8,
    pub long_bits: u8,
    pub size_t_bits: u8,
    pub char_signed: bool,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct Target {
    pub triple: &'static str,
    pub arch: &'static str,
    pub model: DataModel,
    pub endian: Endian,
    pub float: FloatAbi,
    pub atomics: Atomics,
}

pub const X86_64_LINUX: Target = Target {
    triple: "x86_64-unknown-linux-gnu",
    arch: "x86_64",
    model: DataModel {
        pointer_bits: 64,
        long_bits: 64,
        size_t_bits: 64,
        char_signed: true,
    },
    endian: Endian::Little,
    float: FloatAbi::Hard,
    atomics: Atomics::U64,
};

pub const THUMBV7EM: Target = Target {
    triple: "thumbv7em-none-eabihf",
    arch: "thumbv7em",
    model: DataModel {
        pointer_bits: 32,
        long_bits: 32,
        size_t_bits: 32,
        char_signed: false,
    },
    endian: Endian::Little,
    float: FloatAbi::Hard,
    atomics: Atomics::U32,
};

pub const RISCV32IMAC: Target = Target {
    triple: "riscv32imac-unknown-none-elf",
    arch: "riscv32imac",
    model: DataModel {
        pointer_bits: 32,
        long_bits: 32,
        size_t_bits: 32,
        char_signed: false,
    },
    endian: Endian::Little,
    float: FloatAbi::Soft,
    atomics: Atomics::U32,
};

pub fn all() -> &'static [Target] {
    &[X86_64_LINUX, THUMBV7EM, RISCV32IMAC]
}

pub fn by_triple(triple: &str) -> Option<Target> {
    all().iter().copied().find(|t| t.triple == triple)
}

/// Validate `[target]` overrides against the matrix. `None` means "use target
/// default". The rule is conservative: a request may lower capability, never
/// raise it.
pub fn validate_config(
    target: Target,
    float: Option<FloatAbi>,
    atomics: Option<Atomics>,
    endian: Option<Endian>,
) -> Result<(), String> {
    if let Some(endian) = endian {
        if endian != target.endian {
            return Err(format!(
                "E-LS-PROFILE: {} only supports {:?} endianness",
                target.triple, target.endian
            ));
        }
    }
    if let Some(float) = float {
        let ok = match float {
            FloatAbi::None | FloatAbi::Soft => true,
            FloatAbi::Hard => target.float == FloatAbi::Hard,
        };
        if !ok {
            return Err(format!(
                "E-LS-PROFILE: {} cannot use hard float",
                target.triple
            ));
        }
    }
    if let Some(atomics) = atomics {
        if atomics.bits() > target.atomics.bits() {
            return Err(format!(
                "E-LS-PROFILE: {} does not support {:?} atomics",
                target.triple, atomics
            ));
        }
    }
    Ok(())
}

pub fn selftest() -> Result<(), String> {
    if all().len() != 3 {
        return Err("expected exactly three v0 targets".into());
    }
    if by_triple("aarch64-unknown-none").is_some() {
        return Err("unknown target accepted".into());
    }
    validate_config(
        THUMBV7EM,
        Some(FloatAbi::Hard),
        Some(Atomics::U32),
        Some(Endian::Little),
    )?;
    if validate_config(THUMBV7EM, None, Some(Atomics::U64), None).is_ok() {
        return Err("thumbv7em accepted 64-bit atomics".into());
    }
    if validate_config(RISCV32IMAC, Some(FloatAbi::Hard), None, None).is_ok() {
        return Err("riscv32imac accepted hard float".into());
    }
    Ok(())
}
