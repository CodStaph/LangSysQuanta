// Dossier B / accept_stack — device tree walk without recursion.
// Target: 00 §6.7, 03 §4.1. Status: draft.

#[repr(C)]
struct Node {
    name: val[Str],
    first_child: Option[USize],
    next_sibling: Option[USize],
    reg: Array[U32, 2],
}

struct WalkStats { visited: USize, max_depth: USize }

const DT_MAX_DEPTH: USize = 64;

fn walk(nodes: val[Slice[Node]], root: USize, out: ref[WalkStats])
    -> Result[Unit, Error]
    requires root < nodes.len
    ensures  Ok(_) => out.visited >= 1
{
    let mut stack: Array[USize, DT_MAX_DEPTH] = Array.zeroed();
    let mut sp: USize = 0;

    stack[sp] = root;
    sp += 1;

    while sp > 0 {
        sp -= 1;
        let idx = stack[sp];
        out.visited += 1;

        let mut c = nodes[idx].first_child;
        while c.is_some() {
            let ci = c.unwrap();
            if ci >= nodes.len { return Err(Error.BadTree); }
            if sp == DT_MAX_DEPTH { return Err(Error.TooDeep); }
            stack[sp] = ci;
            sp += 1;
            c = nodes[ci].next_sibling;
        }
    }
    Ok(())
}
