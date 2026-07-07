section .text
global _start
_start:
    ; mov r8, r9 (two extended regs)
    mov r9, 42
    mov r8, r9
    cmp r8, 42
    jne fail
    
    ; extended reg with memory
    sub rsp, 16
    mov r8, 99
    mov [rsp], r8
    mov r9, [rsp]
    cmp r9, 99
    jne fail
    
    ; add extended regs
    mov r10, 10
    mov r11, 32
    add r10, r11
    cmp r10, 42
    jne fail
    
    ; push/pop extended regs
    mov r12, 77
    push r12
    pop r13
    cmp r13, 77
    jne fail
    
    ; lea with extended dest
    lea r14, [rsp]
    mov r15, r14
    cmp rsp, r15
    jne fail
    
    ; xor idiom
    xor r15, r15
    test r15, r15
    jne fail
    
    add rsp, 16
    xor rdi, rdi
    jmp ok
fail:
    mov rdi, 1
ok:
    mov rax, 60
    syscall
; expect: 0
