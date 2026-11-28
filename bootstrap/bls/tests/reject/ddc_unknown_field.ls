// S3-4 DDC negative anchor (results/S3-4-ddc.md section 6, family A):
// the `struct: unknown field` diagnostic (rc=4) that the SELF-built
// compiler wrongly emits on VALID struct programs must fire ONLY on
// genuinely unknown fields. Shape mirrors ddc-probe/probe-s2-struct-
// write.ls with the written/read field absent from Point.
struct Point { x_coord: Int, y_coord: Int }

fn main() -> Int {
    let point: Point;
    point.z_coord = 3;
    return point.z_coord;
}
