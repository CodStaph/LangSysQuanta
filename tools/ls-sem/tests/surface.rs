use ls_sem::surface::{check_source, CheckOptions};

fn check(src: &str) -> ls_sem::CheckReport {
    check_source(src, CheckOptions::default())
}

fn check_budget(src: &str, budget: usize) -> ls_sem::CheckReport {
    check_source(
        src,
        CheckOptions {
            arena_budget: budget,
        },
    )
}

fn assert_ok_budget(src: &str, budget: usize) {
    let report = check_budget(src, budget);
    assert!(
        report.ok(),
        "expected success with budget {}, got: {:?}",
        budget,
        report.diagnostics
    );
}

fn assert_ok(src: &str) {
    let report = check(src);
    assert!(
        report.ok(),
        "expected success, got: {:?}",
        report.diagnostics
    );
}

fn assert_code(src: &str, budget: usize, code: &str) {
    let report = check_budget(src, budget);
    assert!(
        report.diagnostics.iter().any(|d| d.code == code),
        "expected {} in {:?}",
        code,
        report.diagnostics
    );
}

// -- item 1: Buffer[T], regions and ownership -------------------------------

#[test]
fn buffer_allocation_and_push_in_region() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](4, R);
                b.push(1);
                b.push(2);
            }
            return;
        }
        "#,
    );
}

#[test]
fn inner_region_value_cannot_escape_to_function() {
    assert_code(
        r#"
        fn make() -> Buffer[Int] eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](2, R);
                return b;
            }
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
}

#[test]
fn buffer_from_heap_may_escape() {
    assert_ok(
        r#"
        fn make() -> Buffer[Int] eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            return b;
        }
        "#,
    );
}

#[test]
fn inner_region_buffer_cannot_be_stored_in_outer_buffer() {
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            region Outer {
                let outer: Buffer[Buffer[Int]] = Buffer.new[Buffer[Int]](2, Outer);
                region Inner {
                    let inner: Buffer[Int] = Buffer.new[Int](2, Inner);
                    outer.push(inner);
                }
            }
            return;
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
}

#[test]
fn outer_region_buffer_can_be_stored_in_inner_buffer() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            region Outer {
                let outer: Buffer[Int] = Buffer.new[Int](2, Outer);
                region Inner {
                    let inner: Buffer[Buffer[Int]] = Buffer.new[Buffer[Int]](2, Inner);
                    inner.push(outer);
                }
            }
            return;
        }
        "#,
    );
}

#[test]
fn unknown_region_is_rejected() {
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, Nope);
            return;
        }
        "#,
        1 << 20,
        "E-LS-REGION",
    );
}

// -- item 2: multi-parameter generics, bounds, unification -------------------

#[test]
fn multi_parameter_generic_struct_and_function() {
    assert_ok(
        r#"
        struct Pair[A, B] { first: A, second: B }

        fn swap[A, B](p: Pair[A, B]) -> Pair[B, A] {
            return Pair.new[B, A](p.second, p.first);
        }

        fn pair[A, B](a: A, b: B) -> Pair[A, B] {
            return Pair.new[A, B](a, b);
        }

        fn main() -> Unit {
            let p: Pair[Int, Str] = pair(1, "x");
            let q: Pair[Str, Int] = swap[Int, Str](p);
            return;
        }
        "#,
    );
}

#[test]
fn nested_generic_unification_mismatch_is_rejected() {
    assert_code(
        r#"
        struct Pair[A, B] { first: A, second: B }
        fn pair[A, B](a: A, b: B) -> Pair[A, B] {
            return Pair.new[A, B](a, b);
        }
        fn main() -> Unit {
            let p: Pair[Int, Str] = pair(1, 2);
            return;
        }
        "#,
        1 << 20,
        "E-LS-TYPE",
    );
}

#[test]
fn generic_bound_is_required_and_forwarded() {
    assert_ok(
        r#"
        fn max[T: Ord](a: T, b: T) -> T {
            if a > b { return a; }
            return b;
        }
        fn both[U: Ord](a: U, b: U) -> U {
            return max[U](a, b);
        }
        fn main() -> Unit {
            let n: Int = both[Int](1, 2);
            let s: Str = max[Str]("a", "b");
            return;
        }
        "#,
    );
}

