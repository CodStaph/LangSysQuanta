// EXPECT: E-LS-EFFECT
// Q4 condition 1 is transitive: a public struct field containing rawptr
// blocks Unsafe termination even though the parameter type is not rawptr.
struct HiddenPtr { p: rawptr[U8] }

fn wrapper(cap: Cap[Unsafe], h: HiddenPtr) -> U32 eff(Write) {
    unsafe { 1 }
}
