; genop_str.asm — flat binary helper for generic Str/Slice operations.
; ABI:
;   rdi = box A, rsi = box B, rdx = op
;   rcx = result box (Str concat) or output slice box (Slice into)
;   r8  = address of heap_ptr, r9 = address of heap_end
bits 64
cpu x86-64

%macro DECODE 3
    movzx eax, byte [%1]
    inc %1
    cmp eax, 0x80
    jb %%done
    cmp eax, 0xE0
    jb %%two
    cmp eax, 0xF0
    jb %%three
    and eax, 0x07
    shl eax, 6
    movzx ecx, byte [%1]
    inc %1
    and ecx, 0x3F
    or eax, ecx
    shl eax, 6
    movzx ecx, byte [%1]
    inc %1
    and ecx, 0x3F
    or eax, ecx
    shl eax, 6
    movzx ecx, byte [%1]
    inc %1
    and ecx, 0x3F
    or eax, ecx
    jmp %%done
%%two:
    and eax, 0x1F
    shl eax, 6
    movzx ecx, byte [%1]
    inc %1
    and ecx, 0x3F
    or eax, ecx
    jmp %%done
%%three:
    and eax, 0x0F
    shl eax, 6
    movzx ecx, byte [%1]
    inc %1
    and ecx, 0x3F
    or eax, ecx
    shl eax, 6
    movzx ecx, byte [%1]
    inc %1
    and ecx, 0x3F
    or eax, ecx
%%done:
    mov %3, eax
%endmacro

genop_str:
    mov eax, [rdi]
    cmp eax, [rsi]
    jne trap
    cmp eax, 3
    je str_entry
    cmp eax, 4
    je slice_entry
    cmp eax, 5
    je slice_entry
    jmp trap

str_entry:
    cmp edx, 1
    je concat
    cmp edx, 6
    jb trap
    cmp edx, 11
    ja trap
    jmp compare

concat:
    mov r10, [rdi+8]
    mov r11, [rdi+16]
    mov r14, [rdi+24]
    mov r12, [rsi+8]
    mov r13, [rsi+16]
    mov rax, [rsi+24]
    add r14, rax
    mov rbx, r11
    add rbx, r13
    ; R4.2: all arena allocations are 8-byte aligned (rbx keeps the real byte
    ; length for the Str box; rax is the aligned bump size).
    mov rax, rbx
    add rax, 7
    and rax, -8
    mov r15, [r8]
    mov rdx, r15
    add rdx, rax
    cmp rdx, [r9]
    ja .oom
    mov [r8], rdx
    ; r8 = &current, r9 = &end; [end+8]=high_water, +16=allocs, +24=rejects
    mov rax, rdx
    sub rax, [r8-8]
    cmp rax, [r9+8]
    jbe .nohw
    mov [r9+8], rax
.nohw:
    mov rax, [r9+16]
    add rax, 1
    mov [r9+16], rax
    mov rdi, r15
    mov rsi, r10
    mov rdx, r11
.copyA:
    test rdx, rdx
    jz .copyB
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jmp .copyA
.copyB:
    mov rsi, r12
    mov rdx, r13
.copyB2:
    test rdx, rdx
    jz .store
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jmp .copyB2
.store:
    mov dword [rcx], 3
    mov [rcx+8], r15
    mov [rcx+16], rbx
    mov [rcx+24], r14
    mov rax, rcx
    ret
.oom:
    ; R4.3/R4.2: arena exhausted -> Err box (tag 9, empty payload), current
    ; unchanged, and the arena rejection counter is bumped.
    mov rax, [r9+24]
    add rax, 1
    mov [r9+24], rax
    mov dword [rcx], 9
    xor eax, eax
    mov [rcx+8], rax
    mov [rcx+16], rax
    mov [rcx+24], rax
    mov rax, rcx
    ret

compare:
    mov r8, [rdi+8]
    mov rax, [rdi+16]
    add rax, r8
    mov r9, rax
    mov r10, [rsi+8]
    mov rax, [rsi+16]
    add rax, r10
    mov r11, rax
.cloop:
    cmp r8, r9
    jae .aend
    cmp r10, r11
    jae .bend
    DECODE r8, r9, r12d
    DECODE r10, r11, r13d
    cmp r12d, r13d
    jne .diff
    jmp .cloop
