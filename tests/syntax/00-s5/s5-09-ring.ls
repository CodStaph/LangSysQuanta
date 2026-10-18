#[repr(C)]
struct Ring {
    buf: box[Slice[U8]],
    head: USize,
    count: USize,
}

fn ring_new(a: Alloc[Heap], cap: USize) -> Result[iso[Ring], Error] eff(Alloc)
    // agent：句柄由 prelude 提供；kernel：额外需要 cap: Cap[Alloc]
{
    if cap == 0 { return Err(Error.InvalidCap); }
    let buf: box[Slice[U8]] = a.alloc_slice(cap)?;   // T 由标注推断（无 turbofish）
    Ok(iso Ring { buf, head: 0, count: 0 })
}

fn ring_push(r: ref[Ring], v: U8) -> Result[Unit, Error]
    requires r.count <= r.buf.len
    ensures  Ok(_) => r.count == old(r.count) + 1
    ensures  Err(_) => r.count == old(r.count)
eff(Write)
{
    if r.count == r.buf.len { return Err(Error.Full); }
    let i = (r.head + r.count) % r.buf.len;
    r.buf[i] = v;                       // 索引默认检查；i < len 由契约+取模保证
    r.count += 1;
    Ok(())
}

fn ring_pop(r: ref[Ring]) -> Result[U8, Error]
    requires r.count <= r.buf.len
    ensures  Ok(_) => r.count == old(r.count) - 1
eff(Write)
{
    if r.count == 0 { return Err(Error.Empty); }
    let v = r.buf[r.head];
    r.head = (r.head + 1) % r.buf.len;
    r.count -= 1;
    Ok(v)
}
