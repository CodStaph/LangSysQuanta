/-
  LSys/Mmio.lean

  T4b of `spec/semantics.md` (the T4 table): the model for **UB-11**
  (MMIO access that is not volatile, or that the backend is allowed to
  reorder/eliminate), plus the **explicit backend trust** of
  `spec/trust.md`.

  Why T4b is not a proof about the compiler: `F0` has no `Mmio`/`Hw`, and the
  obligation "the backend does not reorder volatile accesses" cannot be
  discharged inside the language semantics.  So T4b is a *named assumption*
  with a falsifiable shape:

  1. **Typed access is volatile** — a `Mmio[T]` read/write is a `volatile`
     access by construction (`mmioAccess`), so UB-11 cannot fire on it
     (`typed_mmio_no_ub`); a plain `*T` access to an MMIO place *is* UB-11
     (`plain_mmio_is_ub`), and the case split is total (`safe_or_ub`).
  2. **Trace-level** — a `TypedTrace` (every MMIO access is volatile) has no
     UB-11 (`typed_trace_no_ub`).
  3. **Backend trust** — `Compliant` says what a compiler may do to an access
     trace: keep, drop a non-volatile access, or permute two accesses that are
     not both volatile.  `HonorsVolatile compile := ∀ t, Compliant t (compile t)`
     is the assumption written into `spec/trust.md`; under it the volatile
     subsequence (and therefore the MMIO order and the `ls cost` volatile
     count) is preserved (`honors_preserves_volatile`,
     `honors_preserves_volatile_count`).  A backend that swaps the first two
     accesses unconditionally violates it (`not_every_backend_honors`).
  4. **State** — the MMIO store `M : MmioAddr ⇀ Word` of `semantics.md` 4.4 is
     modelled separately from `σ` (`mmioWrite`/`mmioRead`, with the usual
     read-after-write lemmas).

  Axioms: no `Classical`; all splits are constructor/`Bool` cases.
-/

import LSys.UBCode

namespace LSys

set_option linter.unusedVariables false

/-! ## 1. Places, access modes, UB-11 -/

/-- Address-space kind of a place. -/
inductive PlaceSpace where
  | plain    -- ordinary memory
  | mmio     -- MMIO window
  deriving DecidableEq, Repr

/-- How a place is accessed.  A typed `Mmio[T]` access is `volatile` by
    construction; a plain `*T` access is `ordinary`. -/
inductive AccessMode where
  | ordinary
  | volatile
  deriving DecidableEq, Repr

structure MemAccess where
  space : PlaceSpace
  mode : AccessMode
  deriving DecidableEq, Repr

/-- **UB-11**: a plain access to an MMIO place — the backend may reorder or
    eliminate it, so the program has no defined MMIO semantics. -/
inductive MmioEvent (a : MemAccess) : UBCode → Prop where
  | plainOnMmio (hs : a.space = PlaceSpace.mmio) (hm : a.mode = AccessMode.ordinary) :
      MmioEvent a UBCode.mmio

theorem mmioEvent_outside {a : MemAccess} {k : UBCode} (h : MmioEvent a k) :
    OutsideF0 k := by
  cases h
  simp [OutsideF0]

/-- The access a `Mmio[T]` read/write performs: MMIO and volatile. -/
def mmioAccess : MemAccess := { space := PlaceSpace.mmio, mode := AccessMode.volatile }

theorem mmioAccess_volatile : mmioAccess.mode = AccessMode.volatile := rfl

/-- A typed `Mmio[T]` access cannot raise UB-11. -/
theorem typed_mmio_no_ub : ¬ MmioEvent mmioAccess UBCode.mmio := by
  intro h
  cases h with
  | plainOnMmio _ hm => cases hm

/-- A plain `*T` access to an MMIO place **is** UB-11. -/
theorem plain_mmio_is_ub :
    MmioEvent { space := PlaceSpace.mmio, mode := AccessMode.ordinary } UBCode.mmio :=
  MmioEvent.plainOnMmio rfl rfl

/-- Every MMIO access is either volatile (typed) or UB-11: the classification
    of UB-11 is total.  This is the "gate" reading of `effects.md`: the type
    fixes volatile, so the only way to lose it is a plain access. -/
