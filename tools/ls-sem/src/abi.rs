//! Q6 C ABI v1 scalar mapping.
//!
//! v1 is deliberately small: target-dependent `char`/`long`, explicit
//! `#[repr(C)]` aggregates, and **no bitfields across FFI**.

use crate::target::Target;
use std::fmt;

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum CType {
    Void,
    Bool,
    Char,
    SChar,
    UChar,
    Short,
    UShort,
    Int,
    UInt,
    Long,
    ULong,
    LongLong,
    ULongLong,
    SizeT,
    PtrDiffT,
    Float,
    Double,
    Pointer,
    /// Long double is not part of C ABI v1.
    LongDouble,
    /// C variadic parameter is not part of C ABI v1.
    Varargs,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum LSysType {
    Unit,
    Bool,
    I8,
    U8,
    I16,
    U16,
    I32,
    U32,
    I64,
    U64,
    Usize,
    Isize,
    F32,
    F64,
    RawptrU8,
}

impl CType {
    pub fn from_name(name: &str) -> Option<CType> {
        let n = name.trim();
        Some(match n {
            "void" => CType::Void,
            "bool" | "_Bool" => CType::Bool,
            "char" => CType::Char,
            "signed char" | "schar" | "i8" => CType::SChar,
            "unsigned char" | "uchar" | "u8" => CType::UChar,
            "short" => CType::Short,
            "unsigned short" | "ushort" => CType::UShort,
            "int" | "i32" => CType::Int,
            "unsigned int" | "uint" | "u32" => CType::UInt,
            "long" => CType::Long,
            "unsigned long" | "ulong" => CType::ULong,
            "long long" | "llong" => CType::LongLong,
            "unsigned long long" | "ullong" => CType::ULongLong,
            "size_t" | "usize" => CType::SizeT,
            "ptrdiff_t" | "isize" => CType::PtrDiffT,
            "float" | "f32" => CType::Float,
            "double" | "f64" => CType::Double,
            "void*" | "pointer" | "rawptr" => CType::Pointer,
            "long double" => CType::LongDouble,
            "varargs" => CType::Varargs,
            _ => return None,
        })
    }
}

impl fmt::Display for CType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            CType::Void => "void",
            CType::Bool => "bool",
            CType::Char => "char",
            CType::SChar => "signed char",
            CType::UChar => "unsigned char",
            CType::Short => "short",
            CType::UShort => "unsigned short",
            CType::Int => "int",
            CType::UInt => "unsigned int",
            CType::Long => "long",
            CType::ULong => "unsigned long",
            CType::LongLong => "long long",
            CType::ULongLong => "unsigned long long",
            CType::SizeT => "size_t",
            CType::PtrDiffT => "ptrdiff_t",
            CType::Float => "float",
            CType::Double => "double",
            CType::Pointer => "void*",
            CType::LongDouble => "long double",
            CType::Varargs => "varargs",
        };
        f.write_str(s)
    }
}

impl fmt::Display for LSysType {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        let s = match self {
            LSysType::Unit => "Unit",
            LSysType::Bool => "Bool",
            LSysType::I8 => "I8",
            LSysType::U8 => "U8",
            LSysType::I16 => "I16",
            LSysType::U16 => "U16",
            LSysType::I32 => "I32",
            LSysType::U32 => "U32",
            LSysType::I64 => "I64",
            LSysType::U64 => "U64",
            LSysType::Usize => "USize",
            LSysType::Isize => "ISize",
            LSysType::F32 => "F32",
            LSysType::F64 => "F64",
            LSysType::RawptrU8 => "rawptr[U8]",
        };
        f.write_str(s)
    }
}

impl LSysType {
    pub fn size_align(self, target: Target) -> (usize, usize) {
        let ptr = (target.model.pointer_bits / 8) as usize;
        match self {
            LSysType::Unit => (0, 1),
            LSysType::Bool | LSysType::I8 | LSysType::U8 => (1, 1),
            LSysType::I16 | LSysType::U16 => (2, 2),
            LSysType::I32 | LSysType::U32 | LSysType::F32 => (4, 4),
            LSysType::I64 | LSysType::U64 | LSysType::F64 => (8, 8),
            LSysType::Usize | LSysType::Isize | LSysType::RawptrU8 => (ptr, ptr),
        }
    }
}

