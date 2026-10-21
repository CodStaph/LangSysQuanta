// Checked subset: Buffer[T] + regions, multi-parameter generics,
// val/ref + effects/contracts, fallible allocation with arena reclamation.

struct Pair[A, B] { first: A, second: B }

fn pair[A, B](a: A, b: B) -> Pair[A, B] {
    return Pair.new[A, B](a, b);
}

fn larger[T: Ord](a: T, b: T) -> T {
    if a > b { return a; }
    return b;
}

fn make() -> Result[Buffer[Int], AllocError] eff(Alloc)
    requires 4 > 0
    ensures 1 > 0
{
    region Scratch {
        let scratch: Buffer[Int] = Buffer.try_new[Int](4, Scratch)?;
        scratch.push(1);
    }
    let heap_buf: Buffer[Int] = Buffer.new[Int](2, heap);
    return Result.Ok[Buffer[Int], AllocError](heap_buf);
}

fn main() -> Unit eff(Alloc) {
    let p: Pair[Int, Str] = pair(1, "x");
    let n: Int = larger[Int](p.first, 2);
    region R {
        let b: Buffer[Pair[Int, Str]] = Buffer.new[Pair[Int, Str]](1, R);
        b.push(p);
    }
    return;
}
