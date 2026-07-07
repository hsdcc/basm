section .text
global _start
_start:
    nop
    nop
    nop
    .align 16
    mov rax, 60
    xor rdi, rdi
    syscall
; expect: 0
