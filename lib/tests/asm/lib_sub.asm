section .text
global _start
_start:
    mov rax, 60
    mov rdi, 10
    sub rdi, 5
    syscall
