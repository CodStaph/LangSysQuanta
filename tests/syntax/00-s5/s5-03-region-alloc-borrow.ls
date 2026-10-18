fn scoped() eff(Alloc) {
    region R {
        let a: Alloc[Region] = R.allocator();
        let tmp: box[Array[U8, 256]] = a.alloc(Array.zeroed());
        process(tmp.slice());          // 传入 val[Slice[U8]]
    } // R 结束，tmp 随之释放
}

fn heap_build() -> Result[iso[Buffer], Error] eff(Alloc) {
    let a: Alloc[Heap] = heap_allocator();
    let data: box[Slice[U8]] = a.alloc_slice(64)?;   // T 由标注推断（无 turbofish）
    Ok(iso Buffer { data, len: 0 })
}
