// EXPECT-RUSTC: E0277
// Rust counterpart of E-LS-RACE-r6-shared-plain-read:
// even a plain read of a non-thread-safe shared handle crossing a spawn
// is statically rejected (Rc<u64> is not Send).
use std::rc::Rc;
use std::thread;

fn r6_shared_plain_read() -> u64 {
    let c = Rc::new(1u64);
    let h = thread::spawn(move || *c);
    h.join().unwrap()
}