.aend:
    cmp r10, r11
    jb .less
    jmp .equal
.bend:
    jmp .greater
.diff:
    jl .less
    jmp .greater
.less:
    mov r14d, -1
    jmp cmp_map
.greater:
    mov r14d, 1
    jmp cmp_map
.equal:
    xor r14d, r14d
    jmp cmp_map

slice_entry:
    cmp edx, 31
    je slice_concat_into
    cmp edx, 32
    je slice_append_into
    cmp edx, 6
    jb trap
    cmp edx, 11
    ja trap
    jmp slice_compare

slice_concat_into:
    mov r13d, [rdi]
    cmp r13d, [rsi]
    jne trap
    cmp r13d, [rcx]
    jne trap
    mov r10, [rdi+8]
    mov r11, [rdi+16]
    mov r12, [rsi+8]
    mov r14, [rsi+16]
    mov r15, [rcx+8]
    mov rbx, [rcx+16]
    mov rax, r11
    add rax, r14
    cmp rax, rbx
    ja .capfail
    mov rdi, r15
    mov rsi, r10
    mov rdx, r11
    cmp r13d, 4
    je .copyA
    imul rdx, 8
.copyA:
    test rdx, rdx
    jz .copyB
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jmp .copyA
.copyB:
    mov rsi, r12
    mov rdx, r14
    cmp r13d, 4
    je .copyB2
    imul rdx, 8
.copyB2:
    test rdx, rdx
    jz .done
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jmp .copyB2
.done:
    mov rax, r15
    mov rdx, r11
    add rdx, r14
    ret
.capfail:
    ; R4.3: destination too small -> Err box (tag 9), nothing written.
    mov dword [rcx], 9
    mov rax, r15
    mov rdx, rbx
    ret

slice_append_into:
    mov r13d, [rdi]
    cmp r13d, [rcx]
    jne trap
    mov r10, [rdi+8]
    mov r11, [rdi+16]
    mov r12, [rsi+8]
    mov r15, [rcx+8]
    mov rbx, [rcx+16]
    mov rax, r11
    inc rax
    cmp rax, rbx
    ja .capfail
    mov rdi, r15
    mov rsi, r10
    mov rdx, r11
    cmp r13d, 4
    je .copyA
    imul rdx, 8
.copyA:
    test rdx, rdx
    jz .elem
    mov al, [rsi]
    mov [rdi], al
    inc rsi
    inc rdi
    dec rdx
    jmp .copyA
.elem:
    cmp r13d, 4
    jne .elem8
    mov al, r12b
    mov [rdi], al
    jmp .done
.elem8:
    mov rax, r12
    mov [rdi], rax
.done:
    mov rax, r15
    mov rdx, r11
    inc rdx
    ret
.capfail:
    ; R4.3: destination too small -> Err box (tag 9), nothing written.
    mov dword [rcx], 9
    mov rax, r15
    mov rdx, rbx
    ret

slice_compare:
    mov r8, [rdi+8]
    mov r10, [rsi+8]
    mov r11, [rdi+16]
    mov r12, [rsi+16]
    mov r13, r11
    cmp r13, r12
    cmova r13, r12
    xor ebx, ebx
    mov eax, [rdi]
.sloop:
    cmp rbx, r13
    jae .tails
    cmp eax, 4
    je .byte
    mov r14, [r8+rbx*8]
    mov r15, [r10+rbx*8]
    cmp r14, r15
    jne .diff64
    inc rbx
    jmp .sloop
.byte:
    movzx r14d, byte [r8+rbx]
    movzx r15d, byte [r10+rbx]
    cmp r14d, r15d
    jne .diff32
    inc rbx
    jmp .sloop
.tails:
    cmp r11, r12
    jb .less
    ja .greater
    jmp .equal
.diff64:
    jl .less
    jmp .greater
.diff32:
    jb .less
    jmp .greater
.less:
    mov r14d, -1
    jmp cmp_map
.greater:
    mov r14d, 1
    jmp cmp_map
.equal:
    xor r14d, r14d
    jmp cmp_map

