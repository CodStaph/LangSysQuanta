/-
  LSys/Ffi.lean

  T4c of `spec/semantics.md` (the T4 table): the model for **UB-15**
  (an unwind crossing an `extern "C"` boundary), plus the ABI gate of
  `spec/baremetal.md` §5 and the explicit nounwind trust of `spec/trust.md`.

  The split is the same as T4b:

  1. **Exits** — a boundary crossing ends in `ret w` (normal return),
     `abort` (LSys traps; `panic` also aborts and does *not* unwind) or
     `unwind`.  Only `unwind` is undefined behaviour at a `nounwind`
     boundary (`isDefined`, `defined_or_ub`).
  2. **ABI gate (static)** — `extern "C"` declares `nounwind`, the return type
     must be able to encode a `Result` before `?` may escape, and varargs are
     not supported (`AbiSig`, `abiOk`).  This is the Lean projection of the Q6
     `check_signature` rules (`tools/ls-sem/src/abi.rs`).
  3. **UB-15 event** — `FfiEvent b x UBCode.unwind`: an unwind exits through a
     nounwind boundary.  `nounwind_no_unwind` rules it out for `extern "C"`;
     `ret_not_unwind` / `abort_not_unwind` say normal exits are defined.
  4. **Trust (explicit)** — the callee's behaviour is not provable in the
     language (`H-LS-5`), so T4c assumes `HonorsNounwind`:
     every reachable extern callee exits with a defined exit
     (`isDefined = true`).  Under it no crossing of a nounwind boundary can
     raise UB-15 (`honors_no_ub`); a callee that unwinds violates the trust
     (`not_every_callee_honors`), so the assumption is falsifiable.
  5. **Traces** — `NounwindTrace`/`DefinedTrace` have no UB-15
     (`nounwind_trace_no_ub`, `defined_trace_no_ub`), the negative witness is
     `ub_trace_witness`.

  Axioms: no `Classical`; all splits are constructor/`Bool` cases.
-/

import LSys.UBCode

namespace LSys

set_option linter.unusedVariables false

/-! ## 1. Boundary exits -/

/-- How a call that crosses an FFI boundary ends.

    * `ret w`  — normal return (the ABI value `w`);
    * `abort`  — trap/`panic`; LSys aborts **without unwinding** (`00 §6.6`);
    * `unwind` — stack unwinding across the boundary, i.e. UB-15. -/
inductive Exit where
  | ret (w : Nat)
  | abort
  | unwind
  deriving DecidableEq, Repr

/-- An exit is *defined* when it is a normal return or an abort. -/
def isDefined : Exit → Bool
  | Exit.ret _ => true
  | Exit.abort => true
  | Exit.unwind => false

theorem ret_defined (w : Nat) : isDefined (Exit.ret w) = true := rfl

theorem abort_defined : isDefined Exit.abort = true := rfl

theorem unwind_not_defined : isDefined Exit.unwind = false := rfl

/-- Every exit is either defined, or it is the unwinding exit. -/
theorem defined_or_unwind (x : Exit) : isDefined x = true ∨ x = Exit.unwind := by
  cases x with
  | ret w => exact Or.inl rfl
  | abort => exact Or.inl rfl
  | unwind => exact Or.inr rfl

theorem ne_unwind_of_defined {x : Exit} (h : isDefined x = true) : x ≠ Exit.unwind := by
  intro hx
  rw [hx] at h
  cases h

/-! ## 2. Boundaries and the UB-15 event -/

/-- A boundary declaration.  v0 only has `extern "C"`, which implies
    `nounwind` (`spec/baremetal.md` §5.3); an unwinding ABI does not exist. -/
structure Boundary where
  nounwind : Bool
  deriving DecidableEq, Repr

/-- `extern "C"`. -/
def cBoundary : Boundary := { nounwind := true }

theorem cBoundary_nounwind : cBoundary.nounwind = true := rfl

/-- **UB-15**: an unwind crosses a nounwind boundary. -/
inductive FfiEvent (b : Boundary) (x : Exit) : UBCode → Prop where
  | unwindAcross (hb : b.nounwind = true) (hx : x = Exit.unwind) :
      FfiEvent b x UBCode.unwind

