section .text
global _start
_start:
    mov rax, 8
    shl rax, 1
    shr rax, 2
    mov rdi, rax
    mov rax, 60
    syscall
