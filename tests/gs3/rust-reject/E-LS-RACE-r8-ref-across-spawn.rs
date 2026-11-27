// EXPECT-RUSTC: E0521
// Rust counterpart of E-LS-RACE-r8-ref-across-spawn:
// a reference must not cross a domain boundary; the spawned closure
// captures the reference beyond its allowed lifetime (rustc: E0521).
use std::thread;

struct Config { depth: u32 }

fn r8_ref_across_spawn(r: &Config) -> u32 {
    let h = thread::spawn(move || r.depth);
    h.join().unwrap()
}
