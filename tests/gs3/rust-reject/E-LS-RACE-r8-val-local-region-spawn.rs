// EXPECT-RUSTC: E0373
// Rust counterpart of E-LS-RACE-r8-val-local-region-spawn:
// the value is bound to a local scope; the spawned closure borrows it,
// violating the 'static bound the spawn requires.
use std::thread;

struct Config { depth: u32 }

fn use_cfg(c: &Config) -> u32 { c.depth }

fn r8_val_local_region() -> u32 {
    let c = Config { depth: 4 };
    let h = thread::spawn(|| use_cfg(&c));
    h.join().unwrap()
}
