// B-LS M1c-0c-2: enum payload + match binding.
enum Option { None, Some(Int) }

fn main() -> Int {
    let x = Option.Some(42);
    match x {
        Option.Some(v) => { write("some\n"); return v; },
        Option.None => { return 0; }
    }
    return -1;
}
