// Stage 2: infer Option[Str] from a Str payload.
fn main() -> Int {
    let s: Str = "ok";
    let o = Option.Some(s);
    match o {
        Option.Some(v) => { return v.len; },
        Option.None => { return 9; }
    }
    return 0;
}