#[test]
fn missing_bound_on_generic_parameter_is_rejected() {
    assert_code(
        r#"
        fn max[T: Ord](a: T, b: T) -> T {
            if a > b { return a; }
            return b;
        }
        fn forward[U](a: U, b: U) -> U {
            return max[U](a, b);
        }
        "#,
        1 << 20,
        "E-LS-TRAIT",
    );
}

#[test]
fn concrete_type_without_trait_is_rejected() {
    assert_code(
        r#"
        fn max[T: Ord](a: T, b: T) -> T {
            if a > b { return a; }
            return b;
        }
        fn main() -> Unit eff(Alloc) {
            let a: Buffer[Int] = Buffer.new[Int](1, heap);
            let b: Buffer[Int] = Buffer.new[Int](1, heap);
            let c: Buffer[Int] = max[Buffer[Int]](a, b);
            return;
        }
        "#,
        1 << 20,
        "E-LS-TRAIT",
    );
}

#[test]
fn arithmetic_constraint_on_generic_type() {
    assert_ok(
        r#"
        fn add[T: Arith](a: T, b: T) -> T { return a + b; }
        fn main() -> Unit {
            let n: Int = add[Int](1, 2);
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn add[T: Arith](a: T, b: T) -> T { return a + b; }
        fn main() -> Unit { let s: Str = add[Str]("a", "b"); return; }
        "#,
        1 << 20,
        "E-LS-TRAIT",
    );
}

// -- item 3: val/ref, effects, contracts, comptime --------------------------

#[test]
fn ref_parameter_cannot_escape_or_be_stored() {
    assert_code(
        r#"
        fn leak(ref b: Buffer[Int]) -> Buffer[Int] { return b; }
        "#,
        1 << 20,
        "E-LS-MODE",
    );
    assert_code(
        r#"
        fn store(ref x: Buffer[Int], dst: Buffer[Buffer[Int]]) -> Unit {
            dst.push(x);
            return;
        }
        "#,
        1 << 20,
        "E-LS-MODE",
    );
}

#[test]
fn val_parameter_cannot_be_moved_into_owned_parameter() {
    assert_code(
        r#"
        fn take(b: Buffer[Int]) -> Unit { return; }
        fn f(val b: Buffer[Int]) -> Unit {
            take(b);
            return;
        }
        "#,
        1 << 20,
        "E-LS-MODE",
    );
}

#[test]
fn undeclared_effects_are_rejected() {
    assert_code(
        r#"
        fn make() -> Buffer[Int] {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            return b;
        }
        "#,
        1 << 20,
        "E-LS-EFFECT",
    );
    assert_code(
        r#"
        fn hello() -> Unit { write("hi"); return; }
        "#,
        1 << 20,
        "E-LS-EFFECT",
    );
}

#[test]
fn contracts_are_checked_as_bool_and_result_is_visible() {
    assert_ok(
        r#"
        fn positive(x: Int) -> Int requires x > 0 ensures result >= 0 {
            return x;
        }
        "#,
    );
    assert_code(
        r#"
        fn bad(x: Int) -> Int requires x { return x; }
        "#,
        1 << 20,
        "E-LS-TYPE",
    );
}

#[test]
fn comptime_rejects_runtime_expressions() {
    assert_ok(
        r#"
        fn main() -> Unit {
            comptime { let n = 1 + 2 * 3; }
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn f(x: Int) -> Int { return x; }
        fn main() -> Unit {
            comptime { let n = f(1); }
            return;
        }
        "#,
        1 << 20,
        "E-LS-COMPTIME",
    );
}

// -- item 4: fallible allocation, arena budget and reclamation ---------------

#[test]
fn infallible_allocation_reports_budget_exhaustion() {
    let report = check_budget(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](4, heap);
            return;
        }
        "#,
        16,
    );
    assert!(report.diagnostics.iter().any(|d| d.code == "E-LS-ALLOC"));
    assert_eq!(report.arena.budget, 16);
    assert!(report.arena.rejections >= 1);
}

