// Q9 positive: first assignment is initialization, not mutation.
// `mut` only controls writes after initialization.
fn first_assignment_is_init() {
    let x: Int;
    x = 1;
    let y = x;

    let mut z: Int;
    z = 2;          // first assignment (init)
    z = 3;          // allowed: z is mut
    let w = z;
}
