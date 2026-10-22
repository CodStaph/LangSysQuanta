/-
  LSys/Threads.lean

  T4e (`spec/semantics.md` T4 table, `spec/ub.md` UB-5, `spec/modes.md` R6/R8):
  the thread-domain / interleaving model for **UB-5 (data race)**.

  Scope and boundary:

  * F0 and route A are **single-threaded** (`ConfE` has no thread component,
    `EffHStepEvalCK` is one thread), so UB-5 is vacuous there; this module is
    the *extension* model that the typed fragment must satisfy.
  * The model is event based: each thread contributes a list of memory accesses
    (`Event`), with program order `pos`, an `atomic` flag and a `sync` token.
    `hb` is the transitive closure of (program order) ∪ (release→acquire with
    the same token), computed with a finite fuel (the event count) so it stays
    decidable.
  * **UB-5** (`Race`): two conflicting accesses (same location, at least one
    write) from **different threads**, not both atomic, with no happens-before
    edge in either direction.
  * The oracle `pair_class` says every conflicting cross-thread pair is
    * both-atomic*, *HB-ordered*, *HB-ordered the other way*, or *a race* — the
    "defined or UB" dichotomy for UB-5.
  * The typed-fragment guarantees mirror R6/R8:
    `no_race_if_atomic` (everything is atomic), `shared_atomic_no_race`
    (R6: any two cross-thread accesses to the same location are both atomic),
    `no_race_if_single_owner` (R8: `iso`/`val` transfer leaves one thread as
    the only one touching the location), and `no_race_single_thread` (F0
    vacuity).

  Axioms: no `Classical`; all splits are constructor/`Bool` cases and the
  concrete instances are `decide`-checked.
-/

import LSys.Runtime
import LSys.UBCode

namespace LSys

set_option linter.unusedVariables false

/-! ## 1. Events, threads and happens-before -/

abbrev Tid := Nat

inductive AccessKind where
  | read
  | write
  deriving DecidableEq, Repr

/-- A synchronization label: `rel k` is a release, `acq k` an acquire with the
    same token `k` (this is the `atom`/lock edge of R6). -/
inductive Sync where
  | none
  | rel (tok : Nat)
  | acq (tok : Nat)
  deriving DecidableEq, Repr

structure Event where
  tid : Tid
  /-- program-order index within the thread (0-based) -/
  pos : Nat
  loc : Loc
  kind : AccessKind
  atomic : Bool
  sync : Sync
  deriving DecidableEq, Repr

/-- A machine is the flat list of all events of all threads. -/
structure Machine where
  events : List Event

def isWrite (e : Event) : Bool :=
  match e.kind with
  | AccessKind.write => true
  | AccessKind.read => false

def programBefore (a b : Event) : Bool :=
  a.tid == b.tid && a.pos < b.pos

def syncEdge (a b : Event) : Bool :=
  match a.sync, b.sync with
  | Sync.rel k, Sync.acq k' => k == k'
  | _, _ => false

/-- One step of happens-before: program order or a release→acquire edge. -/
def hbStep (a b : Event) : Bool := programBefore a b || syncEdge a b

/-- Fuel-bounded reachability: is there an `hb` chain of length ≤ `fuel`? -/
def hbFuel : Nat → List Event → Event → Event → Bool
  | 0, _, _, _ => false
  | fuel + 1, es, a, b =>
      hbStep a b || es.any (fun c => hbStep a c && hbFuel fuel es c b)

/-- Happens-before.  The fuel is the event count, which bounds any simple
    chain; the model is conservative (a longer chain is not needed for the
    witnesses we check). -/
def hb (es : List Event) (a b : Event) : Bool :=
  hbFuel (es.length + 1) es a b

/-! ## 2. Conflicts and races -/

/-- Same location, at least one write, different threads. -/
def conflict (a b : Event) : Bool :=
  a.loc == b.loc && (isWrite a || isWrite b) && a.tid != b.tid

/-- Two atomics synchronize, so they never race with each other. -/
def atomicPair (a b : Event) : Bool := a.atomic && b.atomic

/-- A **race pair**: conflicting, not both atomic, and no HB edge either way. -/
def racePair (es : List Event) (a b : Event) : Bool :=
  conflict a b && !atomicPair a b && !(hb es a b) && !(hb es b a)

/-- **UB-5**: the machine has a racing pair. -/
def Race (m : Machine) : Prop :=
  ∃ a, a ∈ m.events ∧ ∃ b, b ∈ m.events ∧ racePair m.events a b = true

