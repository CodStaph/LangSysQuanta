// EXPECT-RUSTC: E0277
// Rust counterpart of E-LS-RACE-r6-shared-plain-write:
// a plain write through a non-thread-safe shared handle (Cell is !Sync)
// is statically rejected when the reference crosses a spawn.
use std::cell::Cell;
use std::thread;

fn r6_shared_plain_write(c: &Cell<u64>) {
    let h = thread::spawn(move || {
        c.set(1);
    });
    let _ = h.join();
}
