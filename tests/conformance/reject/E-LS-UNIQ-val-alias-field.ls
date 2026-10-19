// EXPECT: E-LS-UNIQ
// M2 counterexample: a `val` handle copied into an aggregate field, then
// `recover { v }` consumes only the variable and leaves `s.f` alive.
// Static replay (semantics.md §2.3.4, t4-proof.md §3.5.3):
//   H(v)={b1}; Construct/Let: H(s)={b1};
//   ConsumeResult clears H(v) but b1 stays in Λ because Holders(b1)={s};
//   Aliases*(Σ_c,x)={(s,b1)} ≠ ∅  ⇒  E-LS-UNIQ.
struct S { f: val[Int] }

fn bad() {
    let mut x: Int = 1;
    let v: val[Int] = freeze x;
    let mut s: S = S { f: v };
    recover { v };
    x = 2;
    let y = s.f;
}
