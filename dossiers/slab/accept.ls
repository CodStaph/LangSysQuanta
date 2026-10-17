// Dossier C / accept — slab allocator, intrusive list, refcount/RCU, C driver port.
// Target: 00 §4.3/§4.6, 03 §4.2, ADR-18, D32.
// Status: draft; checker spike may be limited to signatures initially.

#[cap(Unsafe)]
module kernel.slab;

profile kernel;

const OBJ: USize = 64;
const MAX_BYTES: USize = 4096;

struct Free { next: rawptr[Free] }

#[repr(C)]
struct Slab {
    base: rawptr[U8],
    cap: USize,
    free: rawptr[Free],
    used: USize,
}

fn init(s: ref[Slab], mem: rawptr[U8], cap: USize) -> Result[Unit, Error]
    requires is_aligned(mem, OBJ) && cap % OBJ == 0 && cap <= MAX_BYTES
    ensures  Ok(_) => s.used == 0
{
    unsafe {
        s.base = mem;
        s.cap = cap;
        s.used = 0;
        s.free = build_free_list(mem, cap);   // audited primitive 1
    }
    Ok(())
}

fn alloc(s: ref[Slab]) -> Option[rawptr[U8]]
    requires s.used <= s.cap / OBJ
    ensures  Option.Some(_) => s.used == old(s.used) + 1
{
    let head = s.free;
    if head.is_null() { return Option.None; }
    unsafe { s.free = (*head).next; }          // audited primitive 2 (ptr_read)
    s.used += 1;
    Option.Some(head as rawptr[U8])
}

fn free(s: ref[Slab], p: rawptr[U8]) -> Result[Unit, Error]
    requires contains(s, p) && is_aligned(p, OBJ) && !is_free(s, p)
    ensures  Ok(_) => s.used == old(s.used) - 1
{
    if !contains(s, p) { return Err(Error.OutOfRange); }
    unsafe {
        let f = p as rawptr[Free];
        (*f).next = s.free;                     // audited primitive 3 (ptr_write)
        s.free = f;
    }
    s.used -= 1;
    Ok(())
}

// ---- intrusive list ----

struct Link { next: Option[rawptr[Link]], prev: Option[rawptr[Link]] }
struct List { head: Option[rawptr[Link]], len: USize }

fn push(l: ref[List], n: rawptr[Link]) -> Result[Unit, Error]
    requires is_valid(n) && is_unlinked(n)
    ensures  is_linked(n) && l.len == old(l.len) + 1
{
    unsafe {
        (*n).prev = Option.None;
        (*n).next = l.head;
        match l.head {
            Option.Some(h) => (*h).prev = Option.Some(n),
            Option.None => {}
        }
        l.head = Option.Some(n);
    }
    l.len += 1;
    Ok(())
}

// ---- refcount / RCU ----

struct Ref[T] { ptr: rawptr[T], count: shared[Atomic[USize]] }

fn ref_new[T](a: Alloc[Heap], v: T) -> Result[Ref[T], Error] eff(Alloc) { ... }

fn ref_clone[T](r: ref[Ref[T]]) -> Ref[T] eff(Atomic)
    requires r.count.load(Order.Relaxed) < USize.MAX
{
    r.count.fetch_add(1, Order.Relaxed);
    Ref { ptr: r.ptr, count: r.count.handle() }
}

fn ref_put[T](r: Ref[T]) eff(Atomic)
    ensures r.count.load(Order.Acquire) == 0
{
    if r.count.fetch_sub(1, Order.AcqRel) == 1 {
        unsafe { drop_in_place(r.ptr); }
    }
}

struct Rcu[T] { slot: shared[Atomic[rawptr[T]]] }

fn rcu_read[T](r: ref[Rcu[T]]) -> RcuGuard[T] eff(Atomic) { ... }
fn rcu_publish[T](r: ref[Rcu[T]], v: iso[T]) eff(Atomic) { ... }
fn rcu_synchronize[T](r: ref[Rcu[T]]) eff(Block) { ... }

// ---- C driver port: I2C sensor (register + IRQ + DMA) ----

#[register(addr = 0x0F, access = ReadOnly)]
struct WhoAmI { id: U8 }

#[register(addr = 0x20)]
struct Ctrl1 { odr: U8, bdu: Bool, zen: Bool, yen: Bool, xen: Bool }

fn probe(dev: ref[I2cDev]) -> Result[Unit, Error] eff(Io) {
    let who = dev.read_reg(0x0F)?;
    if who != 0x33 { return Err(Error.WrongDevice); }
    dev.write_reg(0x20, Ctrl1 { odr: 0x2, bdu: true, zen: true, yen: true, xen: true })?;
    Ok(())
}

#[irq(level = 1, threaded = true)]
fn on_irq(s: shared[SensorState], r: ref[Mmio[IntRegs]]) -> Result[Unit, Error]
    eff(Irq, Hw)
{
    let st = r.status.read();
    s.pending.fetch_or(st, Order.Relaxed);
    Ok(())
}

fn read_sample(s: ref[SensorState], dev: ref[I2cDev]) -> Result[Sample, Error] eff(Io) {
    let buf = dev.read_burst(0x28, 6)?;
    Ok(Sample {
        x: i16_le(buf[0], buf[1]),
        y: i16_le(buf[2], buf[3]),
        z: i16_le(buf[4], buf[5]),
    })
}

fn run(dev: ref[I2cDev]) -> Result[Unit, Error] eff(Io, Alloc) {
    probe(dev)?;
    let dma = dma_map(dev.rx_buffer())?;          // DmaToken
    defer dma.wait();                             // released on every exit path
    loop { read_sample(&mut state, dev)?; }
}