#[test]
fn try_new_is_fallible_and_reports_rejection_without_error() {
    let report = check_budget(
        r#"
        fn main() -> Result[Buffer[Int], AllocError] eff(Alloc) {
            return Buffer.try_new[Int](4, heap);
        }
        "#,
        8,
    );
    assert!(report.ok(), "diagnostics: {:?}", report.diagnostics);
    assert!(report.arena.rejections >= 1);
}

#[test]
fn try_new_with_question_mark_is_checked() {
    assert_ok(
        r#"
        fn make() -> Result[Buffer[Int], AllocError] eff(Alloc) {
            let b: Buffer[Int] = Buffer.try_new[Int](4, heap)?;
            return Result.Ok[Buffer[Int], AllocError](b);
        }
        "#,
    );
}

#[test]
fn sibling_regions_reclaim_before_the_next_allocation() {
    let report = check_budget(
        r#"
        fn main() -> Unit eff(Alloc) {
            region A {
                let a: Buffer[Int] = Buffer.new[Int](3, A);
            }
            region B {
                let b: Buffer[Int] = Buffer.new[Int](3, B);
            }
            return;
        }
        "#,
        32,
    );
    assert!(report.ok(), "diagnostics: {:?}", report.diagnostics);
    assert_eq!(report.arena.high_water, 24);
    assert_eq!(report.arena.used, 0);
    assert!(report.arena.reclamations >= 2);
}

#[test]
fn nested_regions_share_the_budget() {
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            region A {
                let a: Buffer[Int] = Buffer.new[Int](3, A);
                region B {
                    let b: Buffer[Int] = Buffer.new[Int](3, B);
                }
            }
            return;
        }
        "#,
        32,
        "E-LS-ALLOC",
    );
}

#[test]
fn allocation_budget_is_reclaimed_at_function_exit() {
    let report = check_budget(
        r#"
        fn one() -> Unit eff(Alloc) {
            let a: Buffer[Int] = Buffer.new[Int](3, heap);
            return;
        }
        fn two() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](3, heap);
            return;
        }
        "#,
        32,
    );
    assert!(report.ok(), "diagnostics: {:?}", report.diagnostics);
    assert_eq!(report.arena.used, 0);
}

#[test]
fn checked_fixture_is_accepted() {
    let report = check(include_str!("fixtures/regions_generics_alloc.ls"));
    assert!(report.ok(), "diagnostics: {:?}", report.diagnostics);
    assert!(report.regions >= 2);
    assert!(report.arena.reclamations >= 2);
}

#[test]
fn checked_reject_fixture_is_rejected() {
    assert_code(
        include_str!("fixtures/reject_escape.ls"),
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
}

#[test]
fn contracts_must_be_pure() {
    assert_code(
        r#"
        fn bad(x: Int) -> Int requires write("x") { return x; }
        "#,
        1 << 20,
        "E-LS-EFFECT",
    );
}

#[test]
fn buffer_len_and_cap_are_int_reads() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](4, R);
                let bytes: Int = b.len + b.cap;
            }
            return;
        }
        "#,
    );
}

#[test]
fn buffer_release_consumes_and_cannot_be_reused() {
    assert_ok(
        r#"
        fn release_it() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            b.release();
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn use_after_release() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            b.release();
            b.push(1);
            return;
        }
        "#,
        1 << 20,
        "E-LS-MOVE",
    );
    assert_code(
        r#"
        fn release_ref(ref b: Buffer[Int]) -> Unit {
            b.release();
            return;
        }
        "#,
        1 << 20,
        "E-LS-MODE",
    );
}

#[test]
fn aggregate_region_tracks_buffer_fields() {
    assert_code(
        r#"
        struct Holder { buf: Buffer[Int] }
        fn escape() -> Holder eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](2, R);
                let h: Holder = Holder.new(b);
                return h;
            }
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
    assert_code(
        r#"
        fn escape_option() -> Option[Buffer[Int]] eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](2, R);
                return Option.Some[Buffer[Int]](b);
            }
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
}

