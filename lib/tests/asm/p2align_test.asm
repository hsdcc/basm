section .text
global _start
_start:
    nop
    .p2align 4
    mov rax, 60
    xor rdi, rdi
    syscall
; expect: 0
