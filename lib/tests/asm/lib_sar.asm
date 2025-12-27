; expect: 254
section .text
global _start
_start:
    mov rax, -8
    sar rax, 2
    mov rdi, rax
    mov rax, 60
    syscall