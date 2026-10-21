fn main() -> Int {
    let x = 0;
    region R {
        let y = 1;
        x = x + y;
        region S {
            let z = 2;
            x = x + z;
        }
    }
    return x;
}
