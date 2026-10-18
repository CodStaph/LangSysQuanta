struct Node { next: Option[box[Node]], value: Int }
enum Irq { Timer, Uart(U8), None }
enum Option[T] { Some(T), None }
enum Result[T, E] { Ok(T), Err(E) }

fn add(a: Int, b: Int) -> Int { a + b }
