fn main(sys: Cap[Sys]) {
    let q: iso Queue = iso Queue.new();
    let a = spawn producer(move q);
    let q2: iso Queue = join(a);
    let b = spawn consumer(move q2);
    join(b);
}

fn bump(c: shared[Atomic[U64]]) eff(Atomic) {
    c.fetch_add(1, Order.SeqCst);      // shared 是锁语义；原子操作需内层 Atomic
}

#[irq(level = 1)]
fn on_uart(s: shared[UartState], r: Mmio[UartRegs]) -> Result[Unit, Error]
    eff(Irq, Hw)
{
    let st = r.status.read();
    s.rx.push(st)?;                    // ISR 内禁止 Alloc；`push` 无 Alloc 效果
    Ok(())
}