theorem safe_or_ub {a : MemAccess} (hs : a.space = PlaceSpace.mmio) :
    a.mode = AccessMode.volatile ∨ MmioEvent a UBCode.mmio := by
  cases h : a.mode with
  | volatile => exact Or.inl rfl
  | ordinary => exact Or.inr (MmioEvent.plainOnMmio hs h)

/-! ## 2. MMIO store `M : MmioAddr ⇀ Word`

`semantics.md` 4.4 keeps MMIO *outside* the language state `σ`: the store is
`MmioAddr ⇀ Word`.  Every read/write emits an `Hw` event; ordering is the
backend's obligation (section 3). -/

abbrev MmioAddr := Nat
abbrev Word := Nat
abbrev MmioStore := MmioAddr → Option Word

def mmioRead (m : MmioStore) (a : MmioAddr) : Option Word := m a

def mmioWrite (m : MmioStore) (a : MmioAddr) (w : Word) : MmioStore :=
  fun q => if q = a then some w else m q

theorem mmioWrite_read_same (m : MmioStore) (a : MmioAddr) (w : Word) :
    mmioRead (mmioWrite m a w) a = some w := by
  show (if a = a then some w else m a) = some w
  rw [if_pos rfl]

theorem mmioWrite_read_other {m : MmioStore} {a q : MmioAddr} (hne : q ≠ a) :
    mmioRead (mmioWrite m a q') q = m q := by
  show (if q = a then some q' else m q) = m q
  rw [if_neg hne]

/-! ## 3. Traces, the backend trust, and volatile order -/

structure TraceEv where
  id : Nat
  access : MemAccess
  deriving DecidableEq, Repr

abbrev Trace := List TraceEv

def isVolatile (e : TraceEv) : Bool :=
  match e.access.mode with
  | AccessMode.volatile => true
  | AccessMode.ordinary => false

/-- The volatile (MMIO) subsequence of a trace. -/
def volatileOnly : Trace → Trace
  | [] => []
  | e :: rest => match isVolatile e with
      | true => e :: volatileOnly rest
      | false => volatileOnly rest

/-- `ls cost` reports one volatile access per `Mmio[T]` read/write
    (`spec/cost.md`, `spec/ub.md` UB-11 oracle). -/
def volatileCount (t : Trace) : Nat := (volatileOnly t).length

/-- What a T4b-compliant backend may do to an access trace: keep an access,
    drop a **non-volatile** one, or permute two accesses that are **not both
    volatile**.  Nothing here can change the order of two volatile accesses,
    and nothing can drop a volatile access. -/
inductive Compliant : Trace → Trace → Prop where
  | nil : Compliant [] []
  | keep {a : TraceEv} {r r' : Trace} (h : Compliant r r') :
      Compliant (a :: r) (a :: r')
  | dropPlain {a : TraceEv} {r : Trace} (h : isVolatile a = false) :
      Compliant (a :: r) r
  | swapNotBoth {a b : TraceEv} {r : Trace}
      (h : ¬ (isVolatile a = true ∧ isVolatile b = true)) :
      Compliant (a :: b :: r) (b :: a :: r)
  | trans {t1 t2 t3 : Trace} (h1 : Compliant t1 t2) (h2 : Compliant t2 t3) :
      Compliant t1 t3

theorem Compliant.volatileOnly_eq {t t' : Trace} (h : Compliant t t') :
    volatileOnly t = volatileOnly t' := by
  induction h with
  | nil => rfl
  | keep _ ih =>
      simp only [volatileOnly]
      split
      next => simp [ih]
      next => exact ih
  | dropPlain hfalse =>
      simp only [volatileOnly]
      split
      next htrue => rw [hfalse] at htrue; cases htrue
      next _ => rfl
  | swapNotBoth h =>
      simp only [volatileOnly]
      split
      next ha =>
        split
        next hb => exact absurd ⟨ha, hb⟩ h
        next hb => simp [volatileOnly, ha, hb]
      next ha =>
        split
        next hb => simp [volatileOnly, ha, hb]
        next hb => simp [volatileOnly, ha, hb]
  | trans _ _ ih1 ih2 => exact ih1.trans ih2

/-- Complementary direction: the count of volatile accesses is invariant under
    a compliant transformation, so `ls cost`'s "1 volatile per `Mmio[T]`
    access" is stable under the trusted backend. -/
theorem Compliant.volatileCount_eq {t t' : Trace} (h : Compliant t t') :
    volatileCount t = volatileCount t' := by
  rw [volatileCount, volatileCount, Compliant.volatileOnly_eq h]

/-- **The T4b trust of `spec/trust.md`**: the backend only keeps, drops
    non-volatile, or permutes non-volatile pairs of accesses. -/
def HonorsVolatile (compile : Trace → Trace) : Prop :=
  ∀ t, Compliant t (compile t)

/-- Under the trust, the volatile subsequence survives compilation unchanged —
    in particular two `Mmio[T]` accesses keep their relative order. -/
theorem honors_preserves_volatile {compile : Trace → Trace}
    (h : HonorsVolatile compile) (t : Trace) :
    volatileOnly (compile t) = volatileOnly t :=
  (Compliant.volatileOnly_eq (h t)).symm

theorem honors_preserves_volatile_count {compile : Trace → Trace}
    (h : HonorsVolatile compile) (t : Trace) :
    volatileCount (compile t) = volatileCount t :=
  (Compliant.volatileCount_eq (h t)).symm

/-- A backend that swaps the first two accesses unconditionally: it violates
    the trust as soon as the first two accesses are both volatile. -/
def swapFirstTwo : Trace → Trace
  | a :: b :: rest => b :: a :: rest
  | t => t

def ev (id : Nat) (space : PlaceSpace) (mode : AccessMode) : TraceEv :=
  { id := id, access := { space := space, mode := mode } }

/-- The trust is **not** automatic: some backends reorder volatile accesses,
    and `HonorsVolatile` is false for them.  This is why `spec/trust.md` must
    record the assumption explicitly instead of claiming a theorem. -/
theorem not_every_backend_honors : ¬ HonorsVolatile swapFirstTwo := by
  intro h
  have hv := honors_preserves_volatile h
    [ev 0 PlaceSpace.mmio AccessMode.volatile, ev 1 PlaceSpace.mmio AccessMode.volatile]
  exact absurd hv (by decide)

/-! ### Trace-level UB-11: the typed fragment is safe -/

/-- The typed fragment: every access to an MMIO place is volatile. -/
def TypedTrace (t : Trace) : Prop :=
  ∀ e, e ∈ t → e.access.space = PlaceSpace.mmio → e.access.mode = AccessMode.volatile

/-- There is an MMIO access the backend is free to reorder or drop. -/
def MmioUB (t : Trace) : Prop :=
  ∃ e, e ∈ t ∧ MmioEvent e.access UBCode.mmio

/-- **T4b, language side**: in the typed fragment UB-11 never fires.  The
    remaining obligation is the backend trust (section 3). -/
theorem typed_trace_no_ub {t : Trace} (h : TypedTrace t) : ¬ MmioUB t := by
  intro hbad
  cases hbad with
  | intro e rest =>
      cases rest with
      | intro hmem hev =>
          cases hev with
          | plainOnMmio hs hm =>
              have hv := h e hmem hs
              rw [hm] at hv
              cases hv

/-- A plain (untyped) MMIO access in the trace is exactly UB-11. -/
theorem untyped_mmio_has_ub :
    MmioUB [ev 0 PlaceSpace.mmio AccessMode.ordinary] := by
  refine ⟨ev 0 PlaceSpace.mmio AccessMode.ordinary, ?_, MmioEvent.plainOnMmio rfl rfl⟩
  exact List.Mem.head []

/-- A typed `Mmio[T]` trace has no UB-11 (positive counterpart of the dossier
    negative case). -/
theorem typed_mmio_trace_no_ub : ¬ MmioUB [ev 0 PlaceSpace.mmio AccessMode.volatile] := by
  apply typed_trace_no_ub
  intro e hmem hs
  cases hmem with
  | head => rfl
  | tail _ h => cases h

end LSys