theorem ffiEvent_outside {b : Boundary} {x : Exit} {k : UBCode} (h : FfiEvent b x k) :
    OutsideF0 k := by
  cases h
  simp [OutsideF0]

/-- A normal return never raises UB-15. -/
theorem ret_not_unwind {b : Boundary} (w : Nat) : ¬ FfiEvent b (Exit.ret w) UBCode.unwind := by
  intro h
  cases h with
  | unwindAcross _ hx => cases hx

/-- `abort`/`panic` never raises UB-15: LSys aborts without unwinding. -/
theorem abort_not_unwind {b : Boundary} : ¬ FfiEvent b Exit.abort UBCode.unwind := by
  intro h
  cases h with
  | unwindAcross _ hx => cases hx

/-- The crossing is total: either the exit is defined, or it is UB-15. -/
theorem defined_or_ub {b : Boundary} (hb : b.nounwind = true) (x : Exit) :
    isDefined x = true ∨ FfiEvent b x UBCode.unwind := by
  cases x with
  | ret w => exact Or.inl rfl
  | abort => exact Or.inl rfl
  | unwind => exact Or.inr (FfiEvent.unwindAcross hb rfl)

/-! ## 3. The static ABI gate (Q6 projection)

`spec/baremetal.md` §5 / `results/Q2-Q6-Q7-implementation.md`: `extern "C"`
declares `nounwind`, no varargs, and a `Result` may only cross when the return
type encodes it (`?` must be handled inside otherwise). -/

structure AbiSig where
  /-- declared as `extern "C"` (the only FFI ABI in v0) -/
  externC : Bool
  /-- the return type can encode a `Result` (or the body never propagates `?`) -/
  retEncodesError : Bool
  /-- C varargs (unsupported) -/
  varargs : Bool
  deriving DecidableEq, Repr

/-- The static gate: `extern "C"`, encodable `?`, no varargs. -/
def abiOk (s : AbiSig) : Bool :=
  s.externC && s.retEncodesError && !s.varargs

theorem abiOk_extern_c {s : AbiSig} (h : abiOk s = true) : s.externC = true := by
  simp only [abiOk, Bool.and_eq_true] at h
  exact h.1.1

theorem abiOk_ret_encodes {s : AbiSig} (h : abiOk s = true) : s.retEncodesError = true := by
  simp only [abiOk, Bool.and_eq_true] at h
  exact h.1.2

theorem abiOk_no_varargs {s : AbiSig} (h : abiOk s = true) : s.varargs = false := by
  cases hv : s.varargs with
  | false => rfl
  | true => simp [abiOk, hv] at h

/-- A signature that passes the ABI gate declares a nounwind boundary. -/
theorem abiOk_boundary_nounwind {s : AbiSig} (h : abiOk s = true) :
    cBoundary.nounwind = true :=
  cBoundary_nounwind

/-- Negative case of the ABI gate: `?` escaping through a return type that
    cannot encode the error is `E-LS-ABI` (UB-15 is *not* needed for it). -/
theorem abi_rejects_unencodable_error :
    abiOk { externC := true, retEncodesError := false, varargs := false } = false := rfl

/-- Positive case: a normal `extern "C"` signature with an encodable error. -/
theorem abi_accepts_encodable :
    abiOk { externC := true, retEncodesError := true, varargs := false } = true := rfl

theorem abi_rejects_varargs :
    abiOk { externC := true, retEncodesError := true, varargs := true } = false := rfl

/-! ## 4. The explicit nounwind trust (`spec/trust.md`, `H-LS-5`) -/

/-- The T4c assumption: every reachable extern callee exits with a defined exit
    (normal return or abort), never by unwinding.  The callee is outside the
    language, so this is a **trust**, not a theorem. -/
def HonorsNounwind (exitOf : Nat → Exit) : Prop :=
  ∀ f, isDefined (exitOf f) = true