/-- The executable race detector (`decide`-checkable on concrete machines). -/
def raceB (m : Machine) : Bool :=
  m.events.any (fun a => m.events.any (fun b => racePair m.events a b))

inductive RaceEvent (m : Machine) : UBCode → Prop where
  | race (h : Race m) : RaceEvent m UBCode.race

theorem raceEvent_outside {m : Machine} {k : UBCode} (h : RaceEvent m k) :
    OutsideF0 k := by
  cases h
  simp [OutsideF0]

/-! ## 3. `Bool`/list plumbing -/

theorem any_eq_true {α : Type} {p : α → Bool} {l : List α} :
    (l.any p = true) ↔ ∃ a, a ∈ l ∧ p a = true := by
  induction l with
  | nil =>
      constructor
      · intro h
        cases h
      · intro h
        cases h with
        | intro a rest =>
            cases rest with
            | intro hmem _ => cases hmem
  | cons x xs ih =>
      cases hp : p x with
      | true =>
          constructor
          · intro _
            exact ⟨x, List.Mem.head xs, hp⟩
          · intro _
            show (p x || xs.any p) = true
            rw [hp]
            rfl
      | false =>
          have hany : (x :: xs).any p = xs.any p := by
            show (p x || xs.any p) = xs.any p
            rw [hp]
            rfl
          constructor
          · intro h
            rw [hany] at h
            cases ih.mp h with
            | intro a rest =>
                exact ⟨a, List.Mem.tail x rest.1, rest.2⟩
          · intro h
            rw [hany]
            cases h with
            | intro a rest =>
                cases rest with
                | intro hmem hpv =>
                    cases hmem with
                    | head =>
                        rw [hp] at hpv
                        cases hpv
                    | tail _ htail => exact ih.mpr ⟨a, htail, hpv⟩

theorem raceB_iff_race (m : Machine) : raceB m = true ↔ Race m := by
  unfold raceB Race
  constructor
  · intro h
    cases any_eq_true.mp h with
    | intro a rest =>
        cases any_eq_true.mp rest.2 with
        | intro b rest2 =>
            exact ⟨a, rest.1, b, rest2.1, rest2.2⟩
  · intro h
    cases h with
    | intro a rest =>
        cases rest with
        | intro hmem rest2 =>
            cases rest2 with
            | intro b rest3 =>
                exact any_eq_true.mpr ⟨a, hmem, any_eq_true.mpr ⟨b, rest3.1, rest3.2⟩⟩

/-- `a != b` gives `a ≠ b` (Nat). -/
theorem ne_of_bne_true {a b : Nat} (h : (a != b) = true) : a ≠ b := by
  intro heq
  subst heq
  have h2 : (!(a == a)) = true := h
  have hb : (a == a) = true := Nat.beq_refl a
  rw [hb] at h2
  cases h2

/-! ### Field projections from the race predicates -/

theorem conflict_loc {a b : Event} (h : conflict a b = true) : a.loc = b.loc := by
  unfold conflict at h
  simp only [Bool.and_eq_true] at h
  exact eq_of_beq_true h.1.1

theorem conflict_tid_ne {a b : Event} (h : conflict a b = true) : a.tid ≠ b.tid := by
  unfold conflict at h
  simp only [Bool.and_eq_true] at h
  exact ne_of_bne_true h.2

theorem racePair_conflict {es : List Event} {a b : Event}
    (h : racePair es a b = true) : conflict a b = true := by
  unfold racePair at h
  simp only [Bool.and_eq_true] at h
  exact h.1.1.1

theorem racePair_not_atomic {es : List Event} {a b : Event}
    (h : racePair es a b = true) : atomicPair a b = false := by
  unfold racePair at h
  simp only [Bool.and_eq_true] at h
  cases hat : atomicPair a b with
  | false => rfl
  | true =>
      have hnot : (!atomicPair a b) = true := h.1.1.2
      rw [hat] at hnot
      cases hnot

theorem atomicPair_false {a b : Event} (h : atomicPair a b = false) :
    a.atomic = false ∨ b.atomic = false := by
  unfold atomicPair at h
  cases ha : a.atomic with
  | false => exact Or.inl rfl
  | true =>
      cases hb : b.atomic with
      | false => exact Or.inr rfl
      | true =>
          rw [ha, hb] at h
          cases h