#[test]
fn buffer_push_tracks_static_capacity() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            b.push(1);
            b.push(2);
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            b.push(1);
            b.push(2);
            b.push(3);
            return;
        }
        "#,
        1 << 20,
        "E-LS-BUFFER-CAP",
    );
}

#[test]
fn let_initializer_moves_non_copy_buffer() {
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            let a: Buffer[Int] = Buffer.new[Int](2, heap);
            let b: Buffer[Int] = a;
            a.push(1);
            return;
        }
        "#,
        1 << 20,
        "E-LS-MOVE",
    );
}

#[test]
fn drop_consumes_owning_place() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            drop b;
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            drop b;
            b.push(1);
            return;
        }
        "#,
        1 << 20,
        "E-LS-MOVE",
    );
    assert_code(
        r#"
        fn bad(ref b: Buffer[Int]) -> Unit {
            drop b;
            return;
        }
        "#,
        1 << 20,
        "E-LS-MODE",
    );
    assert_code(
        r#"
        fn bad() -> Unit { drop 1; return; }
        "#,
        1 << 20,
        "E-LS-TYPE",
    );
}

#[test]
fn buffer_capacity_accepts_constant_expressions() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2 + 2, heap);
            b.push(1);
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2 * 3, heap);
            return;
        }
        "#,
        16,
        "E-LS-ALLOC",
    );
}

#[test]
fn drop_reclaims_top_arena_allocation() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            let a: Buffer[Int] = Buffer.new[Int](2, heap);
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            drop b;
            let c: Buffer[Int] = Buffer.new[Int](2, heap);
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn main() -> Unit eff(Alloc) {
            let a: Buffer[Int] = Buffer.new[Int](2, heap);
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            drop a;
            let c: Buffer[Int] = Buffer.new[Int](2, heap);
            return;
        }
        "#,
        32,
        "E-LS-ALLOC",
    );
}

#[test]
fn aggregate_buffer_field_storage_respects_region_direction() {
    assert_code(
        r#"
        struct Holder { buf: Buffer[Int] }
        fn main() -> Unit eff(Alloc) {
            region Outer {
                let outer: Buffer[Holder] = Buffer.new[Holder](2, Outer);
                region Inner {
                    let b: Buffer[Int] = Buffer.new[Int](2, Inner);
                    let h: Holder = Holder.new(b);
                    outer.push(h);
                }
            }
            return;
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
    assert_ok(
        r#"
        struct Holder { buf: Buffer[Int] }
        fn main() -> Unit eff(Alloc) {
            region Outer {
                let b: Buffer[Int] = Buffer.new[Int](2, Outer);
                let h: Holder = Holder.new(b);
                region Inner {
                    let inner: Buffer[Holder] = Buffer.new[Holder](2, Inner);
                    inner.push(h);
                }
            }
            return;
        }
        "#,
    );
}

#[test]
fn slice_borrows_buffer_region_and_blocks_release() {
    assert_ok(
        r#"
        fn main() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](4, heap);
            let s: Slice[Int] = Buffer.slice[Int](b, 1, 2);
            return;
        }
        "#,
    );
    assert_code(
        r#"
        fn bad() -> Slice[Int] eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](4, R);
                let s: Slice[Int] = Buffer.slice[Int](b, 0, 2);
                return s;
            }
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
    assert_code(
        r#"
        fn bad() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](4, heap);
            let s: Slice[Int] = Buffer.slice[Int](b, 0, 2);
            b.release();
            return;
        }
        "#,
        1 << 20,
        "E-LS-ALIAS",
    );
    assert_code(
        r#"
        fn bad() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](4, heap);
            let s: Slice[Int] = Buffer.slice[Int](b, 0, 2);
            let c: Buffer[Int] = b;
            return;
        }
        "#,
        1 << 20,
        "E-LS-ALIAS",
    );
    assert_code(
        r#"
        fn bad() -> Unit eff(Alloc) {
            let b: Buffer[Int] = Buffer.new[Int](2, heap);
            let s: Slice[Int] = Buffer.slice[Int](b, 1, 2);
            return;
        }
        "#,
        1 << 20,
        "E-LS-BUFFER-CAP",
    );
}

