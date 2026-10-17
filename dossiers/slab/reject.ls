// Dossier C / reject — every item below must be rejected.
// Target: 00 §4.3/§4.6/§4.9, 03 §4.2.

module kernel.bad;

struct Slab { base: rawptr[U8], cap: USize, free: rawptr[U8], used: USize }
struct Link { next: Option[rawptr[Link]] }
struct List { head: Option[rawptr[Link]] }
struct Node { data: U32 }

// EXPECT: E-LS-PROV
// Double free: the second free violates !is_free(s, p).
fn double_free(s: ref[Slab], p: rawptr[U8]) -> Result[Unit, Error] {
    free(s, p)?;
    free(s, p)?;
    Ok(())
}

// EXPECT: E-LS-PROV
// Linking an already-linked node violates is_unlinked(n).
fn double_link(l: ref[List], n: rawptr[Link]) -> Result[Unit, Error] {
    push(l, n)?;
    push(l, n)?;
    Ok(())
}

// EXPECT: E-LS-MOVE
// Mmio[T] is affine: it cannot be copied.
fn copy_mmio(a: Mmio[U32]) -> (Mmio[U32], Mmio[U32]) {
    (a, a)
}

// EXPECT: E-LS-LEAK
// DmaToken is linear; dropping it without wait/release leaks the device ownership.
fn forget_dma(d: DmaToken) {
    let _ = d;
}

// EXPECT: E-LS-DIAL
// Disabling bounds checks requires a contract and CI evidence.
#[bounds(off)]
fn unchecked_index(a: ref[Slice[U8]], i: USize) -> U8 {
    a[i]
}

// EXPECT: E-LS-REGION-ESCAPE
// Alloc[Region] cannot be stored in a field: rho would escape.
struct BadHolder { a: Alloc[Region] }

// EXPECT: E-LS-STATIC
// No bare static mut.
static mut COUNTER: U32 = 0;

// EXPECT: E-LS-CAPCTX
// A module without #[cap(Unsafe)] cannot open an unsafe block.
fn no_cap(p: rawptr[U32]) -> U32 {
    unsafe { *p }
}
