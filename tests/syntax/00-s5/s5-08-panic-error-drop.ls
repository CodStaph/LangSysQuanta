fn open(p: val[Path]) -> Result[File, Error] eff(Io) {
    let f = fs.open(p)?;               // `?` 传播；Error 是 Copy 的紧凑 enum
    Ok(f)
}

fn kernel_demo() eff(Write) {
    let f = open(p).or_else(Error.NotFound)?;
    defer f.release();                 // 作用域退出消费；错误路径也不泄漏
    // ...
}