#[test]
fn slice_in_aggregate_keeps_region_direction() {
    assert_code(
        r#"
        struct View { s: Slice[Int] }
        fn bad() -> View eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](4, R);
                let s: Slice[Int] = Buffer.slice[Int](b, 0, 2);
                return View.new(s);
            }
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
    assert_code(
        r#"
        struct View { s: Slice[Int] }
        fn bad() -> Unit eff(Alloc) {
            region Outer {
                let dst: Buffer[View] = Buffer.new[View](2, Outer);
                region Inner {
                    let b: Buffer[Int] = Buffer.new[Int](4, Inner);
                    let s: Slice[Int] = Buffer.slice[Int](b, 0, 2);
                    dst.push(View.new(s));
                }
            }
            return;
        }
        "#,
        1 << 20,
        "E-LS-REGION-ESCAPE",
    );
}

#[test]
fn aggregate_drop_reclaims_buffer_fields() {
    assert_ok_budget(
        r#"
        struct Pair { a: Buffer[U8], b: Buffer[U8] }
        fn main() -> Unit eff(Alloc) {
            let p: Pair = Pair.new(
                Buffer.new[U8](8, heap),
                Buffer.new[U8](8, heap)
            );
            drop p;
            let c: Buffer[U8] = Buffer.new[U8](8, heap);
            return;
        }
        "#,
        16,
    );
    assert_code(
        r#"
        struct Pair { a: Buffer[U8], b: Buffer[U8] }
        fn main() -> Unit eff(Alloc) {
            let p: Pair = Pair.new(
                Buffer.new[U8](8, heap),
                Buffer.new[U8](8, heap)
            );
            drop p;
            p.a.push(1);
            return;
        }
        "#,
        1 << 20,
        "E-LS-MOVE",
    );
}

#[test]
fn nested_aggregate_drop_reclaims_inner_fields() {
    assert_ok_budget(
        r#"
        struct Inner { b: Buffer[U8] }
        struct Outer { inner: Inner, extra: Buffer[U8] }
        fn main() -> Unit eff(Alloc) {
            let o: Outer = Outer.new(
                Inner.new(Buffer.new[U8](8, heap)),
                Buffer.new[U8](8, heap)
            );
            drop o;
            let c: Buffer[U8] = Buffer.new[U8](8, heap);
            return;
        }
        "#,
        16,
    );
}

// -- L1: minimal unsat core + LS-P17 fix-it negative ------------------------

#[test]
fn escape_reports_minimal_core_and_safe_fixit() {
    let report = check(
        r#"
        fn make() -> Buffer[Int] eff(Alloc) {
            region R {
                let b: Buffer[Int] = Buffer.new[Int](2, R);
                return b;
            }
        }
        "#,
    );
    let d = report
        .diagnostics
        .iter()
        .find(|d| d.code == "E-LS-REGION-ESCAPE")
        .expect("expected E-LS-REGION-ESCAPE");
    assert!(d.message.contains("core (1 minimal)"), "{}", d.message);
    assert!(d.message.contains("return:"), "{}", d.message);
    assert!(d.message.contains("witness:"), "{}", d.message);
    let fixit = d.fixit.as_deref().expect("escape must carry a fix-it");
    for bad in ["unsafe", "rawptr", "Ffi", "Cap["] {
        assert!(
            !fixit.contains(bad),
            "fix-it must not suggest `{bad}`: {fixit}"
        );
    }
    assert!(fixit.contains("copy"), "{}", fixit);
    assert!(fixit.contains("heap"), "{}", fixit);
}

#[test]
fn unsat_core_fixture_is_reproducible() {
    let src = include_str!("fixtures/unsat_core_escape.ls");
    let report = check(src);
    assert!(!report.ok());
    let d = report
        .diagnostics
        .iter()
        .find(|d| d.code == "E-LS-REGION-ESCAPE")
        .expect("fixture must hit E-LS-REGION-ESCAPE");
    assert!(d.message.contains("core (1 minimal)"), "{}", d.message);
    assert!(d.message.contains("witness:"), "{}", d.message);
    assert!(d.fixit.is_some());
}
