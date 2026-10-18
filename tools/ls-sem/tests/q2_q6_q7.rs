use ls_sem::abi::{map_scalar, CType, LSysType};
use ls_sem::cap_context::{Capability, Knobs, Module, ModuleTree};
use ls_sem::target::{by_triple, validate_config, Atomics, FloatAbi};

#[test]
fn q2_child_does_not_inherit_cap() {
    let mut tree = ModuleTree::new();
    tree.add(Module::new("drivers").cap(Capability::Unsafe));
    tree.add(Module::new("drivers.uart"));
    assert!(!tree.allows_unsafe("drivers.uart"));
    assert!(tree
        .require_cap("drivers.uart", &Capability::Unsafe)
        .is_err());
}

#[test]
fn q2_forbid_is_downward_closed() {
    let mut tree = ModuleTree::new();
    tree.add(Module::new("kern").forbid_unsafe());
    tree.add(Module::new("kern.sub").cap(Capability::Unsafe));
    assert!(!tree.allows_unsafe("kern.sub"));
    assert!(tree.validate().iter().any(|d| d.code == "E-LS-CAPCTX"));
}

#[test]
fn q2_child_knob_cannot_loosen() {
    let mut tree = ModuleTree::new();
    tree.add(Module::new("safe"));
    tree.add(Module::new("safe.sub").knobs(Knobs {
        overflow_wrapping: true,
        ..Knobs::default()
    }));
    assert!(tree.validate().iter().any(|d| d.code == "E-LS-DIAL"));
}

#[test]
fn q2_mmio_range_is_contained() {
    let mut tree = ModuleTree::new();
    tree.add(Module::new("mmio").cap(Capability::Mmio {
        lo: 0x4000_0000,
        hi: 0x4000_0fff,
    }));
    assert!(tree
        .require_cap(
            "mmio",
            &Capability::Mmio {
                lo: 0x4000_0100,
                hi: 0x4000_01ff,
            }
        )
        .is_ok());
    assert!(tree
        .require_cap(
            "mmio",
            &Capability::Mmio {
                lo: 0x4000_0000,
                hi: 0x4000_2000,
            }
        )
        .is_err());
}

#[test]
fn q6_char_and_long_are_target_specific() {
    let x86 = by_triple("x86_64-unknown-linux-gnu").unwrap();
    let arm = by_triple("thumbv7em-none-eabihf").unwrap();
    let rv = by_triple("riscv32imac-unknown-none-elf").unwrap();

    assert_eq!(map_scalar(x86, CType::Char).unwrap(), LSysType::I8);
    assert_eq!(map_scalar(arm, CType::Char).unwrap(), LSysType::U8);
    assert_eq!(map_scalar(rv, CType::Char).unwrap(), LSysType::U8);
    assert_eq!(map_scalar(x86, CType::Long).unwrap(), LSysType::I64);
    assert_eq!(map_scalar(arm, CType::Long).unwrap(), LSysType::I32);
}

#[test]
fn q6_rejects_long_double_and_bitfields() {
    let x86 = by_triple("x86_64-unknown-linux-gnu").unwrap();
    assert!(map_scalar(x86, CType::LongDouble).is_err());
    assert!(ls_sem::check_signature(x86, &[CType::Int], CType::Void, true, true).is_err());
    assert!(ls_sem::check_signature(x86, &[CType::Int], CType::Void, false, false).is_err());
}

#[test]
fn q7_matrix_rejects_unknown_and_overcommit() {
    assert!(by_triple("aarch64-unknown-none").is_none());
    let thumb = by_triple("thumbv7em-none-eabihf").unwrap();
    assert!(validate_config(thumb, None, Some(Atomics::U64), None).is_err());
    assert!(validate_config(thumb, Some(FloatAbi::Hard), None, None).is_ok());
    let rv = by_triple("riscv32imac-unknown-none-elf").unwrap();
    assert!(validate_config(rv, Some(FloatAbi::Hard), None, None).is_err());
}

#[test]
fn module_selftests_pass() {
    ls_sem::cap_context::selftest().unwrap();
    ls_sem::abi::selftest().unwrap();
    ls_sem::target::selftest().unwrap();
}