pub fn map_scalar(target: Target, c: CType) -> Result<LSysType, String> {
    let t = match c {
        CType::Void => LSysType::Unit,
        CType::Bool => LSysType::U8,
        CType::Char => {
            if target.model.char_signed {
                LSysType::I8
            } else {
                LSysType::U8
            }
        }
        CType::SChar => LSysType::I8,
        CType::UChar => LSysType::U8,
        CType::Short => LSysType::I16,
        CType::UShort => LSysType::U16,
        CType::Int => LSysType::I32,
        CType::UInt => LSysType::U32,
        CType::Long => {
            if target.model.long_bits == 64 {
                LSysType::I64
            } else {
                LSysType::I32
            }
        }
        CType::ULong => {
            if target.model.long_bits == 64 {
                LSysType::U64
            } else {
                LSysType::U32
            }
        }
        CType::LongLong => LSysType::I64,
        CType::ULongLong => LSysType::U64,
        CType::SizeT => LSysType::Usize,
        CType::PtrDiffT => LSysType::Isize,
        CType::Float => LSysType::F32,
        CType::Double => LSysType::F64,
        CType::Pointer => LSysType::RawptrU8,
        CType::LongDouble => return Err("E-LS-ABI: long double is not part of C ABI v1".into()),
        CType::Varargs => return Err("E-LS-ABI: varargs is not part of C ABI v1".into()),
    };
    Ok(t)
}

pub fn layout(target: Target, c: CType) -> Result<(usize, usize), String> {
    Ok(map_scalar(target, c)?.size_align(target))
}

/// Minimal FFI signature check for Q6.
pub fn check_signature(
    target: Target,
    params: &[CType],
    ret: CType,
    has_bitfield: bool,
    enum_has_repr: bool,
) -> Result<(Vec<LSysType>, LSysType), String> {
    if has_bitfield {
        return Err("E-LS-ABI: bitfields are not part of C ABI v1".into());
    }
    if !enum_has_repr {
        return Err("E-LS-ABI: enum crossing FFI needs #[repr(C)] + integer repr".into());
    }
    let p = params
        .iter()
        .map(|c| map_scalar(target, *c))
        .collect::<Result<Vec<_>, _>>()?;
    let r = map_scalar(target, ret)?;
    Ok((p, r))
}

pub fn selftest() -> Result<(), String> {
    let x86 = crate::target::X86_64_LINUX;
    let arm = crate::target::THUMBV7EM;
    let rv = crate::target::RISCV32IMAC;

    if map_scalar(x86, CType::Char)? != LSysType::I8 {
        return Err("x86 char should be signed".into());
    }
    if map_scalar(arm, CType::Char)? != LSysType::U8 {
        return Err("thumb char should be unsigned".into());
    }
    if map_scalar(rv, CType::Char)? != LSysType::U8 {
        return Err("riscv char should be unsigned".into());
    }
    if map_scalar(x86, CType::Long)? != LSysType::I64 {
        return Err("x86 long should be i64 (LP64)".into());
    }
    if map_scalar(arm, CType::Long)? != LSysType::I32 {
        return Err("thumb long should be i32 (ILP32)".into());
    }
    if layout(x86, CType::Pointer)? != (8, 8) {
        return Err("x86 pointer layout".into());
    }
    if layout(arm, CType::Pointer)? != (4, 4) {
        return Err("thumb pointer layout".into());
    }
    if map_scalar(x86, CType::LongDouble).is_ok() {
        return Err("long double accepted".into());
    }
    if check_signature(x86, &[CType::Int], CType::Void, true, true).is_ok() {
        return Err("bitfield FFI accepted".into());
    }
    Ok(())
}
