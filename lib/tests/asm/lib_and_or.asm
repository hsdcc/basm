section .text
global _start
_start:
    mov rax, 5
    or rax, 2
    and rax, 3
    mov rdi, rax
    mov rax, 60
    syscall
