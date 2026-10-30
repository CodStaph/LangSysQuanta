struct Point { x: Int, y: Int }
impl Eq for Point {
    fn eq(ref a: Point, ref b: Point) -> Int { return 1; }
}
impl Eq for Point {
    fn eq2(ref a: Point, ref b: Point) -> Int { return 1; }
}
fn main() -> Int { return 0; }
