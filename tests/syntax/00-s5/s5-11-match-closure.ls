fn classify(x: Irq) -> U8 {
    match x {
        Irq.Timer    => 0,
        Irq.Uart(ch) => ch,
        Irq.None     => 0xFF,
    }
}

fn dispatch(r: ref[Read], buf: ref[Slice[U8]]) -> Result[USize, Error] eff(Read) {
    r.read(buf)                     // 动态分派：`ref[Trait]` 是 trait 对象视图
}

fn with_closure() {
    let n = 3;
    let f = |x: Int| x + n;         // 捕获 n：按 val（只读）捕获
    for i in 0..10 { f(i); }
}
