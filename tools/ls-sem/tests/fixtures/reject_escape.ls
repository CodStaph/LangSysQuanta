fn escape() -> Buffer[Int] eff(Alloc) {
    region R {
        let b: Buffer[Int] = Buffer.new[Int](2, R);
        return b;
    }
}