cmp_map:
    cmp edx, 6
    je .eq
    cmp edx, 7
    je .ne
    cmp edx, 8
    je .lt
    cmp edx, 9
    je .le
    cmp edx, 10
    je .gt
    cmp r14d, 0
    setge al
    jmp .ret
.eq:
    cmp r14d, 0
    sete al
    jmp .ret
.ne:
    cmp r14d, 0
    setne al
    jmp .ret
.lt:
    cmp r14d, 0
    setl al
    jmp .ret
.le:
    cmp r14d, 0
    setle al
    jmp .ret
.gt:
    cmp r14d, 0
    setg al
.ret:
    movzx eax, al
    ret

trap:
    mov eax, 60
    mov edi, 70
    syscall

; ---------------------------------------------------------------------------
; R4.6: general free list (hole reuse + coalescing) for arena blocks.
;
; Table layout (in the generated program's data segment):
;   [table+0]  = entry count (qword)
;   [table+8 + i*16] = { off, size }   (8-byte aligned, sorted by off)
; Offsets are relative to the arena base; sizes are byte counts.
;
; ABI (called from generated code through the vector at the end of this binary):
;   buf_take(rdi=&table, rsi=size)            -> rax = off or -1
;   buf_free(rdi=&table, rsi=off, rdx=size)   -> rax = 0 or -1
;   buf_purge(rdi=&table, rsi=limit)          -> rax = 0
;   buf_compact(rdi=&table)                   -> rax = 0
; ---------------------------------------------------------------------------

buf_take:
    mov r8, [rdi]
    xor r9d, r9d
.bt_loop:
    cmp r9, r8
    jae .bt_fail
    mov r10, r9
    shl r10, 4
    lea r11, [rdi+8]
    add r11, r10
    mov rax, [r11+8]
    cmp rax, rsi
    jb .bt_next
    mov rdx, [r11]
    mov rcx, [r11+8]
    sub rcx, rsi
    cmp rcx, 8
    jb .bt_whole
    add [r11], rsi
    mov [r11+8], rcx
    mov rax, rdx
    ret
.bt_next:
    inc r9
    jmp .bt_loop
.bt_whole:
    mov r10, r9
.bt_shift:
    mov rax, r10
    inc rax
    cmp rax, r8
    jae .bt_shrunk
    mov rbx, r10
    shl rbx, 4
    lea r11, [rdi+8]
    add r11, rbx
    mov rbx, rax
    shl rbx, 4
    lea rcx, [rdi+8]
    add rcx, rbx
    mov rbx, [rcx]
    mov [r11], rbx
    mov rbx, [rcx+8]
    mov [r11+8], rbx
    inc r10
    jmp .bt_shift
.bt_shrunk:
    dec r8
    mov [rdi], r8
    mov rax, rdx
    ret
.bt_fail:
    mov rax, -1
    ret

buf_free:
    add rdx, 7
    and rdx, -8
    cmp rdx, 8
    jb .bf_fail
    mov r8, [rdi]
    cmp r8, 64
    jae .bf_fail
    xor r9d, r9d
.bf_find:
    cmp r9, r8
    jae .bf_ins
    mov r10, r9
    shl r10, 4
    lea r11, [rdi+8]
    add r11, r10
    mov rax, [r11]
    cmp rax, rsi
    ja .bf_ins
    inc r9
    jmp .bf_find
.bf_ins:
    mov r10, r8
.bf_shift:
    cmp r10, r9
    jbe .bf_place
    mov rax, r10
    shl rax, 4
    lea r11, [rdi+8]
    add r11, rax
    mov rax, r10
    dec rax
    shl rax, 4
    lea rcx, [rdi+8]
    add rcx, rax
    mov rbx, [rcx]
    mov [r11], rbx
    mov rbx, [rcx+8]
    mov [r11+8], rbx
    dec r10
    jmp .bf_shift
.bf_place:
    mov rax, r9
    shl rax, 4
    lea r11, [rdi+8]
    add r11, rax
    mov [r11], rsi
    mov [r11+8], rdx
    inc r8
    mov [rdi], r8
    ; coalesce with next
    mov r10, r9
    inc r10
    cmp r10, r8
    jae .bf_prev
    mov rax, r10
    shl rax, 4
    lea rcx, [rdi+8]
    add rcx, rax
    mov rax, rsi
    add rax, rdx
    cmp rax, [rcx]
    jne .bf_prev
    mov rax, [rcx+8]
    add [r11+8], rax
    mov r10, r9
    inc r10
.bf_shift2:
    mov rax, r10
    inc rax
    cmp rax, r8
    jae .bf_shrunk2
    mov rbx, r10
    shl rbx, 4
    lea rcx, [rdi+8]
    add rcx, rbx
    mov rbx, rax
    shl rbx, 4
    lea r11, [rdi+8]
    add r11, rbx
    mov rbx, [r11]
    mov [rcx], rbx
    mov rbx, [r11+8]
    mov [rcx+8], rbx
    inc r10
    jmp .bf_shift2
.bf_shrunk2:
    dec r8
    mov [rdi], r8
.bf_prev:
    test r9, r9
    jz .bf_ok
    mov r10, r9
    dec r10
    mov rax, r10
    shl rax, 4
    lea rcx, [rdi+8]
    add rcx, rax
    mov rax, [rcx]
    add rax, [rcx+8]
    cmp rax, rsi
    jne .bf_ok
    mov rax, r9
    shl rax, 4
    lea r11, [rdi+8]
    add r11, rax
    mov rax, [r11+8]
    add [rcx+8], rax
    mov r10, r9
.bf_shift3:
    mov rax, r10
    inc rax
    cmp rax, r8
    jae .bf_shrunk3
    mov rbx, r10
    shl rbx, 4
    lea rcx, [rdi+8]
    add rcx, rbx
    mov rbx, rax
    shl rbx, 4
    lea r11, [rdi+8]
    add r11, rbx
    mov rbx, [r11]
    mov [rcx], rbx
    mov rbx, [r11+8]
    mov [rcx+8], rbx
    inc r10
    jmp .bf_shift3
.bf_shrunk3:
    dec r8
    mov [rdi], r8
.bf_ok:
    xor eax, eax
    ret
.bf_fail:
    mov rax, -1
    ret

buf_purge:
    mov r8, [rdi]
    xor r9d, r9d
.bp_loop:
    cmp r9, r8
    jae .bp_done
    mov r10, r9
    shl r10, 4
    lea r11, [rdi+8]
    add r11, r10
    mov rax, [r11]
    cmp rax, rsi
    jae .bp_cut
    mov rcx, rax
    add rcx, [r11+8]
    cmp rcx, rsi
    jbe .bp_next
    sub rsi, rax
    cmp rsi, 8
    jb .bp_cut
    mov [r11+8], rsi
    jmp .bp_done
.bp_next:
    inc r9
    jmp .bp_loop
.bp_cut:
    mov [rdi], r9
.bp_done:
    xor eax, eax
    ret

buf_compact:
    mov r8, [rdi]
    mov r9, 1
.bc_loop:
    cmp r9, r8
    jae .bc_done
    mov r10, r9
    dec r10
    shl r10, 4
    lea r11, [rdi+8]
    add r11, r10
    mov rax, [r11]
    add rax, [r11+8]
    mov r10, r9
    shl r10, 4
    lea rcx, [rdi+8]
    add rcx, r10
    cmp rax, [rcx]
    jne .bc_next
    mov rax, [rcx+8]
    add [r11+8], rax
    mov r10, r9
.bc_shift:
    mov rax, r10
    inc rax
    cmp rax, r8
    jae .bc_shrunk
    mov rbx, r10
    shl rbx, 4
    lea rcx, [rdi+8]
    add rcx, rbx
    mov rbx, rax
    shl rbx, 4
    lea r11, [rdi+8]
    add r11, rbx
    mov rbx, [r11]
    mov [rcx], rbx
    mov rbx, [r11+8]
    mov [rcx+8], rbx
    inc r10
    jmp .bc_shift
.bc_shrunk:
    dec r8
    mov [rdi], r8
    jmp .bc_loop
.bc_next:
    inc r9
    jmp .bc_loop
.bc_done:
    xor eax, eax
    ret

; Vector: 4 x int32 absolute offsets from the blob start (last 16 bytes).
align 4
genop_vec:
    dd buf_take
    dd buf_free
    dd buf_purge
    dd buf_compact
