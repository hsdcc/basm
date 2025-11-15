section .text
global _start
_start:
    mov rax, 42
    neg rax
    mov rdi, rax
    mov rax, 60
    syscall
