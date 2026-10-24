// R4.4: region-scoped budget accounting + dynamic Buffer capacity.
fn main() -> Int {
    if region_used() != 0 { return 1; }
    region R {
        let b: Buffer[Int] = Buffer.new[Int](2, R);        // 32 + 16 = 48
        if region_used() != 48 { return 2; }
        if arena_used() != 48 { return 3; }
        region S {
            let c: Buffer[Int] = Buffer.new[Int](2, S);    // 48
            if region_used() != 48 { return 4; }
            if arena_used() != 96 { return 5; }
        }
        if region_used() != 48 { return 6; }
        if arena_used() != 48 { return 7; }
    }
    if region_used() != 0 { return 8; }
    if arena_used() != 0 { return 9; }
    if arena_stat(3) != 2 { return 10; }   // two region exits

    // Dynamic capacity: the cap comes from a runtime value.
    let cap = 3;
    let d: Buffer[Int] = Buffer.new[Int](cap, heap);
    if d.cap != 3 { return 11; }
    d.push(1);
    d.push(2);
    d.push(3);
    if d.len != 3 { return 12; }
    if d.push(4) != 0 - 1 { return 13; }
    if arena_used() != 32 + 24 { return 14; }
    if d.release() != 0 { return 15; }
    if arena_used() != 0 { return 16; }
    if arena_stat(3) != 3 { return 17; }
    return 7;
}
