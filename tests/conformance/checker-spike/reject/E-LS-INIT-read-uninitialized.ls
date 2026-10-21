// EXPECT: E-LS-INIT
// `p` is declared without an initializer; reading `p.x` is a use before init.
struct Point { x: Int, y: Int }

fn bad_init() {
    let p: Point;
    let q = p.x;
}