theorem racePair_of_not_both {es : List Event} {a b : Event}
    (hc : conflict a b = true) (hpair : atomicPair a b = false)
    (h1 : hb es a b = false) (h2 : hb es b a = false) :
    racePair es a b = true := by
  unfold racePair
  rw [hc, hpair, h1, h2]
  rfl

/-! ## 4. The UB-5 dichotomy -/

/-- Every conflicting cross-thread pair is: both atomic (atomics synchronize),
    HB-ordered one way or the other, or a race.  This is the "defined or UB-5"
    oracle for UB-5. -/
theorem pair_class {m : Machine} {a b : Event}
    (hc : conflict a b = true) :
    atomicPair a b = true ∨ hb m.events a b = true ∨ hb m.events b a = true ∨
      racePair m.events a b = true := by
  cases haa : a.atomic with
  | true =>
      cases hbb : b.atomic with
      | true =>
          exact Or.inl (by unfold atomicPair; rw [haa, hbb]; rfl)
      | false =>
          have hpair : atomicPair a b = false := by
            unfold atomicPair; rw [haa, hbb]; rfl
          cases h1 : hb m.events a b with
          | true => exact Or.inr (Or.inl rfl)
          | false =>
              cases h2 : hb m.events b a with
              | true => exact Or.inr (Or.inr (Or.inl rfl))
              | false =>
                  exact Or.inr (Or.inr (Or.inr
                    (racePair_of_not_both hc hpair h1 h2)))
  | false =>
      cases hbb : b.atomic with
      | true =>
          have hpair : atomicPair a b = false := by
            unfold atomicPair; rw [haa, hbb]; rfl
          cases h1 : hb m.events a b with
          | true => exact Or.inr (Or.inl rfl)
          | false =>
              cases h2 : hb m.events b a with
              | true => exact Or.inr (Or.inr (Or.inl rfl))
              | false =>
                  exact Or.inr (Or.inr (Or.inr
                    (racePair_of_not_both hc hpair h1 h2)))
      | false =>
          have hpair : atomicPair a b = false := by
            unfold atomicPair; rw [haa, hbb]; rfl
          cases h1 : hb m.events a b with
          | true => exact Or.inr (Or.inl rfl)
          | false =>
              cases h2 : hb m.events b a with
              | true => exact Or.inr (Or.inr (Or.inl rfl))
              | false =>
                  exact Or.inr (Or.inr (Or.inr
                    (racePair_of_not_both hc hpair h1 h2)))

/-- A race needs two different threads. -/
theorem race_needs_two_threads {m : Machine} (h : Race m) :
    ∃ a, a ∈ m.events ∧ ∃ b, b ∈ m.events ∧ a.tid ≠ b.tid := by
  cases h with
  | intro a rest =>
      cases rest with
      | intro hmem rest2 =>
          cases rest2 with
          | intro b rest3 =>
              exact ⟨a, hmem, b, rest3.1,
                conflict_tid_ne (racePair_conflict rest3.2)⟩

/-! ## 5. Typed-fragment guarantees (R6 / R8 / F0) -/

/-- All accesses are atomic (atomics never race with atomics). -/
theorem no_race_if_atomic {m : Machine} (h : ∀ e, e ∈ m.events → e.atomic = true) :
    ¬ Race m := by
  intro hr
  cases hr with
  | intro a rest =>
      cases rest with
      | intro hmem rest2 =>
          cases rest2 with
          | intro b rest3 =>
              have hnot := racePair_not_atomic rest3.2
              unfold atomicPair at hnot
              rw [h a hmem, h b rest3.1] at hnot
              cases hnot

/-- **R6**: if any two cross-thread accesses to the same location are both
    atomic, the machine has no race.  (`shared` requires `atom`; plain access to
    a shared place is exactly the `E-LS-RACE` family.) -/
theorem shared_atomic_no_race {m : Machine}
    (h : ∀ a b, a ∈ m.events → b ∈ m.events → a.loc = b.loc → a.tid ≠ b.tid →
      a.atomic = true ∧ b.atomic = true) : ¬ Race m := by
  intro hr
  cases hr with
  | intro a rest =>
      cases rest with
      | intro hmem rest2 =>
          cases rest2 with
          | intro b rest3 =>
              have hconf := racePair_conflict rest3.2
              have hnot := racePair_not_atomic rest3.2
              have hpair := h a b hmem rest3.1 (conflict_loc hconf)
                (conflict_tid_ne hconf)
              unfold atomicPair at hnot
              rw [hpair.1, hpair.2] at hnot
              cases hnot

