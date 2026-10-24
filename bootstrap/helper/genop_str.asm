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

; ---------------------------------------------------------------------------
; R4.7: Buffer handle table (handle -> block offset) and moving compaction.
;
; Table layout (in the generated program's data segment):
;   [ht+0]  = slot count (ever allocated, <= 128)
;   [ht+8]  = live count (informational)
;   [ht+16 + i*16] = { off, size }   size == 0 means the slot is free
;
; A Buffer handle is the *slot index*, so moving a block only rewrites the
; table entry; Buffer variables/Result payloads stay valid.  Raw arena blocks
; and Str boxes are not in this table and are therefore non-movable (pinned).
;
; ABI:
;   buf_hreg(rdi=&ht, rsi=off, rdx=size) -> rax = handle or -1
;   buf_hget(rdi=&ht, rsi=handle)        -> rax = off or -1
;   buf_hfree(rdi=&ht, rsi=handle)       -> rax = 0 or -1
;   buf_hpurge(rdi=&ht, rsi=limit)       -> rax = 0 (invalidate off >= limit)
;   buf_hcompact(rdi=&free, rsi=&ht, rdx=&base, rcx=&current) -> rax = moved
; ---------------------------------------------------------------------------

buf_hreg:
    mov r8, [rdi]
    xor r9d, r9d
.hr_find:
    cmp r9, r8
    jae .hr_append
    mov rax, r9
    shl rax, 4
    lea rcx, [rdi+16]
    add rcx, rax
    cmp qword [rcx+8], 0
    je .hr_store
    inc r9
    jmp .hr_find
.hr_append:
    cmp r8, 128
    jae .hr_fail
    mov r9, r8
    inc r8
    mov [rdi], r8
    mov rax, r9
    shl rax, 4
    lea rcx, [rdi+16]
    add rcx, rax
.hr_store:
    mov [rcx], rsi
    mov [rcx+8], rdx
    mov rax, r9
    ret
.hr_fail:
    mov rax, -1
    ret

buf_hget:
    mov rax, [rdi]
    cmp rsi, rax
    jae .hg_fail
    mov rax, rsi
    shl rax, 4
    lea rcx, [rdi+16]
    add rcx, rax
    cmp qword [rcx+8], 0
    je .hg_fail
    mov rax, [rcx]
    ret
.hg_fail:
    mov rax, -1
    ret

buf_hfree:
    mov rax, [rdi]
    cmp rsi, rax
    jae .hf_fail
    mov rax, rsi
    shl rax, 4
    lea rcx, [rdi+16]
    add rcx, rax
    cmp qword [rcx+8], 0
    je .hf_fail
    mov qword [rcx+8], 0
    xor eax, eax
    ret
.hf_fail:
    mov rax, -1
    ret

buf_hpurge:
    mov r8, [rdi]
    xor r9d, r9d
.hp_loop:
    cmp r9, r8
    jae .hp_done
    mov rax, r9
    shl rax, 4
    lea rcx, [rdi+16]
    add rcx, rax
    cmp qword [rcx+8], 0
    je .hp_next
    mov rax, [rcx]
    cmp rax, rsi
    jb .hp_next
    mov qword [rcx+8], 0
.hp_next:
    inc r9
    jmp .hp_loop
.hp_done:
    xor eax, eax
    ret

buf_hcompact:
    push rbp
    push rbx
    push r12
    push r13
    push r14
    push r15
    sub rsp, 8
    mov r12, rdi            ; free table
    mov r13, rsi            ; handle table
    mov r14, rdx            ; &base
    mov r15, rcx            ; &current
    xor ebx, ebx            ; total moved
.hc_pass:
    xor r10d, r10d          ; slot index
    xor r11d, r11d          ; moves in this pass
.hc_loop:
    mov rax, [r13]
    cmp r10, rax
    jae .hc_pass_end
    mov rax, r10
    shl rax, 4
    lea rcx, [r13+16]
    add rcx, rax
    mov r8, [rcx+8]         ; size
    test r8, r8
    jz .hc_next
    mov r9, [rcx]           ; old off
    mov rax, [r12]          ; free count
    xor ebp, ebp
.hc_hole:
    cmp rbp, rax
    jae .hc_next
    mov rdi, rbp
    shl rdi, 4
    lea rsi, [r12+8]
    add rsi, rdi            ; hole entry
    mov rdi, [rsi+8]        ; hole size
    cmp rdi, r8
    jb .hc_hole_next
    mov rcx, [rsi]          ; hole off
    mov rdx, rcx
    add rdx, r8
    cmp rdx, r9             ; only move downward, hole end <= old off
    ja .hc_hole_next
    ; copy: dst = base+hole_off, src = base+old_off, count = size
    push rsi                ; hole entry
    push rcx                ; dst off
    push r8                 ; size
    push r9                 ; old off
    mov rax, [r14]
    lea rdi, [rax+rcx]
    lea rsi, [rax+r9]
    mov rcx, r8
    rep movsb
    pop r9
    pop r8
    pop rdx                 ; dst off
    pop rsi                 ; hole entry
    ; shrink or remove the consumed hole
    mov rax, [rsi+8]
    sub rax, r8
    cmp rax, 8
    jb .hc_hole_remove
    add [rsi], r8
    mov [rsi+8], rax
    jmp .hc_hole_done
.hc_hole_remove:
    mov rax, [r12]          ; count
    mov rdi, rbp
.hc_shift:
    inc rdi
    cmp rdi, rax
    jae .hc_shrunk
    mov rcx, rdi
    shl rcx, 4
    lea rdx, [r12+8]
    add rdx, rcx            ; src entry (j+1)
    mov rcx, rdi
    dec rcx
    shl rcx, 4
    lea rsi, [r12+8]
    add rsi, rcx            ; dst entry (j)
    mov rcx, [rdx]
    mov [rsi], rcx
    mov rcx, [rdx+8]
    mov [rsi+8], rcx
    jmp .hc_shift
.hc_shrunk:
    dec rax
    mov [r12], rax
.hc_hole_done:
    ; handle entry -> new off; header data_off = new off + 32
    mov rax, r10
    shl rax, 4
    lea rcx, [r13+16]
    add rcx, rax
    mov [rcx], rdx
    mov rax, [r14]
    add rax, rdx
    lea rcx, [rdx+32]
    mov [rax], rcx
    ; insert the old block into the free list
    push r10
    push r11
    push rbx
    mov rdi, r12
    mov rsi, r9
    mov rdx, r8
    call buf_free
    pop rbx
    pop r11
    pop r10
    inc rbx
    inc r11
.hc_next:
    inc r10
    jmp .hc_loop
.hc_pass_end:
    ; repeat until a pass makes no progress (moves only go downward)
    test r11, r11
    jnz .hc_pass
.hc_trim:
    ; drop trailing holes and lower `current` accordingly
    mov rax, [r12]
    test rax, rax
    jz .hc_done
    mov rcx, rax
    dec rcx
    shl rcx, 4
    lea rsi, [r12+8]
    add rsi, rcx
    mov rdx, [rsi]
    add rdx, [rsi+8]        ; hole end (relative)
    mov rcx, [r15]          ; current absolute
    sub rcx, [r14]          ; used
    cmp rdx, rcx
    jne .hc_done
    mov rdi, [r14]
    add rdi, [rsi]
    mov [r15], rdi
    mov rax, [r12]
    dec rax
    mov [r12], rax
    jmp .hc_trim
.hc_done:
    mov rax, rbx
    add rsp, 8
    pop r15
    pop r14
    pop r13
    pop r12
    pop rbx
    pop rbp
    ret
.hc_hole_next:
    inc rbp
    jmp .hc_hole

; Vector: 12 x int32 absolute offsets from the blob start (last 48 bytes).
align 4
genop_vec:
    dd buf_take
    dd buf_free
    dd buf_purge
    dd buf_compact
    dd buf_hreg
    dd buf_hget
    dd buf_hfree
    dd buf_hcompact
    dd buf_hpurge
    dd 0
    dd 0
    dd 0
