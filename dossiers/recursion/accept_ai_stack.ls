// Dossier B / B-7 — AI-generated explicit-stack walker.
// Generated in a single pass from dossiers/recursion/README.md (no edits),
// accepted by tools/checker-spike with 0 diagnostics.

struct Node { first_child: Option[USize], next_sibling: Option[USize] }
struct Stats { visited: USize, max_depth: USize }

const MAX_DEPTH: USize = 32;

fn walk_ai(nodes: val[Slice[Node]], root: USize, out: ref[Stats])
    -> Result[Unit, Error]
    requires root < nodes.len
    ensures  Ok(_) => out.visited >= 1
{
    let mut stack: Array[USize, MAX_DEPTH] = Array.zeroed();
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
            if sp == MAX_DEPTH { return Err(Error.TooDeep); }
            stack[sp] = ci;
            sp += 1;
            c = nodes[ci].next_sibling;
        }
    }
    Ok(())
}
