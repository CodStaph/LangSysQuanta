// EXPECT: E-LS-MOVE
// `a` is moved into `b`; the later `let c = a;` uses the moved value.
// Spike scope: whole-variable moves of box/iso values, not field moves.
fn bad_move() {
    let a: box[Int] = alloc(1);
    let b = move a;
    let c = a;
}
