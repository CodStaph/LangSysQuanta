// M1d-1a: stage1 control flow, write and expression arguments.
fn add(a: Int, b: Int) -> Int {
    return a + b;
}

fn main() -> Int {
    let i = 0;
    let s = 0;
    while i < 5 {
        i = i + 1;
        if i == 3 {
            continue;
        }
        if i == 5 {
            break;
        }
        s = add(s, i * 2);
    }
    write("ctl ok\n");
    if s == 99 {
        return 1;
    } else if s == 14 {
        return s;
    } else {
        return 2;
    }
}
