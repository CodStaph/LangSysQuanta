/-
  LSys/UBCode.lean

  The 15 UB classes of `spec/ub.md` §1 as a Lean enum, plus the coverage
  classification:

  * `DefinedBehavior` — the classes the F0 core *does* observe, and whose
    occurrence is a **defined** behaviour (abort or wrapping), not UB;
  * `OutsideF0` — the classes deliberately outside the F0 fragment; they are
    handled by T1/T3/static checks, or are the responsibility of T4b–T4e
    (`semantics.md` §T4 table).

  `ub_partition` shows that every code is in exactly one of the two groups, so
  the 15-entry list is covered without gaps.  (Before this module existed the
  enum only had 12 codes and `OutsideF0` 7, so UB-9/10/15 were not even
  representable.)

  The module is imported by `Runtime` (runtime UB events, UB-2/3/4) and `T4a`
  (F0 events), which is why it sits below both.
-/

namespace LSys

/-- The 15 UB classes of `spec/ub.md` §1, in order. -/
inductive UBCode where
  | bounds      -- UB-1  越界读/写
  | dangling    -- UB-2  悬垂引用/指针
  | doubleFree  -- UB-3  double free / 重复 drop
  | uninit      -- UB-4  使用未初始化
  | race        -- UB-5  数据竞争
  | overflow    -- UB-6  整数溢出
  | divZero     -- UB-7  除零 / 非法移位
  | rawUnsafe   -- UB-8  解引用 null/野指针
  | unaligned   -- UB-9  未对齐访问
  | provenance  -- UB-10 违反 provenance
  | mmio        -- UB-11 MMIO 非 volatile 访问
  | evalOrder   -- UB-12 未定义求值顺序
  | stack       -- UB-13 栈溢出
  | dropUse     -- UB-14 drop 期间使用已释放对象
  | unwind      -- UB-15 跨 FFI 的 unwind
  deriving Repr, DecidableEq

/-- Codes whose occurrence is a *defined* behaviour (abort/wrap), i.e. the ones
    the F0 core observes without that being UB. -/
def DefinedBehavior : UBCode → Bool
  | .bounds => true
  | .overflow => true
  | .divZero => true
  | .evalOrder => true
  | .dropUse => true
  | _ => false

/-- The F0 event codes: the same five classes as `DefinedBehavior`. -/
def F0Code : UBCode → Bool := DefinedBehavior

/-- UB classes deliberately outside the F0 fragment. -/
def OutsideF0 : UBCode → Prop
  | .dangling => True
  | .doubleFree => True
  | .uninit => True
  | .race => True
  | .rawUnsafe => True
  | .unaligned => True
  | .provenance => True
  | .mmio => True
  | .stack => True
  | .unwind => True
  | _ => False

/-- An F0 code is a defined behaviour. -/
theorem f0Code_defined {c : UBCode} (h : F0Code c = true) :
    DefinedBehavior c = true := h

/-- A code outside F0 is not a defined behaviour (it *is* UB). -/
theorem outside_not_defined {c : UBCode} (h : OutsideF0 c) :
    DefinedBehavior c = false := by
  cases c <;> simp [OutsideF0, DefinedBehavior] at h ⊢

/-- **15/15 coverage**: every code is either an F0 (defined) event or
    explicitly outside the F0 fragment. -/
theorem ub_partition (c : UBCode) : F0Code c = true ∨ OutsideF0 c := by
  cases c <;> simp [F0Code, DefinedBehavior, OutsideF0]

end LSys
