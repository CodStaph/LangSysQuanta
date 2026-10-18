#[repr(C)]
struct RawRing { buf: rawptr[U8], cap: USize, head: USize, tail: USize }

unsafe fn raw_push(r: rawptr[RawRing], v: U8) -> Bool
    requires is_alloc(r.buf, r.cap) && r.tail >= r.head && r.tail - r.head <= r.cap
{
    if (*r).tail - (*r).head == (*r).cap { return false; }
    *((*r).buf + ((*r).tail % (*r).cap)) = v;   // provenance 由契约承担
    (*r).tail += 1;                              // kernel 默认 wrapping
    true
}