/-- **R8**: if every location is touched by a single thread only (after an
    `iso`/`val` transfer the old thread no longer accesses it), there is no
    race. -/
def SingleOwner (m : Machine) : Prop :=
  ∀ (loc : Loc) (a b : Event), a ∈ m.events → b ∈ m.events →
    a.loc = loc → b.loc = loc → a.tid = b.tid

theorem no_race_if_single_owner {m : Machine} (h : SingleOwner m) : ¬ Race m := by
  intro hr
  cases hr with
  | intro a rest =>
      cases rest with
      | intro hmem rest2 =>
          cases rest2 with
          | intro b rest3 =>
              have hconf := racePair_conflict rest3.2
              have hloc := conflict_loc hconf
              have hne := conflict_tid_ne hconf
              exact hne (h a.loc a b hmem rest3.1 rfl hloc.symm)

/-- **F0 vacuity**: a single-threaded trace (`ConfE`/`EffHStepEvalCK` are one
    thread) has no race. -/
theorem no_race_single_thread {m : Machine} (h : ∀ e, e ∈ m.events → e.tid = 0) :
    ¬ Race m := by
  intro hr
  cases hr with
  | intro a rest =>
      cases rest with
      | intro hmem rest2 =>
          cases rest2 with
          | intro b rest3 =>
              have hconf := racePair_conflict rest3.2
              have hne := conflict_tid_ne hconf
              exact hne (by rw [h a hmem, h b rest3.1])

/-! ## 6. Concrete instances (`spec/conformance` R6/R8 shapes) -/

def tev (tid pos loc : Nat) (kind : AccessKind) (atomic : Bool) (sync : Sync) : Event :=
  { tid := tid, pos := pos, loc := loc, kind := kind, atomic := atomic, sync := sync }


/-- Two plain conflicting accesses from two threads, no synchronization ⇒ race. -/
def mRace : Machine :=
  { events := [tev 0 0 0 AccessKind.write false Sync.none,
               tev 1 0 0 AccessKind.read false Sync.none] }

/-- The `E-LS-RACE-r6-shared-plain-write` shape: plain write vs. atomic read. -/
def mSharedPlainWrite : Machine :=
  { events := [tev 0 0 0 AccessKind.write false Sync.none,
               tev 1 0 0 AccessKind.read true Sync.none] }

/-- Both accesses atomic ⇒ no race. -/
def mAtomic : Machine :=
  { events := [tev 0 0 0 AccessKind.write true Sync.none,
               tev 1 0 0 AccessKind.read true Sync.none] }

/-- Release/acquire with the same token orders the pair ⇒ no race. -/
def mSynced : Machine :=
  { events := [tev 0 0 0 AccessKind.write false (Sync.rel 7),
               tev 1 0 0 AccessKind.read false (Sync.acq 7)] }

/-- Same thread, two accesses ⇒ no race (conflict needs two threads). -/
def mSameThread : Machine :=
  { events := [tev 0 0 0 AccessKind.write false Sync.none,
               tev 0 1 0 AccessKind.read false Sync.none] }

/-- Different locations ⇒ no race. -/
def mDisjoint : Machine :=
  { events := [tev 0 0 0 AccessKind.write false Sync.none,
               tev 1 0 1 AccessKind.read false Sync.none] }

/-- Two plain reads ⇒ no race (no write). -/
def mBothRead : Machine :=
  { events := [tev 0 0 0 AccessKind.read false Sync.none,
               tev 1 0 0 AccessKind.read false Sync.none] }

/-- R8/`iso` transfer: only one thread touches the location ⇒ no race. -/
def mSingleOwner : Machine :=
  { events := [tev 0 0 0 AccessKind.write false Sync.none,
               tev 0 1 0 AccessKind.read false Sync.none,
               tev 0 2 1 AccessKind.write false Sync.none] }

theorem race_witness : raceB mRace = true := by decide

theorem race_shared_plain_write : raceB mSharedPlainWrite = true := by decide

theorem atomic_no_race : raceB mAtomic = false := by decide

theorem synced_no_race : raceB mSynced = false := by decide

theorem same_thread_no_race : raceB mSameThread = false := by decide

theorem disjoint_no_race : raceB mDisjoint = false := by decide

theorem both_read_no_race : raceB mBothRead = false := by decide

theorem single_owner_no_race : raceB mSingleOwner = false := by decide

theorem race_implies_race_event : RaceEvent mRace UBCode.race :=
  RaceEvent.race ((raceB_iff_race mRace).mp race_witness)

end LSys
