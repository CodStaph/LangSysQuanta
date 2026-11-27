// EXPECT-RUSTC: E0277
// Rust counterpart of E-LS-IRQ-r6-lock-rank.
// Rust has no static lock-rank checking; the closest statically-rejected
// neighbour is a shared lock handle whose type is not Send (Rc<Mutex<_>>),
// i.e. the aliasing condition on guarded shared state that the checker
// refuses regardless of acquire order.
use std::rc::Rc;
use std::sync::Mutex;

struct State { value: u64 }

fn r6_lock_rank(a: Rc<Mutex<State>>, b: Rc<Mutex<State>>) {
    let ga = a.lock().unwrap();
    let gb = b.lock().unwrap();
    let h = std::thread::spawn(move || gb.value + ga.value);
    let _ = h.join();
}