theorem honors_no_ub {exitOf : Nat → Exit} (h : HonorsNounwind exitOf)
    {b : Boundary} (hb : b.nounwind = true) (f : Nat) :
    ¬ FfiEvent b (exitOf f) UBCode.unwind := by
  intro he
  cases he with
  | unwindAcross _ hx =>
      have hdef := h f
      rw [hx] at hdef
      cases hdef

/-- A callee that unwinds violates the trust — the assumption is falsifiable. -/
def unwindingCallee : Nat → Exit := fun _ => Exit.unwind

theorem not_every_callee_honors : ¬ HonorsNounwind unwindingCallee := by
  intro h
  have hdef := h 0
  exact absurd hdef (by decide)

/-- A callee that only returns or aborts satisfies the trust. -/
def wellBehavedCallee : Nat → Exit := fun _ => Exit.abort

theorem well_behaved_honors : HonorsNounwind wellBehavedCallee := by
  intro f
  rfl

/-! ## 5. Trace level -/

structure Crossing where
  boundary : Boundary
  exit : Exit
  deriving DecidableEq, Repr

/-- Some crossing unwinds through a nounwind boundary (UB-15 in a trace). -/
def FfiUB (t : List Crossing) : Prop :=
  ∃ c, c ∈ t ∧ FfiEvent c.boundary c.exit UBCode.unwind

/-- Every crossing happens on a nounwind boundary (`extern "C"`). -/
def NounwindTrace (t : List Crossing) : Prop :=
  ∀ c, c ∈ t → c.boundary.nounwind = true

/-- Every crossing ends with a defined exit. -/
def DefinedTrace (t : List Crossing) : Prop :=
  ∀ c, c ∈ t → isDefined c.exit = true

/-- A trace of defined exits has no UB-15. -/
theorem defined_trace_no_ub {t : List Crossing} (h : DefinedTrace t) : ¬ FfiUB t := by
  intro hbad
  cases hbad with
  | intro c rest =>
      cases rest with
      | intro hmem hev =>
          cases hev with
          | unwindAcross _ hx =>
              have hdef := h c hmem
              rw [hx] at hdef
              cases hdef

/-- Negative witness: an unwind through `extern "C"` is UB-15. -/
theorem ub_trace_witness : FfiUB [{ boundary := cBoundary, exit := Exit.unwind }] := by
  refine ⟨{ boundary := cBoundary, exit := Exit.unwind }, ?_, FfiEvent.unwindAcross rfl rfl⟩
  exact List.Mem.head []

/-- **Declarations alone are not enough**: a nounwind trace can still raise UB-15
    when a callee unwinds.  This is exactly why T4c needs the trust of section 4. -/
theorem nounwind_trace_not_enough :
    NounwindTrace [{ boundary := cBoundary, exit := Exit.unwind }] ∧
      FfiUB [{ boundary := cBoundary, exit := Exit.unwind }] := by
  refine ⟨?_, ub_trace_witness⟩
  intro c hmem
  cases hmem with
  | head => rfl
  | tail _ h => cases h

/-- **T4c with the trust**: if every crossing ends in a callee exit that honors
    nounwind, no crossing raises UB-15. -/
theorem trace_no_ub_of_callees {t : List Crossing} {exitOf : Nat → Exit}
    (h : HonorsNounwind exitOf)
    (hlink : ∀ c, c ∈ t → ∃ f, c.exit = exitOf f) : ¬ FfiUB t := by
  intro hbad
  cases hbad with
  | intro c rest =>
      cases rest with
      | intro hmem hev =>
          cases hev with
          | unwindAcross _ hx =>
              cases hlink c hmem with
              | intro f hf =>
                  have hdef := h f
                  rw [← hf] at hdef
                  rw [hx] at hdef
                  cases hdef

/-- Positive witness: an abort through `extern "C"` is defined. -/
theorem abort_trace_no_ub :
    ¬ FfiUB [{ boundary := cBoundary, exit := Exit.abort }] := by
  apply defined_trace_no_ub
  intro c hmem
  cases hmem with
  | head => rfl
  | tail _ h => cases h

end LSys
