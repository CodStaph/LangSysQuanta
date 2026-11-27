// EXPECT-RUSTC: E0277
// Rust counterpart of E-LS-EFFECT-rawptr-in-public-field:
// a public field carrying a raw pointer infects the whole struct with
// !Send; sharing it across a spawn is statically rejected even though the
// function signature itself hides the pointer.
struct HiddenPtr { p: *mut u8 }

fn share(h: HiddenPtr) {
    let handle = std::thread::spawn(move || {
        let hidden = h;
        let _ = &hidden;
    });
    let _ = handle.join();
}
