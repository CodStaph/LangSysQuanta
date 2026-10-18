#[cap(Unsafe, Mmio[0x4000_0000..0x4000_0fff])]
#[bounds(off, requires = "idx < len")]
#[overflow(wrapping)]
module drivers.uart;
profile kernel;
