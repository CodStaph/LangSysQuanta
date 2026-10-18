#[bitfield]
struct Ctrl { enable: 1, mode: 3, irq: 1, _: 3 }

comptime fn ring_capacity() -> USize { 4096 }

const CAP: USize = comptime ring_capacity();
