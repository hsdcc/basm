section .text
global _start
_start:
    cld
    mov rax, 60
    xor rdi, rdi
    syscall
; expect: 0