// Dossier B / B-7 — AI-generated bounded-recursion walker.
// Generated in a single pass from dossiers/recursion/README.md (no edits),
// accepted by tools/checker-spike with 0 diagnostics
// (`#[recursion(bound = 8)]` fits the 8 KiB static stack budget).

struct Node { first_child: Option[USize], next_sibling: Option[USize] }
struct Stats { visited: USize, max_depth: USize }

#[recursion(bound = 8)]
fn walk_ai_rec(nodes: val[Slice[Node]], idx: USize, depth: USize, out: ref[Stats])
    -> Result[Unit, Error]
    requires idx < nodes.len && depth < 8
{
    out.visited += 1;

    let mut c = nodes[idx].first_child;
    while c.is_some() {
        let ci = c.unwrap();
        walk_ai_rec(nodes, ci, depth + 1, out)?;
        c = nodes[ci].next_sibling;
    }

    Ok(())
}
