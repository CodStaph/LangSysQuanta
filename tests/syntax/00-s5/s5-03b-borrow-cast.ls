// Syntax corpus for the v2.2 productions `borrow_expr`, `freeze_expr` and `cast`.
// Not a verbatim 00 §5 block: added together with those productions so the
// grammar change is covered by the syntax-freeze gate.
// Semantic expectations (not checked here):
//   - borrow_ok / borrow_nested: accepted (R2, S6/S7)
//   - freeze_ok: accepted (R3/S8)
//   - bad_escape: rejected with E-LS-REGION-ESCAPE (R4)

fn borrow_ok() {
    let mut x = 1;
    borrow mut x as r {
        r += 1;
    }
}

fn borrow_nested() eff(Alloc, Write) {
    region R {
        let a: Alloc[Region] = R.allocator();
        let p: box[Array[Int, 4]] = a.alloc(Array.zeroed());
        borrow mut p[0] as r {
            r += 1;
        }
    }
}

fn freeze_ok() {
    let mut x = 1;
    let v: val[Int] = freeze x;
    let w = v;
}

fn cast_ok(n: USize, h: USize) -> USize {
    let i = n as USize;
    let j = (h + 1) as USize;
    let k = -1 as Int;
    i + j + k
}

fn bad_escape() -> ref[Int] {
    let mut x = 1;
    borrow mut x as r { return r; }   // E-LS-REGION-ESCAPE
}
