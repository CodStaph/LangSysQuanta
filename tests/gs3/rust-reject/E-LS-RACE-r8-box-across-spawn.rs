// EXPECT-RUSTC: E0521
// Rust counterpart of E-LS-RACE-r8-box-across-spawn:
// a region-local value crossing a domain boundary: the spawned closure
// carries a borrow that does not satisfy the required lifetime
// (rustc: E0521, borrowed data escapes).
use std::thread;

struct Config { depth: u32 }

fn use_cfg(c: &Config) -> u32 { c.depth }

fn r8_box_across_spawn(c: &Config) -> u32 {
    let h = thread::spawn(move || use_cfg(c));
    h.join().unwrap()
}
