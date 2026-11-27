// tests/gs1/rust-ref/slab.rs — Rust reference implementation of the slab
// allocator dossier (dossiers/slab/accept.ls), the D-GS1-3 counterpart
// first piece for the LS-07 comparison arm.
//
// Logic mirrors the L-Sys accept.ls: build_free_list / (*head).next read /
// (*f).next write are the three audited unsafe primitives; everything else
// stays safe Rust. unsafe-surface category mapping:
//   primitive 1  build_free_list  -> raw deref write in init loop
//   primitive 2  ptr_read         -> (*head).next
//   primitive 3  ptr_write        -> (*f).next = self.free
// This file is reference material (not a test subject); it must compile:
//   rustc --edition 2021 --crate-type lib tests/gs1/rust-ref/slab.rs
use std::ptr;

const OBJ: usize = 64;
const MAX_BYTES: usize = 4096;

#[repr(C)]
struct Free {
    next: *mut Free,
}

#[repr(C)]
pub struct Slab {
    base: *mut u8,
    cap: usize,
    free: *mut Free,
    used: usize,
}

impl Slab {
    // audited primitive 1: build the intrusive free list over raw memory
    unsafe fn build_free_list(mem: *mut u8, cap: usize) -> *mut Free {
        let mut head: *mut Free = ptr::null_mut();
        let mut off = cap;
        while off >= OBJ {
            off -= OBJ;
            let slot = mem.add(off) as *mut Free;
            unsafe {
                (*slot).next = head;                     // deref-write
            }
            head = slot;
        }
        head
    }

    pub fn new(mem: *mut u8, cap: usize) -> Result<Slab, ()> {
        if cap % OBJ != 0 || cap > MAX_BYTES {
            return Err(());
        }
        let free = unsafe { Self::build_free_list(mem, cap) };
        Ok(Slab { base: mem, cap, free, used: 0 })
    }

    pub fn alloc(&mut self) -> Option<*mut u8> {
        let head = self.free;
        if head.is_null() {
            return None;
        }
        unsafe {
            self.free = (*head).next;                    // audited primitive 2
        }
        self.used += 1;
        Some(head as *mut u8)
    }

    pub fn free(&mut self, p: *mut u8) -> Result<(), ()> {
        if p.is_null() {
            return Err(());
        }
        unsafe {
            let f = p as *mut Free;
            (*f).next = self.free;                       // audited primitive 3
            self.free = f;
        }
        self.used -= 1;
        Ok(())
    }
}
