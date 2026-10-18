#[repr(C, align(16))]
struct Regs { ctrl: U32, status: U32 }

extern "C" fn memcpy(dst: rawptr[U8], src: rawptr[U8], n: USize);

// MMIO 访问是安全 API（cap 控制），不需要 unsafe
fn mmio_snapshot(r: ref[Mmio[Regs]]) -> (U32, U32) eff(Hw) {
    (r.ctrl.read(), r.status.read())   // 字段投影保留 Mmio 地址空间
}

fn halt() eff(Asm) {
    unsafe(Cap[Unsafe]) { asm("wfi"); }
}

// 裸机代码生成指令（封闭属性集，D34）
#[no_mangle]
#[link_section = ".vectors"]
static VECTORS: val[Array[Handler, 4]] = Array.zeroed();  // 启动代码填充

#[naked]
#[no_mangle]
fn reset_handler() { asm("b _start"); }

#[repr(transparent)]
struct Handle(U32);                     // FFI newtype

union Word { u: U32, f: F32 }

fn read_cntpct() -> U64 eff(Asm) {
    let mut t: U64 = 0;
    unsafe(Cap[Unsafe]) {
        asm("mrs {}, cntpct_el0", out("x0") => t);   // 操作数/命名寄存器
    }
    t
}
