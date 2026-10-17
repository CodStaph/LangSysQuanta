// Dossier B / accept_rec — bounded recursion escape hatch.
// Target: 00 §6.7, 03 §4.1, D31. Status: draft (conditional on Q3).

#[recursion(bound = 8)]
fn walk_rec(nodes: val[Slice[Node]], idx: USize, depth: USize, out: ref[WalkStats])
    -> Result[Unit, Error]
    requires idx < nodes.len && depth < 8
{
    out.visited += 1;
    let mut c = nodes[idx].first_child;
    while c.is_some() {
        let ci = c.unwrap();
        walk_rec(nodes, ci, depth + 1, out)?;
        c = nodes[ci].next_sibling;
    }
    Ok(())
}
