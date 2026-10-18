//! Q2 module-level capability context.
//!
//! Decision: lexical, non-widening, no implicit inheritance. `#[forbid(unsafe)]`
//! is downward-closed; per-module knobs are local and may only tighten.

use std::collections::{BTreeMap, BTreeSet};

#[derive(Clone, Debug, Eq, PartialEq, Ord, PartialOrd)]
pub enum Capability {
    Unsafe,
    Alloc,
    Dma,
    Ffi,
    Spawn,
    Irq,
    Mmio { lo: u64, hi: u64 },
}

impl Capability {
    pub fn contains(&self, requested: &Capability) -> bool {
        match (self, requested) {
            (Capability::Mmio { lo, hi }, Capability::Mmio { lo: rlo, hi: rhi }) => {
                lo <= rlo && rhi <= hi
            }
            _ => self == requested,
        }
    }
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct Knobs {
    pub bounds_off: bool,
    pub overflow_wrapping: bool,
    pub fp_fast: bool,
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct Module {
    pub name: String,
    pub caps: BTreeSet<Capability>,
    pub forbid_unsafe: bool,
    pub knobs: Knobs,
}

impl Module {
    pub fn new(name: impl Into<String>) -> Self {
        Self {
            name: name.into(),
            caps: BTreeSet::new(),
            forbid_unsafe: false,
            knobs: Knobs::default(),
        }
    }

    pub fn cap(mut self, cap: Capability) -> Self {
        self.caps.insert(cap);
        self
    }

    pub fn forbid_unsafe(mut self) -> Self {
        self.forbid_unsafe = true;
        self
    }

    pub fn knobs(mut self, knobs: Knobs) -> Self {
        self.knobs = knobs;
        self
    }
}

#[derive(Clone, Debug, Eq, PartialEq)]
pub struct CapDiagnostic {
    pub code: &'static str,
    pub message: String,
}

#[derive(Clone, Debug, Default)]
pub struct ModuleTree {
    pub modules: BTreeMap<String, Module>,
}

impl ModuleTree {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn add(&mut self, module: Module) {
        self.modules.insert(module.name.clone(), module);
    }

    pub fn get(&self, name: &str) -> Option<&Module> {
        self.modules.get(name)
    }

    pub fn parent_name(name: &str) -> Option<String> {
        name.rsplit_once('.').map(|(parent, _)| parent.to_string())
    }

    pub fn ancestors(&self, name: &str) -> Vec<&Module> {
        let mut out = Vec::new();
        let mut cur = Self::parent_name(name);
        while let Some(p) = cur {
            if let Some(m) = self.modules.get(&p) {
                out.push(m);
            }
            cur = Self::parent_name(&p);
        }
        out
    }

    /// `#[forbid(unsafe)]` is inherited downward.
    pub fn forbids_unsafe(&self, name: &str) -> bool {
        self.get(name).map(|m| m.forbid_unsafe).unwrap_or(false)
            || self.ancestors(name).iter().any(|m| m.forbid_unsafe)
    }

    /// `unsafe` allowed only by the module's own cap, and not under forbid.
    pub fn allows_unsafe(&self, name: &str) -> bool {
        !self.forbids_unsafe(name)
            && self
                .get(name)
                .map(|m| m.caps.contains(&Capability::Unsafe))
                .unwrap_or(false)
    }

    /// Caps are not inherited: the requested cap must be in this module's set.
    pub fn require_cap(&self, name: &str, requested: &Capability) -> Result<(), CapDiagnostic> {
        let Some(module) = self.get(name) else {
            return Err(CapDiagnostic {
                code: "E-LS-CAPCTX",
                message: format!("unknown module {}", name),
            });
        };
        if module.caps.iter().any(|c| c.contains(requested)) {
            Ok(())
        } else {
            Err(CapDiagnostic {
                code: "E-LS-CAP",
                message: format!("module {} does not declare {:?}", name, requested),
            })
        }
    }

    /// Child knobs may only tighten (disable a parent loosening).
    pub fn validate(&self) -> Vec<CapDiagnostic> {
        let mut out = Vec::new();
        for module in self.modules.values() {
            for cap in &module.caps {
                if let Capability::Mmio { lo, hi } = cap {
                    if lo > hi {
                        out.push(CapDiagnostic {
                            code: "E-LS-CAP",
                            message: format!("module {} has empty Mmio range", module.name),
                        });
                    }
                }
            }
            if module.forbid_unsafe && module.caps.contains(&Capability::Unsafe) {
                out.push(CapDiagnostic {
                    code: "E-LS-CAPCTX",
                    message: format!("module {} both forbids and declares Unsafe", module.name),
                });
            }
            if self.ancestors(&module.name).iter().any(|m| m.forbid_unsafe)
                && module.caps.contains(&Capability::Unsafe)
            {
                out.push(CapDiagnostic {
                    code: "E-LS-CAPCTX",
                    message: format!(
                        "module {} re-opens Unsafe under a forbid(unsafe) ancestor",
                        module.name
                    ),
                });
            }
            if let Some(parent) = ModuleTree::parent_name(&module.name)
                .as_deref()
                .and_then(|p| self.get(p))
            {
                if module.knobs.bounds_off && !parent.knobs.bounds_off {
                    out.push(CapDiagnostic {
                        code: "E-LS-DIAL",
                        message: format!(
                            "module {} turns bounds(off) on under a safe parent",
                            module.name
                        ),
                    });
                }
                if module.knobs.overflow_wrapping && !parent.knobs.overflow_wrapping {
                    out.push(CapDiagnostic {
                        code: "E-LS-DIAL",
                        message: format!(
                            "module {} loosens overflow policy under parent {}",
                            module.name, parent.name
                        ),
                    });
                }
                if module.knobs.fp_fast && !parent.knobs.fp_fast {
                    out.push(CapDiagnostic {
                        code: "E-LS-DIAL",
                        message: format!(
                            "module {} loosens fp policy under parent {}",
                            module.name, parent.name
                        ),
                    });
                }
            }
        }
        out
    }
}

pub fn selftest() -> Result<(), String> {
    let mut tree = ModuleTree::new();
    tree.add(Module::new("drivers").cap(Capability::Unsafe));
    tree.add(Module::new("drivers.uart"));
    if tree.allows_unsafe("drivers.uart") {
        return Err("child inherited parent cap".into());
    }
    if tree
        .require_cap("drivers.uart", &Capability::Unsafe)
        .is_ok()
    {
        return Err("child used parent cap".into());
    }
    tree.add(Module::new("drivers.uart").cap(Capability::Unsafe));
    if !tree.allows_unsafe("drivers.uart") {
        return Err("own cap not accepted".into());
    }

    let mut forbidden = ModuleTree::new();
    forbidden.add(Module::new("kern").forbid_unsafe().cap(Capability::Alloc));
    forbidden.add(Module::new("kern.sub").cap(Capability::Unsafe));
    if forbidden.allows_unsafe("kern.sub") {
        return Err("forbid(unsafe) was not inherited".into());
    }
    if !forbidden.validate().iter().any(|d| d.code == "E-LS-CAPCTX") {
        return Err("forbid(unsafe) violation not diagnosed".into());
    }

    let mut knobs = ModuleTree::new();
    knobs.add(Module::new("safe"));
    knobs.add(Module::new("safe.sub").knobs(Knobs {
        bounds_off: true,
        ..Knobs::default()
    }));
    if !knobs.validate().iter().any(|d| d.code == "E-LS-DIAL") {
        return Err("child knob loosening not diagnosed".into());
    }

    let mut mmio = ModuleTree::new();
    mmio.add(
        Module::new("mmio")
            .cap(Capability::Mmio {
                lo: 0x4000_0000,
                hi: 0x4000_0fff,
            })
            .cap(Capability::Unsafe),
    );
    mmio.require_cap(
        "mmio",
        &Capability::Mmio {
            lo: 0x4000_0100,
            hi: 0x4000_01ff,
        },
    )
    .map_err(|d| d.message)?;
    if mmio
        .require_cap(
            "mmio",
            &Capability::Mmio {
                lo: 0x4000_0000,
                hi: 0x4000_2000,
            },
        )
        .is_ok()
    {
        return Err("out-of-range Mmio accepted".into());
    }
    Ok(())
}
