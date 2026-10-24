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
    mov rax, [r8]
    mov r15, rax
    add r15, rbx
    cmp r15, [r9]
    ja .oom
    mov [r8], r15
    mov r15, rax
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
    ; R4.3: arena exhausted -> Err box (tag 9, empty payload), current unchanged.
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
